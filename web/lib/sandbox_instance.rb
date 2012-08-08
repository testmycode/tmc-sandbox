require 'paths'
require 'subprocess_group_with_timeout'
require 'shellwords'
require 'app_log'
require 'uml_instance'
require 'tap_device'

class SandboxInstance
  attr_reader :index

  def initialize(index, settings, plugin_manager)
    @index = index
    @settings = settings
    @plugin_manager = plugin_manager
    nuke_work_dir!

    @instance = UmlInstance.new

    @instance.subprocess_init do
      `dd if=/dev/zero of=#{output_tar_path} bs=#{@settings['max_output_size']} count=1`
      raise "Failed to create output tar file" unless $?.success?
    end

    @instance.when_done do |process_status|
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
    @notifier = notifier
    FileUtils.mv(tar_file, task_tar_path)

    @plugin_images = @plugin_manager.run_hook(:extra_images, :instance => self).reduce({}, &:merge)

    @plugin_manager.run_hook(:before_exec, :instance => self, :tar_file => task_tar_path)

    file_locks = @plugin_images.map {|name, path|
      if name.to_s =~ /^(ubd.)c?(r?)c?$/
        lock_type = if $2 == 'r' then File::LOCK_SH else File::LOCK_EX end
        [path, lock_type]
      else
        raise "Invalid plugin image name: #{name}"
      end
    }

    @instance.set_options({
      :disks => @plugin_images.merge({
        :ubdarc => Paths.rootfs_path,
        :ubdbr => task_tar_path,
        :ubdc => output_tar_path
      }),
      :file_locks => file_locks,
      :mem => @settings['instance_ram'],
      :network => network_devices,
      :timeout => @settings['timeout'].to_i
    })

    @instance.start
  end

  def idle?
    !busy?
  end

  def busy?
    @instance.running?
  end

  def wait
    @instance.wait
  end

  def kill
    @instance.kill
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

  def output_tar_path
    instance_work_dir + 'output.tar'
  end

  def task_tar_path
    instance_work_dir + 'task.tar'
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

  def network_devices
    if @settings['network'] && @settings['network']['enabled']
      i = @index
      tapdev = "tap_tmc#{i}"
      ip_range_start = @settings['network']['private_ip_range_start']
      ip = "192.168.#{ip_range_start + i}.1"
      {:eth0 => TapDevice.new(tapdev, ip, Settings.tmc_user)}
    else
      {}
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