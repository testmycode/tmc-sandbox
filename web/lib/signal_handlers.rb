
# Allows for multiple handlers for a single signal.
# The methods here may not be called from a signal handler.
module SignalHandlers
  PRIORITY_FIRST = 0
  PRIORITY_DEFAULT = 5
  PRIORITY_LAST = 10

  @handlers = {} # signal => hash of priority => array of handlers
  @original_traps = {}
  @signal_name_by_num = Signal.list.invert

  def self.termination_signals
    ["TERM", "INT", "HUP", "USR1", "USR2"]
  end

  def self.with_trap(signals, handler_proc, priority = PRIORITY_DEFAULT, &block)
    signals = normalize_signal_list(signals)

    signals.each {|sig| add_one_trap(sig, handler_proc, priority) }
    begin
      block.call
    ensure
      signals.each {|sig| remove_one_trap(sig, handler_proc) }
    end
  end

  def self.add_trap(signals, handler_proc, priority = PRIORITY_DEFAULT)
    for sig in normalize_signal_list(signals)
      add_one_trap(sig, handler_proc, priority)
    end
  end

  def self.remove_trap(signals, handler_proc)
    for sig in normalize_signal_list(signals)
      remove_one_trap(sig, handler_proc)
    end
  end

  def self.original_handler(sig)
    sig = normalize_signal_name(sig)
    if @original_traps[sig]
      @original_traps[sig]
    else
      caught = false
      handler = Signal.trap(sig) { caught = true }
      Signal.trap(sig, handler)
      Process.kill(sig, Process.pid) if caught # very unlikely
      handler
    end
  end

  def self.reapply
    for sig in @handlers.keys
      if !@handlers[sig].empty?
        setup_trap(sig)
      end
    end
  end


private
  def self.normalize_signal_list(signals)
    signals = [signals] if !signals.is_a?(Enumerable)
    signals.map {|sig| normalize_signal_name(sig) }
  end

  def self.normalize_signal_name(sig)
    s = sig
    if s =~ /^\d+$/
      s = @signal_name_by_num[sig.to_i]
    elsif sig =~ /^SIG[A-Z0-9]+$/
      s = sig[3..-1]
    end
    raise "Invalid signal: #{sig}" if !Signal.list[s]
    s
  end

  def self.add_one_trap(sig, handler_proc, priority)
    if @handlers[sig] == nil || @handlers[sig].empty?
      @handlers[sig] = {priority => [handler_proc]}
      setup_trap(sig)
    else
      @handlers[sig][priority] ||= []
      @handlers[sig][priority] << handler_proc
    end
  end

  def self.remove_one_trap(sig, trap_proc)
    @handlers[sig].each_value {|a| a.delete(trap_proc) }
    @handlers[sig].reject! {|_, a| a.empty? }

    if @handlers[sig].empty?
      @handlers.delete(sig)
      if @original_traps[sig].is_a?(Proc)
        block = @original_traps[sig]
        Signal.trap(sig, &block)
      else
        Signal.trap(sig, @original_traps[sig])
        @original_traps.delete(sig)
      end
    end
  end

  def self.setup_trap(sig)
    trap_proc = trap_proc_for(sig)
    @original_traps[sig] = Signal.trap(sig, &trap_proc)
  end

  def self.trap_proc_for(sig)
    Proc.new do
      for priority in @handlers[sig].keys.sort
        for handler in @handlers[sig][priority]
          if handler.arity == 0
            handler.call
          else
            handler.call(sig)
          end
        end
      end
    end
  end
end