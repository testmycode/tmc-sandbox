require 'subprocess_group_with_timeout'
require 'paths'
require 'settings'
require 'tap_device'

class UmlInstance
  def self.debug?
    Settings.get['uml_debug']
  end

  def debug?
    self.class.debug?
  end


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
      :log => AppLog.get
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
    raise "Already running" if @subprocess

    @subprocess = SubprocessGroupWithTimeout.new(self.timeout, log) do
      begin
        $stdin.reopen("/dev/null")
        if debug?
          $stdout.reopen(Paths.log_dir + "vm.debug.#{Process.pid}.log")
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

        if debug?
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

    pin, pout = IO.pipe
    @subprocess.when_done do |status|
      begin
        @when_done.call(status) if @when_done
      rescue
        status = :when_done_fail
      ensure
        pin.close
        begin
          if status == :timeout || status == :when_done_fail
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
    end

    @subprocess.start

    nil
  end

  def running?
    !!@subprocess
  end

  def kill
    @subprocess.kill if @subprocess
  end

  def wait
    if @subprocess
      success = false
      SignalHandlers.with_trap(SignalHandlers.termination_signals, lambda { @subprocess.kill }) do
        begin
          @subprocess.start
          pout.close
          success = (pin.read == '1')
          pin.close
        rescue
          success = false
        end
        @subprocess.wait
      end

      @@debug_ports.unreserve_port(@debug_port) if @debug_port
      @subprocess = nil

      success
    else
      nil
    end
  end
end