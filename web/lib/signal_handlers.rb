
# Allows for multiple handlers for a single signal
module SignalHandlers
  @handlers = {}
  @original_traps = {}
  @signal_name_by_num = Signal.list.invert

  def self.termination_signals
    ["TERM", "INT", "HUP", "USR1", "USR2"]
  end

  def self.with_trap(signals, handler_proc, &block)
    signals = normalize_signal_list(signals)

    signals.each {|sig| add_one_trap(sig, handler_proc) }
    begin
      block.call
    ensure
      signals.each {|sig| remove_one_trap(sig, handler_proc) }
    end
  end

  def self.add_trap(signals, handler_proc)
    for sig in normalize_signal_list(signals)
      add_one_trap(sig, handler_proc)
    end
  end

  def self.remove_trap(signals, handler_proc)
    for sig in normalize_signal_list(signals)
      remove_one_trap(sig, handler_proc)
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

  def self.add_one_trap(sig, handler_proc)
    if @handlers[sig] == nil || @handlers[sig].empty?
      trap_proc = trap_proc_for(sig)
      @handlers[sig] = [handler_proc]
      @original_traps[sig] = Signal.trap(sig, &trap_proc)
    else
      @handlers[sig] << handler_proc
    end
  end

  def self.remove_one_trap(sig, trap_proc)
    @handlers[sig].delete(trap_proc)

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

  def self.trap_proc_for(sig)
    Proc.new do
      for handler in @handlers[sig]
        if handler.arity == 0
          handler.call
        else
          handler.call(sig)
        end
      end
    end
  end
end