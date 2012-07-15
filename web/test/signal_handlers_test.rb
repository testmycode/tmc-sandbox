
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
      execute_interrupts
    end

    assert_equal(0, orig_traps)
    assert_equal(2, traps)

    Process.kill("USR1", Process.pid)
    execute_interrupts

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
      execute_interrupts
      assert_equal(2, traps1)

      SignalHandlers.with_trap(["TERM", "SIGUSR2"], lambda { traps2 += 1 }) do
        Process.kill("TERM", Process.pid)
        Process.kill("USR1", Process.pid)
        Process.kill("USR2", Process.pid)
        execute_interrupts
      end

      assert_equal(4, traps1)
      assert_equal(2, traps2)

      Process.kill("TERM", Process.pid)
      Process.kill("USR1", Process.pid)
      Process.kill("USR2", Process.pid)
      execute_interrupts
    end

    assert_equal(1, orig_traps)
    assert_equal(6, traps1)
    assert_equal(2, traps2)

    Process.kill("USR2", Process.pid)
    execute_interrupts

    assert_equal(2, orig_traps)
    assert_equal(6, traps1)
    assert_equal(2, traps2)
  end

  def test_handler_parameter
    handled = []
    SignalHandlers.with_trap(["TERM", "SIGUSR1"], lambda {|sig| handled << sig }) do
      Process.kill("TERM", Process.pid)
      execute_interrupts
      Process.kill("USR1", Process.pid)
      execute_interrupts
      Process.kill("TERM", Process.pid)
      execute_interrupts
    end

    assert_equal(["TERM", "USR1", "TERM"], handled)
  end

private
  def execute_interrupts
    # Ruby's signal handlers queue signals to the main thread.
    # Whenever the main thread gets scheduled, it checks the queue and
    # executes any signal handlers.
    # Scheduling it explicitly makes it check the queue immediately.
    Thread.main.run
  end
end

