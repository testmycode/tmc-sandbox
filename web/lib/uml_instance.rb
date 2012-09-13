require 'subprocess_group_with_timeout'
require 'paths'
require 'settings'
require 'tap_device'

class UmlInstance
  def initialize(options = {})
    @options = default_options.merge(options)
  end

  attr_reader :options

  def set_options(options)
    @options = default_options.merge(options)
  end

  def default_options
    {
      :binary => Paths.kernel_path,
      :initrd => Paths.initrd_path,
      :disks => {
        :ubdarc => Paths.rootfs_path
      },
      :file_locks => [], # array of [path, flock_type]
      :mem => Settings.get['instance_ram'],
      :extra_options => [],
      :network => {
        # e.g. :eth0 => tap_device_object
      },
      :command => nil, # nil for normal sandboxes. e.g. run_tarred_script:/dev/ubdb
      :timeout => nil,
      :nicelevel => 0,
      :uml_dir => Paths.work_dir + 'uml',
      :log => AppLog.get,
      :vm_log => nil # May be an IO or a file name
    }
  end

  def method_missing(name, *args)
    @options[name.to_sym]
  end

  def subprocess_init(&block)
    @subprocess_init = block
  end

  def when_done(&block)
    @when_done = block
  end

  def start
    wait if !running? && waitable?
    raise "Already running" if @subprocess

    @subprocess = SubprocessGroupWithTimeout.new(self.timeout, log) do
      begin
        $stdin.reopen("/dev/null")
        if options[:vm_log]
          $stdout.reopen(options[:vm_log])
        else
          $stdout.reopen("/dev/null")
        end
        $stderr.reopen($stdout)

        @subprocess_init.call if @subprocess_init

        nocloexec = [$stdin, $stdout, $stderr]

        cmd = []
        cmd << self.binary
        cmd << "initrd=#{self.initrd}"
        cmd << "mem=#{self.mem}"
        cmd << "uml_dir=#{self.uml_dir}"

        for name, path in self.disks
          cmd << "#{name}=#{path}" if path != nil
        end

        for path, lock_type in file_locks
          f = File.open(path, File::RDONLY)
          f.flock(lock_type)
          nocloexec << f
        end

        for iface, tapdev in self.network
          if tapdev != nil
            if tapdev.is_a?(TapDevice)
              cmd << "#{iface}=tuntap,#{tapdev.name},,#{tapdev.ip_addr}"
            else
              cmd << "#{iface}=#{tapdev}"
            end
          end
        end

        cmd += self.extra_options

        if options[:vm_log]
          cmd << "con=null,fd:1"
        else
          cmd << "con=null"
        end

        cmd << self.command if self.command

        # Increase the nicelevel (lower the priority) of this process
        if self.nicelevel != 0
          begin
            Process.setpriority(Process::PRIO_PROCESS, 0, self.nicelevel)
          rescue
            log.warn("Failed to set nicelevel to #{0}: #{$!.message}")
          end
        end

        log.debug "PID #{Process.pid} executing: #{cmd}"
        MiscUtils.cloexec_all_except(nocloexec)
        Process.exec(Shellwords.join(cmd.map(&:to_s)))
      rescue
        log.error("UML execution failed: " + AppLog.fmt_exception($!))
      ensure
        exit(210)
      end
    end

    @subprocess.when_done(&@when_done) if @when_done

    @subprocess.start

    nil
  end

  def running?
    @subprocess && @subprocess.running?
  end

  def waitable?
    !!@subprocess
  end

  def kill
    @subprocess.kill if @subprocess
  end

  def wait
    if @subprocess
      SignalHandlers.with_trap(SignalHandlers.termination_signals, lambda { @subprocess.kill }) do
        @subprocess.wait
      end
      @subprocess = nil
    end
  end
end