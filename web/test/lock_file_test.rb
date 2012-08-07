
require File.dirname(File.realpath(__FILE__)) + '/test_helper.rb'
require 'lock_file'
require 'process_user'
require 'tempfile'

class LockFileTest < MiniTest::Unit::TestCase
  def setup
    ProcessUser.drop_root!
    super
  end

  def test_private_lock
    LockFile.open_private do |lock|
      do_test_lock(lock)
    end
  end

  def test_blockless_api
    file = Tempfile.new('LockFileTest_test_blockless_api')
    begin
      lock = LockFile.new(file)
      do_test_lock(lock)
    ensure
      file.close(true)
    end
  end

private
  def do_test_lock(lock)
    LockFile.open_private do |lock|
      pid1 = Process.fork do
        lock.lock
      end

      rd, rw = IO.pipe
      pid2 = Process.fork do
        rd.close
        sleep 0.5
        result = lock.lock(File::LOCK_NB)
        rw.write(if result == false then 'OK' else 'FAIL' end)
        rw.close
      end
      rw.close

      assert_equal 'OK', rd.read

      Process.waitpid(pid1)
      Process.waitpid(pid2)
      assert_equal "012X456789", buf.read
    end
  end
end

