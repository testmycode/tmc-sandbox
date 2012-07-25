
require File.dirname(File.realpath(__FILE__)) + '/test_helper.rb'
require 'signal_handlers'
require 'misc_utils'
require 'process_user'

class SignalHandlersTest < MiniTest::Unit::TestCase
  def setup
    ProcessUser.drop_root!
  end

  def test_with_trap_using_single_trap
    orig_traps = 0
    traps = 0

    Signal.trap("USR1") do
      orig_traps += 1
    end

    SignalHandlers.with_trap(["TERM", "SIGUSR1"], lambda { traps += 1 }) do
      Process.kill("TERM", Process.pid)
      Process.kill("USR1", Process.pid)
      handle_pending_signals
    end

    assert_equal(0, orig_traps)
    assert_equal(2, traps)

    Process.kill("USR1", Process.pid)
    handle_pending_signals

    assert_equal(1, orig_traps)
    assert_equal(2, traps)
  end

  def test_with_trap_nesting
    orig_traps = 0
    traps1 = 0
    traps2 = 0

    ["USR1", "USR2"].each do |sig|
      Signal.trap(sig) do
        orig_traps += 1
      end
    end

    SignalHandlers.with_trap(["TERM", "SIGUSR1"], lambda { traps1 += 1 }) do
      Process.kill("TERM", Process.pid)
      Process.kill("USR1", Process.pid)
      handle_pending_signals
      assert_equal(2, traps1)

      SignalHandlers.with_trap(["TERM", "SIGUSR2"], lambda { traps2 += 1 }) do
        Process.kill("TERM", Process.pid)
        Process.kill("USR1", Process.pid)
        Process.kill("USR2", Process.pid)
        handle_pending_signals
      end

      assert_equal(4, traps1)
      assert_equal(2, traps2)

      Process.kill("TERM", Process.pid)
      Process.kill("USR1", Process.pid)
      Process.kill("USR2", Process.pid)
      handle_pending_signals
    end

    assert_equal(1, orig_traps)
    assert_equal(6, traps1)
    assert_equal(2, traps2)

    Process.kill("USR2", Process.pid)
    handle_pending_signals

    assert_equal(2, orig_traps)
    assert_equal(6, traps1)
    assert_equal(2, traps2)
  end

  def test_handler_parameter
    handled = []
    SignalHandlers.with_trap(["TERM", "SIGUSR1"], lambda {|sig| handled << sig }) do
      Process.kill("TERM", Process.pid)
      handle_pending_signals
      Process.kill("USR1", Process.pid)
      handle_pending_signals
      Process.kill("TERM", Process.pid)
      handle_pending_signals
    end

    assert_equal(["TERM", "USR1", "TERM"], handled)
  end

  def test_setting_original_traps
    Signal.trap("USR1", "IGNORE")
    assert_equal("IGNORE", SignalHandlers.original_handler("USR1"))
    proc = Proc.new {}
    Signal.trap("USR1", &proc)
    assert_equal(proc, SignalHandlers.original_handler("USR1"))
  end

  def test_setting_original_traps_while_there_are_handlers
    sigs = []

    SignalHandlers.with_trap("USR1", lambda { sigs << :handler }) do
      Signal.trap("USR1") do
        sigs << :original
      end
      Process.kill("USR1", Process.pid)
      handle_pending_signals
    end

    assert_equal([:handler], sigs)

    Process.kill("USR1", Process.pid)
    handle_pending_signals

    assert_equal([:handler, :original], sigs)
  end

  def test_handler_priorities
    sigs = []
    SignalHandlers.with_trap("USR1", lambda { sigs << :last }, SignalHandlers::PRIORITY_LAST) do
      SignalHandlers.with_trap("USR1", lambda { sigs << :first }, SignalHandlers::PRIORITY_FIRST) do
        Process.kill("USR1", Process.pid)
        handle_pending_signals
      end
    end

    assert_equal([:first, :last], sigs)
  end

private
  def handle_pending_signals
    # Horrible unreliable kludge.
    # Firstly, we can't trust that kill()'ing the self process delivers the signal immediately
    sleep 0.02
    # Secondly, we need to reschedule the main ruby thread so it picks up the signal from the queue
    Thread.main.run
  end
end

