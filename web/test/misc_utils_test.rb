
require './init.rb'
require 'minitest/autorun'

require 'misc_utils'

class MiscUtilsTest < MiniTest::Unit::TestCase
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
end

