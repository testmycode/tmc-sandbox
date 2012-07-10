require 'paths'
require 'subprocess_group_with_timeout'

class SandboxInstance
  def initialize(index, settings, plugin_manager)
    @index = index
    @settings = settings
    @plugin_manager = plugin_manager
    nuke_work_dir!

    @subprocess = SubprocessGroupWithTimeout.new(@settings['timeout'].to_i, SandboxApp.debug_log) do
      $stdin.close
      $stdout.reopen("#{vm_log_path}", "w")
      $stderr.reopen($stdout)
      nocloexec = [$stdout, $stderr]

      `dd if=/dev/zero of=#{output_tar_path} bs=#{@settings['max_output_size']} count=1`
      exit!(1) unless $?.success?

      args = [
        "#{Paths.kernel_path}",
        "initrd=#{Paths.initrd_path}",
        "ubdarc=#{Paths.rootfs_path}",
        "ubdbr=#{@tar_file.path}",
        "ubdc=#{output_tar_path}",
        "mem=#{@settings['instance_ram']}",
        "con=null"
      ]
      if @settings['extra_image_ubdd']
        ubdd = @settings['extra_image_ubdd']
        debug "Using #{ubdd} as ubdd"
        args << "ubddrc=#{ubdd}"
        ubdd_file = File.open(ubdd, File::RDONLY)
        ubdd_file.flock(File::LOCK_SH) # Released when UML exits
        nocloexec << ubdd_file
      end
      if @settings['extra_uml_args'].is_a?(Enumerable)
        args += @settings['extra_uml_args']
      elsif @settings['extra_uml_args'].is_a?(String)
        args << @settings['extra_uml_args']
      end

      #TODO: networking

      cmd = Shellwords.join(args)

      debug "PID #{Process.pid} executing: #{cmd}"
      MiscUtils.cloexec_all_except(nocloexec)
      Process.exec(cmd)
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

    @plugin_manager.run_hook(:before_exec, :tar_file => @tar_file)
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

  def debug(msg)
    log_with_level(:debug, msg)
  end

  def warn(msg)
    log_with_level(:warn, msg)
  end

  def log_with_level(level, msg)
    SandboxApp.debug_log.send(level, "Instance #{@index}: #{msg}")
  end
end