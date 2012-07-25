
require File.dirname(File.realpath(__FILE__)) + '/test_helper.rb'
require 'misc_utils'
require 'process_user'

class MiscUtilsTest < MiniTest::Unit::TestCase
  def setup
    ProcessUser.drop_root!
    super
  end

  def test_open_fds
    # We don't know exactly what MiniTest or our environment might open,
    # so we can't justassert_equals.
    pipe_in, pipe_out = IO.pipe
    begin
      fds = MiscUtils.open_fds
      expected = [1, 2, 3, pipe_in.fileno, pipe_out.fileno]
      for e in expected
        assert(fds.include?(e), "FD #{e} expected to be open")
      end
      
      assert(!fds.include?(123))
    ensure
      pipe_in.close
      pipe_out.close
    end
  end

  def test_cloexec_all
    pin, pout = IO.pipe
    pid = Process.fork do
      MiscUtils.cloexec_all
      Process.exec("sleep 10")
    end
    begin
      pin.close

      assert_raises(Errno::EPIPE) do
        pout.write('a'*100000)
      end
      pout.close
    ensure
      Process.kill("KILL", pid)
      Process.waitpid(pid)
    end
  end

  def test_wait_for_signal
    pin, pout = IO.pipe
    pid = Process.fork do
      pin.close
      Signal.trap("TERM") do
        pout.puts "Got TERM"
      end
      MiscUtils.wait_for_signal("TERM")
      pout.puts "Exiting"
      pout.close
    end
    pout.close

    sleep 0.2
    Process.kill("TERM", pid)
    data = pin.read
    Process.waitpid(pid)

    pin.close

    assert_equal "Exiting\n", data
  end
end

