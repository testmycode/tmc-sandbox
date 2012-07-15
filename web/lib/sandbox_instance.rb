require 'paths'
require 'subprocess_group_with_timeout'
require 'app_log'

class SandboxInstance
  attr_reader :index

  def initialize(index, settings, plugin_manager)
    @index = index
    @settings = settings
    @plugin_manager = plugin_manager
    nuke_work_dir!

    @subprocess = SubprocessGroupWithTimeout.new(@settings['timeout'].to_i, AppLog) do
      begin
        $stdin.close
        $stdout.reopen("#{vm_log_path}", "w")
        $stderr.reopen($stdout)
        nocloexec = [$stdout, $stderr]

        `dd if=/dev/zero of=#{output_tar_path} bs=#{@settings['max_output_size']} count=1`
        exit!(201) unless $?.success?

        args = [
          "#{Paths.kernel_path}",
          "initrd=#{Paths.initrd_path}",
          "ubdarc=#{Paths.rootfs_path}",
          "ubdbr=#{@tar_file}",
          "ubdc=#{output_tar_path}",
          "mem=#{@settings['instance_ram']}",
          "con=null"
        ]

        for name, path in @plugin_images
          debug "Adding #{name}=#{path}"
          if name =~ /^(ubd.)(r?)(c?)$/
            args << "#{name}=#{path}"

            lock_type = if $2 == 'r' then File::LOCK_SH else File::LOCK_EX end
            f = File.open(path, File::RDONLY)
            f.flock(lock_type)
            nocloexec << f
          else
            error "Error in plugin_images"
            exit!(202)
          end
        end

        args += network_args

        cmd = Shellwords.join(args)

        debug "PID #{Process.pid} executing: #{cmd}"
        MiscUtils.cloexec_all_except(nocloexec)
        Process.exec(cmd)
      rescue
        error("Sandbox execution failed: " + AppLog.fmt_exception($!))
      ensure
        exit!(210)
      end
    end

    @subprocess.when_done do |process_status|
      exit_code = nil
      status =
        if process_status == :timeout
          :timeout
        elsif process_status.success?
          begin
            exit_code = extract_file_from_tar(output_tar_path, 'exit_code.txt').to_i
          rescue
            warn "Failed to untar exit_code.txt"
            exit_code = nil
          end
          if exit_code == 0
            :finished
          else
            :failed
          end
        else
          warn "Sandbox failed with status #{process_status.inspect}"
          :failed
        end

      debug "Status: #{status}. Exit code: #{exit_code.inspect}."

      output = {
        'test_output' => try_extract_file_from_tar(output_tar_path, 'test_output.txt'),
        'stdout' => try_extract_file_from_tar(output_tar_path, 'stdout.txt'),
        'stderr' => try_extract_file_from_tar(output_tar_path, 'stderr.txt')
      }

      @notifier.call(status, exit_code, output) if @notifier
    end
  end

  # Runs the sandbox. Notifier is called with
  # status string, exit code, output hash
  def start(tar_file, &notifier)
    raise 'busy' if busy?

    nuke_work_dir!
    @tar_file = tar_file
    @notifier = notifier

    @plugin_images = @plugin_manager.run_hook(:extra_images, :instance => self).reduce({}, &:merge)

    @plugin_manager.run_hook(:before_exec, :instance => self, :tar_file => tar_file)
    @subprocess.start
  end

  def idle?
    !busy?
  end

  def busy?
    @subprocess.running?
  end

  def wait
    @subprocess.wait
  end

  def kill
    @subprocess.kill
  end

private

  def nuke_work_dir!
    debug "Clearing work dir"
    FileUtils.rm_rf instance_work_dir
    FileUtils.mkdir_p instance_work_dir
  end

  def instance_work_dir
    Paths.work_dir + @index.to_s
  end

  def vm_log_path
    instance_work_dir + 'vm.log'
  end

  def output_tar_path
    instance_work_dir + 'output.tar'
  end

  def extract_file_from_tar(tar_path, file_name)
    result = `tar --to-stdout -xf #{output_tar_path} #{file_name} 2>/dev/null`
    raise "Failed to extract #{file_name} from #{tar_path}" if !$?.success?
    result
  end

  def try_extract_file_from_tar(tar_path, file_name)
    begin
      extract_file_from_tar(tar_path, file_name)
    rescue
      ""
    end
  end

  def network_args
    if @settings['network'] && @settings['network']['enabled']
      i = @index
      tapdev = "tap_tmc#{i}"
      ip_range_start = @settings['network']['private_ip_range_start']
      ip = "192.168.#{ip_range_start + i}.1"
      ["eth0=tuntap,#{tapdev},,#{ip}"]
    else
      []
    end
  end

  def debug(msg)
    log_with_level(:debug, msg)
  end

  def warn(msg)
    log_with_level(:warn, msg)
  end

  def error(msg)
    log_with_level(:error, msg)
  end

  def log_with_level(level, msg)
    AppLog.send(level, "Instance #{@index}: #{msg}")
  end
end