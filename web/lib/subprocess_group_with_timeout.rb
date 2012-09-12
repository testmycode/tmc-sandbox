require 'signal_handlers'

# A subprocess group with a timeout that will kill the whole group.
# Aimed at running UML.
class SubprocessGroupWithTimeout
  def initialize(timeout, log = nil, &block)
    @timeout = timeout
    @log = log || Logger.new('/dev/null')
    @block = block
    @after_block = lambda {|ignore| }

    @signal_handler = lambda do |sig|
      Process.kill(sig, @intermediate_pid) if @intermediate_pid != nil
    end
    
    @intermediate_pid = nil
  end
  
  # Runs block in an intermediate subprocess immediately after
  # the main subprocess finishes or times out.
  # Gives status of main process or :timeout as parameter
  def when_done(&block)
    @after_block = block
  end

  def start
    raise 'previous run not waited nor killed' if @intermediate_pid

    SignalHandlers.add_trap(SignalHandlers.termination_signals, @signal_handler)

    pipe_in, pipe_out = IO.pipe
    
    @intermediate_pid = Process.fork do
      SignalHandlers.restore_original_handler(SignalHandlers.termination_signals)

      pipe_in.close
      # We start a new session and process group for two reasons.
      # First, we want to be able to kill the whole process group at once.
      # Second, UML likes to mess up the current session's console.
      #
      # Also, when UML panics, it goes berserk and kills its entire process group.
      # `wait` will then find this process dead by SIGTERM.
      #
      # Moreover we shall kill this entire process group if the UML timeouts too,
      # since otherwise UML child processes may be left, holding locks to files
      # and preventing future UMLs from starting.
      Process.setsid
      
      worker_pid = fork_in_new_pgrp do
        pipe_out.close
        @block.call
      end
      timeout_pid = Process.fork do
        pipe_out.close
        MiscUtils.cloexec_all
        Process.exec("sleep #{@timeout}")
      end
      @log.debug "PIDS: Intermediate(#{Process.pid}), Worker(#{worker_pid}), Timeout(#{timeout_pid})"

      Signal.trap("SIGTERM") do
        Process.kill("KILL", timeout_pid)
        Process.kill("KILL", -worker_pid)
        exit!(1)
      end
      
      pipe_out.write("ready for SIGTERM")
      pipe_out.close
      
      finished_pid, status = Process.waitpid2(-1)
      Signal.trap("SIGTERM", "SIG_DFL")
      
      if finished_pid == worker_pid
        @log.debug "Worker finished with status #{status.inspect}"
        Process.kill("KILL", timeout_pid)
        Process.waitpid(timeout_pid)
      else
        @log.debug "Worker timed out."
        Process.kill("KILL", -worker_pid) # kill whole process group
        status = :timeout
      end

      @after_block.call(status)
    end

    pipe_out.close
    if pipe_in.read != "ready for SIGTERM"
      Process.kill("KILL", @intermediate_pid)
      Process.waitpid(@intermediate_pid)
      SignalHandlers.remove_trap(SignalHandlers.termination_signals, @signal_handler)
      raise "intermediate PID did not start properly"
    end
    pipe_in.close
  end
  
  def running?
    wait(false)
    @intermediate_pid != nil
  end
  
  def wait(block = true)
    if @intermediate_pid
      @log.debug "Waiting for runner (#{@intermediate_pid}) to stop (blocking = #{block})"
      
      pid, status = Process.waitpid2(@intermediate_pid, if block then 0 else Process::WNOHANG end)
      if pid != nil
        @log.debug "Runner (#{@intermediate_pid}) stopped. Status: #{status.inspect}."
        @intermediate_pid = nil
        SignalHandlers.remove_trap(SignalHandlers.termination_signals, @signal_handler)
      end
      status
    else
      nil
    end
  end
  
  def kill
    if @intermediate_pid
      @log.debug "Killing runner (#{@intermediate_pid}) process group"
      Process.kill("TERM", @intermediate_pid)
      wait
    end
  end
  
private
  def fork_in_new_pgrp(&block)
    pipe_in, pipe_out = IO.pipe
    
    pid = Process.fork do
      pipe_in.close
      Process.setpgrp
      pipe_out.write("started")
      pipe_out.close
      
      block.call
    end
    pipe_out.close
    
    if pipe_in.read != "started"
      Process.kill("KILL", pid)
      Process.waitpid(pid)
      raise "subprocess did not signal started"
    end
    pipe_in.close
    
    pid
  end
end

