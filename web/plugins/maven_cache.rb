require 'fileutils'
require 'tempfile'
require 'tmpdir'
require 'shellwords'

require 'shell_utils'
require 'ext2_utils'
require 'closeable_wrapper'
require 'subprocess_with_timeout'

#
# Recognizes Maven projects and downloads their dependencies to a local repository
# in the background.
# 
# The cache employs double buffering. The repository resides in an ext2 image file
# called the back buffer. Another ext2 image called the front buffer is in
# read-only use by the sandbox. When dependencies have been downloaded to the back buffer,
# the buffers are swapped and the changes are rsynced back to the new back buffer.
# 
# The buffer swap is implemented as an atomic symlink replace.
# The sandbox should be configured so that ubdd points to the symlink.
# 
# It's safe to run multiple sandboxes with this plugin using same maven cache files.
# The sandbox acquires a shared flock on its ubdd file.
# Writing to the back buffer is done under an exclusive flock.
# If the sandbox is using the cache while buffers are swapped,
# writes to what becomes the back buffer will block until the sandbox releases
# its lock.
# 
# It's possible for the daemon to fail e.g. because it ran out of space on an image.
# In this case, the image is likely (given maven's correctness) to be left in a
# usable state and the daemon will eventually be started again and try again,
# until an administrator resolves the situation. TODO: better error reporting
#
# System requirements:
# 
# A squid proxy must be configured with a dedicated TAP device for this plugin.
# See site.defaults.yml and the readme.
#
# Implementation details:
# 
# To reduce contention and unnecessary swaps, the plugin starts a daemon (at most one even if workdir is shared).
# The daemon processes Maven projects dropped into the workdir until it's empty. Then it exits.
# To prevent race conditions, the workdir is protected by a lock.
# The lock is acquired before writing to the workdir and trying to start the daemon.
# The daemon acquires the lock to atomically check if the workdir is empty and exit if so.
# This way, if there are tasks to be executed, a daemon is always executing them.
#
class MavenCache < SandboxApp::Plugin
  def initialize(*args)
    super
    
    @img1path = abspath_mkdir(@plugin_settings['img1'])
    @img2path = abspath_mkdir(@plugin_settings['img2'])
    @symlink = abspath_mkdir(@plugin_settings['symlink'])
    @work_dir = abspath_mkdir(@plugin_settings['work_dir'])
    @tap_device = @plugin_settings['tap_device']
    @tap_ip = @plugin_settings['tap_ip']
    
    @script_path = "#{File.dirname(File.realpath(__FILE__))}/maven_cache"
    
    @tasks_dir = "#{@work_dir}/tasks"
    FileUtils.mkdir_p(@tasks_dir)
    
    @current_task_path = "#{@work_dir}/current-task.tar"
    @script_tar_path = "#{@work_dir}/script.tar"
    @log_tar_path = "#{@work_dir}/log.tar"
    @rsync_log_tar_path = "#{@work_dir}/rsync-log.tar"
    @tasks_lock = "#{@work_dir}/tasks.lock"
    @tasks_pidfile = "#{@work_dir}/tasks.pid"
    
    @maven_projects_seen = 0
    @daemon_start_count = 0
  end
  
  attr_reader :maven_projects_seen
  attr_reader :daemon_start_count

  def before_exec(options)
    start_caching_deps(options[:tar_file])
  end
  
  def start_caching_deps(tar_file)
    if `tar -tf #{tar_file}`.strip.split("\n").any? {|f| f == 'pom.xml' || f == './pom.xml' }
      @maven_projects_seen += 1
      add_task(tar_file)
    end
  end
  
  def wait_for_daemon
    File.open(@tasks_pidfile, File::WRONLY | File::CREAT) do |pidfile|
      pidfile.flock(File::LOCK_EX)
      pidfile.flock(File::LOCK_UN)
    end
  end
  
private

  class ImageFile
    def initialize(path, default_size)
      @path = path
      
      create(default_size) if !File.exist?(@path)
      @imghandle = File.open(@path, File::RDONLY)
      @lock_mode = nil
    end
    
    attr_reader :path
    
    def lock(mode)
      @imghandle.flock(mode)
      @lock_mode = mode
    end
    
    def locked?
      @lock_mode != nil
    end
    
    def unlock
      @imghandle.flock(File::LOCK_UN) if locked?
      @lock_mode = nil
    end
    
    def close
      @imghandle.close
    end
    
  private
    def create(size)
      FileUtils.mkdir_p(File.dirname(path))
      
      ShellUtils.sh!(['fallocate', '-l', size, path])
      Ext2Utils.mke2fs(path)
    end
  end
  
  class ImagePair
    def initialize(img1, img2, symlink)
      @img1 = img1
      @img2 = img2
      @symlink = symlink
      File.symlink(img1.path, symlink) if !File.exist?(symlink)
      raise "#{symlink} should be a symlink" if !File.symlink?(symlink)
    end
    
    def lock_back_rw
      backimg.lock(File::LOCK_EX)
    end
    
    def lock_front_ro
      frontimg.lock(File::LOCK_SH)
    end
    
    def unlock_back
      backimg.unlock
    end
    
    def unlock_front
      frontimg.unlock
    end
    
    def unlock_both_and_swap
      unlock_front
      unlock_back
      set_symlink_atomic(backimg.path)
    end
    
    def frontimg
      buffer_order[0]
    end
    
    def backimg
      buffer_order[1]
    end
    
    def close
      begin
        @img1.close
      ensure
        @img2.close
      end
    end
    
  private
    def buffer_order
      case File.readlink(@symlink)
      when @img1.path
        [@img1, @img2]
      when @img2.path
        [@img2, @img1]
      else
        raise "Symlink doesn't point to either image file."
      end
    end
    
    def set_symlink_atomic(dest)
      Dir.mktmpdir("newlink", File.dirname(@symlink)) do |dir|
        newlink = "#{dir}/newlink"
        File.symlink(dest, newlink) # file.symlink doesn't overwrite
        File.rename(newlink, @symlink)
      end
    end
  end
  

  def abspath_mkdir(path)
    dir = File.dirname(path)
    basename = File.basename(path)
    FileUtils.mkdir_p(dir)
    "#{File.realpath(dir)}/#{basename}"
  end
  
  def add_task(tar_file)
    with_flock(@tasks_lock) do |tasks_lock_file|
      task_file = Tempfile.new(["task", ".tar"], @tasks_dir)
      task_file.close
      FileUtils.cp(tar_file, task_file.path)
      start_daemon_unless_running([tasks_lock_file])
    end
  end
  
  def with_flock(path, flags = File::LOCK_EX, unlock = true, &block)
    file = File.open(path, File::RDONLY | File::CREAT)
    file.flock(flags)
    begin
      block.call(file)
    ensure
      file.flock(File::LOCK_UN) if unlock
      file.close
    end
  end
  
  def start_daemon_unless_running(files_to_close)
    pidfile = File.open(@tasks_pidfile, File::WRONLY | File::CREAT)
    if pidfile.flock(File::LOCK_EX | File::LOCK_NB) == 0
      begin
        @daemon_start_count += 1
        pid = Process.fork do # Inherit flock on pidfile
          begin
            files_to_close.each(&:close) # relinquishes this copy of flock
            run_daemon
          ensure
            pidfile.close
            File.delete(pidfile)
          end
        end
        pidfile.truncate(0)
        pidfile.write(pid.to_s)
        Process.detach(pid)
      ensure
        pidfile.close # Child process may still hold lock
      end
    end
  end
  
  def run_daemon
    SandboxApp.debug_log.debug "Maven cache daemon starting."
    
    img1 = CloseableWrapper.new(ImageFile.new(@img1path, @plugin_settings['img_size']))
    img2 = CloseableWrapper.new(ImageFile.new(@img2path, @plugin_settings['img_size']))
    imgpair = CloseableWrapper.new(ImagePair.new(img1, img2, @symlink))
    
    imgpair.lock_back_rw
    
    begin
      loop do
      
        # Acquire tasksdir lock to atomically check if there are tasks
        # and move one to be processed if so.
        exiting = false
        with_flock(@tasks_lock) do
          file = (Dir.entries(@tasks_dir) - ['.', '..']).first
          if file != nil
            FileUtils.mv("#{@tasks_dir}/#{file}", @current_task_path)
          else
            exiting = true
          end
        end
        
        if exiting
          imgpair.unlock_both_and_swap
          imgpair.lock_back_rw
          
          imgpair.lock_front_ro
          Ext2Utils.fsck(imgpair.frontimg.path)
          rsync(imgpair.frontimg.path, imgpair.backimg.path)
          imgpair.unlock_front
          
          # Check if a new task has appeared while we were swapping and rsyncing.
          # If so, we must not exit yet, since no daemon would then handle the task.
          with_flock(@tasks_lock) do
            if (Dir.entries(@tasks_dir) - ['.', '..']).empty?
              # Exit while holding tasksdir lock.
              # Prevents the race where a sandbox adds a task but sees the exiting daemon as active.
              SandboxApp.debug_log.debug "Maven cache daemon has processed all tasks and exits."
              exit!(0)
            else
              # More tasks appeared while rsyncing. Continue.
              exiting = false
            end
          end
        else
          # TODO: short-circuit if we've seen the exact same POM before.
          # Is there an easy-to-configure disk-backed cache library we can call here?
          # Most importantly we need max lifetime
          
          SandboxApp.debug_log.debug "Downloading Maven dependencies into #{imgpair.backimg.path}"
          download_deps(@current_task_path, imgpair.backimg.path)
          FileUtils.rm_f(@current_task_path)
        end
        
      end
    ensure
      imgpair.close
    end
  end
  
  def download_deps(tar_file, backimg_path)
    run_uml_script('getdeps', @log_tar_path, tar_file, backimg_path)
  end
  
  def rsync(from, to)
    run_uml_script('rsync', @rsync_log_tar_path, from, to)
  end
  
  def run_uml_script(command, log_tar_path, ro_image, rw_image)
    prepare_script_tar_file(command)
    prepare_empty_log_tar_file(log_tar_path, "4M")
  
    root = @settings['sandbox_files_root']
    
    subprocess = SubprocessWithTimeout.new(@plugin_settings['download_timeout'].to_i, SandboxApp.debug_log) do
      $stdin.close
      $stdout.reopen("/dev/null", "w")
      $stderr.reopen($stdout)
      
      cmd = []
      cmd << "#{root}/linux.uml"
      cmd << "initrd=#{root}/initrd.img"
      cmd << "mem=256M"
      cmd << "ubdarc=#{root}/rootfs.squashfs"
      cmd << "ubdbr=#{@script_tar_path}"
      cmd << "ubdc=#{log_tar_path}"
      cmd << "ubdd=#{ro_image}" if ro_image
      cmd << "nomount_ubdd" if ro_image
      cmd << "ubde=#{rw_image}" if rw_image
      cmd << "eth0=tuntap,#{@tap_device},,#{@tap_ip}"
      cmd << "run_tarred_script:/dev/ubdb"
      cmd << "con=null"
      
      MiscUtils.cloexec_all_except([$stdout, $stderr])
      Process.exec(Shellwords.join(cmd))
    end
    
    subprocess.start
    subprocess.wait
  end
  
  def prepare_script_tar_file(command)
    Dir.mktmpdir do |tmpdir|
      File.open("#{tmpdir}/tmc-run", 'wb') do |f|
        f.write(File.read("#{@script_path}/tmc-run").gsub('__COMMAND__', command))
      end
      FileUtils.cp("#{@script_path}/getdeps.sh", "#{tmpdir}/getdeps.sh")
      ShellUtils.sh! [
        'tar',
        '-C',
        tmpdir,
        '-cf',
        @script_tar_path,
        'tmc-run',
        'getdeps.sh'
      ]
    end
  end
  
  def prepare_empty_log_tar_file(log_tar_path, size)
    ShellUtils.sh! ["dd", "if=/dev/zero", "of=#{log_tar_path}", "bs=#{size}", "count=1"]
  end
end

