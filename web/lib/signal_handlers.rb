
require 'misc_utils'

module Signal
  class <<self
    alias_method :_actual_trap, :trap
  end
  def self.trap(sig, command = nil, &block)
    command = block if command == nil
    SignalHandlers.set_original_handler(sig, command)
  end
end

module Kernel
  def trap(sig, command = nil, &block)
    Signal.trap(sig, command, &block)
  end
end

# Allows for multiple handlers for a single signal.
# The methods here may not be called from a signal handler.
module SignalHandlers
  PRIORITY_FIRST = 0
  PRIORITY_DEFAULT = 5
  PRIORITY_LAST = 10

  @handlers = {} # signal => hash of priority => array of handlers
  @original_traps = {} # signal => command or proc set by Signal.trap or Kernel#trap.

  # @original_traps[sig] is set only if @handlers[sig] is not empty

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
      original = set_actual_trap(sig) { caught = true }
      set_actual_trap(sig, original)
      Process.kill(sig, Process.pid) if caught # unlikely but possible
      original
    end
  end

  def self.set_original_handler(signals, handler)
    signals = normalize_signal_list(signals)
    for sig in signals
      @original_traps[sig] = handler
      set_trap(sig)
    end
  end

  def self.restore_original_handler(signals)
    signals = normalize_signal_list(signals)
    for sig in signals
      if @original_traps[sig]
        @handlers.delete(sig)
        set_actual_trap(sig, @original_traps[sig])
      end
    end
  end

  def self.inspect
    "<SignalHandlers @handlers=#{@handlers.inspect} " +
      "@original_traps=#{@original_traps.inspect}>"
  end


private
  def self.normalize_signal_list(signals)
    signals = [signals] if !signals.is_a?(Enumerable)
    signals.map {|sig| normalize_signal_name(sig) }
  end

  def self.normalize_signal_name(sig)
    s = sig.to_s
    if s =~ /^\d+$/
      s = @signal_name_by_num[sig.to_i]
    elsif sig =~ /^SIG[A-Z0-9]+$/
      s = sig[3..-1]
    end
    raise "Invalid signal: #{sig}" if !Signal.list[s]
    s
  end

  def self.add_one_trap(sig, handler_proc, priority)
    @handlers[sig] ||= {}
    @handlers[sig][priority] ||= []
    @handlers[sig][priority] << handler_proc
    set_trap(sig)
  end

  def self.remove_one_trap(sig, trap_proc)
    @handlers[sig].each_value {|a| a.delete(trap_proc) }
    @handlers[sig].reject! {|_, a| a.empty? }
    @handlers.reject! {|_, a| a.empty? }
    set_trap(sig)
  end

  # Called each time @handlers or @original_traps change.
  def self.set_trap(sig)
    handlers = if @handlers[sig] then @handlers[sig].clone else {} end
    if handlers.empty?
      if @original_traps[sig]
        set_actual_trap(sig, @original_traps[sig])
        @original_traps.delete(sig)
      end
    else
      trap_proc = trap_proc_for(sig, handlers)
      old_trap = set_actual_trap(sig, &trap_proc)
      @original_traps[sig] = old_trap unless @original_traps.has_key?(sig)
    end
  end

  def self.trap_proc_for(sig, handlers_by_priority)
    Proc.new do
      for priority in handlers_by_priority.keys.sort
        for handler in handlers_by_priority[priority]
          if handler.arity == 0
            handler.call
          else
            handler.call(sig)
          end
        end
      end
    end
  end

  def self.set_actual_trap(sig, command = nil, &block)
    block = command if command.is_a?(Proc)
    if block_given?
      Signal._actual_trap(sig, &block)
    else
      Signal._actual_trap(sig, command)
    end
  end
end
