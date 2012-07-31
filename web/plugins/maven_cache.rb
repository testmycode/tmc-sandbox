require 'sandbox_app'
require 'fileutils'
require 'tempfile'
require 'tmpdir'
require 'shellwords'
require 'digest'

require 'shell_utils'
require 'ext2_utils'
require 'closeable_wrapper'
require 'subprocess_group_with_timeout'
require 'disk_cache'
require 'paths'
require 'signal_handlers'

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
# The cache may be explicitly populated by POSTing a tar file with a pom.xml as
# the file parameter to /maven_cache/populate.json.
#
# System requirements:
# 
# A squid proxy must be configured with a dedicated TAP device for this plugin.
# See site.defaults.yml.
#
# Implementation details:
# 
# To reduce contention and unnecessary swaps, the plugin starts a daemon.
# The daemon processes Maven projects dropped into the workdir until it's empty. Then it exits.
# To prevent race conditions, the workdir is protected by a lock.
# The lock is acquired before writing to the workdir and trying to start the daemon.
# The daemon acquires the lock to atomically check if the workdir is empty and exit if so.
# This way, if there are tasks to be executed, a daemon is always executing them.
#
class MavenCache < SandboxApp::Plugin
  def initialize(*args)
    super

    if @plugin_settings['alternate_work_dir']
      @work_dir = Pathname(@plugin_settings['alternate_work_dir'])
    else
      @work_dir = Paths.work_dir + 'maven_cache'
    end
    FileUtils.mkdir_p(@work_dir)
    @work_dir = @work_dir.realpath.to_s

    @img1path = "#{@work_dir}/1.img"
    @img2path = "#{@work_dir}/2.img"
    @symlink = "#{@work_dir}/current.img"
    @tap_device = @plugin_settings['tap_device']
    @tap_ip = @plugin_settings['tap_ip']
    
    @script_path = "#{File.dirname(File.realpath(__FILE__))}/maven_cache"
    
    @tasks_dir = "#{@work_dir}/tasks"
    FileUtils.mkdir_p(@tasks_dir)
    
    @current_task_path = "#{@work_dir}/current-task.tar"
    @log_tar_path = "#{@work_dir}/log.tar"
    @rsync_log_tar_path = "#{@work_dir}/rsync-log.tar"
    @file_list_log_tar_path = "#{@work_dir}/list-log.tar"
    @tasks_lock = "#{@work_dir}/tasks.lock"
    @daemon_pidfile = "#{@work_dir}/daemon.pid"
    
    @maven_projects_seen = 0
    @maven_projects_skipped_immediately = 0
    @daemon_start_count = 0

    @projects_seen_cache = DiskCache.get("maven_projects_seen")
    if [@img1path, @img2path].any? {|path| !File.exist?(path) }
      AppLog.debug "Maven cache clearing projects_seen_cache since image file(s) don't exist"
      @projects_seen_cache.clear
    end
  end
  
  attr_reader :maven_projects_seen
  attr_reader :maven_projects_skipped_immediately
  attr_reader :daemon_start_count

  def before_exec(options)
    start_caching_deps(options[:tar_file])
  end

  def shut_down
    kill_daemon_if_running
    wait_for_daemon
  end
  
  def start_caching_deps(project_file)
    if pom_xml_file?(project_file) || maven_project?(project_file)
      @maven_projects_seen += 1
      if !can_skip?(project_file)
        add_task(project_file)
      else
        @maven_projects_skipped_immediately += 1
        AppLog.debug "Maven project's deps already cached. Skipping."
      end
    else
      AppLog.debug("Not a maven project. Skipping maven cache.")
    end
  end

  def kill_daemon_if_running
    File.open(@daemon_pidfile, File::RDONLY | File::CREAT) do |pidfile|
      begin
        pid = pidfile.read.strip.to_i
        if pid > 0
          AppLog.debug("Killing maven cache daemon (pid #{pid})")
          Process.kill("TERM", pid)
        end
      rescue
        # nothing
      end
    end
  end

  def daemon_running?
    running = false
    File.open(@daemon_pidfile, File::RDONLY | File::CREAT) do |pidfile|
      running = !pidfile.flock(File::LOCK_EX | File::LOCK_NB)
      pidfile.flock(File::LOCK_UN)
    end
    running
  end
  
  def wait_for_daemon
    File.open(@daemon_pidfile, File::RDONLY | File::CREAT) do |pidfile|
      pidfile.flock(File::LOCK_EX)
      File.delete(@daemon_pidfile)
      pidfile.flock(File::LOCK_UN)
    end
  end

  def extra_images(options)
    if File.exist?(@symlink)
      {'ubddrc' => @symlink}
    else
      {}
    end
  end

  def get_files_in_cache
    return [] if !File.exist?(@symlink)
    img = ImageFile.new(@symlink, nil)
    img.lock(File::LOCK_SH)
    begin
      tmpfile = Tempfile.new(['filelist', '.tar'])
      prepare_empty_log_tar_file(tmpfile.path, '8M')
      begin
        AppLog.debug("Reading file list from #{File.readlink(@symlink)}")
        run_uml_command('filelist', @file_list_log_tar_path, @symlink, tmpfile.path, false)
        output = ShellUtils.sh!(['tar', '--to-stdout', '-xf', tmpfile.path, 'output.txt'])
        return output.split("\n")
      ensure
        tmpfile.delete
        tmpfile.close
      end
    ensure
      img.unlock
    end
  end

  def can_serve_request?(req)
    main_page_request?(req) || post_request?(req) || files_request?(req) || artifacts_request?(req)
  end

  def serve_request(req, resp, respdata)
    if post_request?(req)
      raise SandboxApp::BadRequest.new('missing file parameter') if !req['file'] || !req['file'][:tempfile]
      start_caching_deps(req['file'][:tempfile].path)
      respdata[:status] = 'ok'
    elsif main_page_request?(req)
      serve_main_page(req, resp, respdata)
    elsif files_request?(req)
      serve_files_request(req, resp, respdata)
    elsif artifacts_request?(req)
      serve_artifacts_request(req, resp, respdata)
    end
  end

  def main_page_request?(req)
    req.get? && req.path == '/maven_cache.html'
  end

  def post_request?(req)
    req.post? && req.path == '/maven_cache/populate.json'
  end

  def files_request?(req)
    req.get? && req.path == '/maven_cache/files.html'
  end

  def artifacts_request?(req)
    req.get? && req.path == '/maven_cache/artifacts.html'
  end

  def serve_main_page(req, resp, respdata)
    respdata << <<EOS
<!doctype html>
<html>
<head><title>Maven cache</title></head>
<body>
  <div>
    <ul>
      <li><a href="/maven_cache/artifacts.html">List of artifacts in cache</a></li>
      <li><a href="/maven_cache/files.html">List of files in cache</a></li>
    </ul>
  </div>
  <div>
    <h3>Add POM file</h3>
    <form action="/maven_cache/populate.json" enctype="multipart/form-data" method="post">
      POM file: <input type="file" name="file" /><br />
      <input type="submit" />
    </form>
  </div>
</body>
</html>
EOS
  end

  def serve_files_request(req, resp, respdata)
    files = get_files_in_cache
    respdata << <<EOS
<!doctype html>
<html>
<head><title>Maven cache files</title></head>
<body>
  <div>
    #{files.sort.join("<br/>\n    ")}
  </div>
</body>
</html>
EOS
  end

  def serve_artifacts_request(req, resp, respdata)
    files = get_files_in_cache
    artifacts = files.map do |f|
      if f =~ /^.\/maven\/repository\/(.*)\/[^\/]+\.pom$/
        path = $1.split("/")
        version = path.pop
        name = path.pop
        group = path.join(".")
        "#{group}:#{name}:#{version}"
      else
        nil
      end
    end.reject(&:nil?)

    respdata << <<EOS
<!doctype html>
<html>
<head><title>Maven cache artifacts</title></head>
<body>
  <div>
    #{artifacts.sort.join("<br />\n    ")}
  </div>
</body>
</html>
EOS
  end
  
private

  class ImageFile
    def initialize(path, size)
      @path = path

      create(size) if !File.exist?(@path) && size != nil

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
      if !File.exist?(symlink)
        AppLog.debug "Creating symlink #{symlink} -> #{img1.path}"
        File.symlink(img1.path, symlink)
      end
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
      AppLog.debug "Setting symlink #{@symlink} -> #{backimg.path}"
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

  def maven_project?(project_file)
    `tar -tf #{project_file}`.strip.split("\n").any? {|f| f == 'pom.xml' || f == './pom.xml' }
  end

  def pom_xml_file?(file)
    ty = ShellUtils.sh!(['file', '--mime-type', file])
    ty.include?("text/html") ||
      ty.include?("text/xml") ||
      ty.include?("application/xml") ||
      ty.include?("text/plain")
  end

  def can_skip?(project_file)
    @projects_seen_cache.get(checksum_pom_xml(project_file)) != nil
  end

  def mark_pom_file_processed_in_cache(tar_file)
    @projects_seen_cache.put(checksum_pom_xml(tar_file), '1')
  end

  def checksum_pom_xml(project_file)
    if pom_xml_file?(project_file)
      pom_xml = File.read(project_file)
    else
      file_list = ShellUtils.sh!(['tar', '-tf', project_file])
      pom_file_name = file_list.strip.split("\n").find {|f| f == 'pom.xml' || f == './pom.xml' }
      pom_xml = ShellUtils.sh!(['tar', '--to-stdout', '-xf', project_file, pom_file_name])
    end
    Digest::SHA2.hexdigest(pom_xml)
  end

  def add_task(project_file)
    begin
      with_flock(@tasks_lock) do |tasks_lock_file|
        task_file = Tempfile.new(["task", ".tar"], @tasks_dir)
        task_file.close
        if pom_xml_file?(project_file)
          AppLog.info("Adding project pom.xml to maven cache")
          pom_file = "#{@work_dir}/pom.xml"
          begin
            FileUtils.cp(project_file, pom_file)
            ShellUtils.sh!(['tar', '-C', @work_dir, '-cf', task_file.path, "pom.xml"])
          ensure
            File.delete(pom_file)
          end
        else
          AppLog.info("Adding project tar file to maven cache")
          FileUtils.cp(project_file, task_file.path)
        end

        start_daemon_unless_running([tasks_lock_file])
      end
    rescue
      AppLog.warn("Failed to send project to maven cache")
      raise
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
    pidfile = File.open(@daemon_pidfile, File::WRONLY | File::CREAT)
    if pidfile.flock(File::LOCK_EX | File::LOCK_NB) == 0
      begin
        AppLog.debug("Starting maven cache daemon")
        @daemon_start_count += 1
        pid = Process.fork do # Inherit flock on pidfile
          SignalHandlers.restore_original_handler(SignalHandlers.termination_signals)
          begin
            files_to_close.each(&:close) # relinquishes this copy of flock
            run_daemon
          rescue
            AppLog.error "Maven cache daemon crashed: #{AppLog.fmt_exception($!)}"
          ensure
            begin
              pidfile.close
              File.delete(@daemon_pidfile)
            ensure
              exit!(0)
            end
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
            AppLog.debug "Maven cache daemon sees no more tasks."
            exiting = true
          end
        end
        
        if exiting
          imgpair.unlock_both_and_swap
          imgpair.lock_back_rw

          imgpair.lock_front_ro
          begin
            AppLog.debug "Ryncing from  #{imgpair.frontimg.path} to #{imgpair.backimg.path}"
            rsync(imgpair.frontimg.path, imgpair.backimg.path)
          ensure
            imgpair.unlock_front
          end
          
          # Check if a new task has appeared while we were swapping and rsyncing.
          # If so, we must not exit yet, since no daemon would then handle the task.
          with_flock(@tasks_lock) do
            if (Dir.entries(@tasks_dir) - ['.', '..']).empty?
              # Exit while holding tasksdir lock.
              # Prevents the race where a sandbox adds a task but sees the exiting daemon as active.
              AppLog.debug "Maven cache daemon exiting."
              exit!(0)
            else
              # More tasks appeared while rsyncing. Continue.
              exiting = false
            end
          end
        else
          if !can_skip?(@current_task_path)
            AppLog.debug "Downloading Maven dependencies into #{imgpair.backimg.path}"
            if download_deps(@current_task_path, imgpair.backimg.path)
              AppLog.debug "Dependencies downloaded successfully"
              mark_pom_file_processed_in_cache(@current_task_path)
            else
              AppLog.warn "Failed to download dependencies"
            end
          else
            AppLog.debug "Skipping downloading Maven dependencies. This project was recently downloaded."
          end
          FileUtils.rm_f(@current_task_path)
        end
        
      end
    ensure
      imgpair.close
    end
  end
  
  def download_deps(tar_file, backimg_path)
    run_uml_command('getdeps', @log_tar_path, tar_file, backimg_path)
  end
  
  def rsync(from, to)
    run_uml_command('rsync', @rsync_log_tar_path, from, to)
  end

  def run_uml_command(command, log_tar_path, ro_image, rw_image, network = true)
    with_script_tar_file(command) do |script_tar_file|
      run_uml_script(script_tar_file, log_tar_path, ro_image, rw_image, network)
    end
  end

  def run_uml_script(script_tar_path, log_tar_path, ro_image, rw_image, network = true)
    prepare_empty_log_tar_file(log_tar_path, "4M") if log_tar_path

    subprocess = SubprocessGroupWithTimeout.new(@plugin_settings['download_timeout'].to_i, AppLog.get) do
      cmd = []
      cmd << Paths.kernel_path
      cmd << "initrd=#{Paths.initrd_path}"
      cmd << "mem=256M"
      cmd << "ubdarc=#{Paths.rootfs_path}"
      cmd << "ubdbr=#{script_tar_path}"
      cmd << "ubdc=#{log_tar_path}" if log_tar_path
      cmd << "ubddrc=#{ro_image}"
      cmd << "nomount_ubdd"
      cmd << "ubde=#{rw_image}"
      cmd << "nomount_ubde"
      cmd << "eth0=tuntap,#{@tap_device},,#{@tap_ip}" if network
      cmd << "run_tarred_script:/dev/ubdb"
      cmd << "con=null" # con=xterm can be used for debugging, if UML is modified to pass '-l' to it.

      $stdin.reopen("/dev/null")
      $stdout.reopen("/dev/null")
      $stderr.reopen($stdout)

      # Increase the nicelevel (lower the priority) of this process
      oldprio = Process.getpriority(Process::PRIO_PROCESS, 0)
      Process.setpriority(Process::PRIO_PROCESS, 0, oldprio + 5)

      MiscUtils.cloexec_all_except([$stdin, $stdout, $stderr])
      Process.exec(Shellwords.join(cmd.map(&:to_s)))
    end

    pin, pout = IO.pipe
    subprocess.when_done do |status|
      pin.close
      begin
        if status == :timeout
          output = '0'
        else
          output = if status.success? then '1' else '0' end
        end
        pout.write(output)
      rescue Errno::EPIPE
        # Possible if the maven cache daemon is killed while we work. Ignore.
      ensure
        pout.close
      end
    end

    success = false
    SignalHandlers.with_trap(SignalHandlers.termination_signals, lambda { subprocess.kill }) do
      begin
        subprocess.start
        pout.close
        success = (pin.read == '1')
        pin.close
      rescue
        success = false
      end
      subprocess.wait
    end

    success
  end

  def with_script_tar_file(command, &block)
    Tempfile.open(['script', '.tar']) do |script_tar_file|
      begin
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
            script_tar_file.path,
            'tmc-run',
            'getdeps.sh'
          ]
        end
        return block.call(script_tar_file.path)
      ensure
        script_tar_file.delete
      end
    end
  end
  
  def prepare_empty_log_tar_file(log_tar_path, size)
    ShellUtils.sh! ["dd", "if=/dev/zero", "of=#{log_tar_path}", "bs=#{size}", "count=1"]
  end
end

