
require 'minitest/autorun'
require 'fileutils'
require 'yaml'
require 'shellwords'

# Note: this test may leave instances running if it fails.
class ManageSandboxesTest < MiniTest::Unit::TestCase
  def setup
    FileUtils.rm_rf(work_dir)
    FileUtils.mkdir_p(work_dir)
    FileUtils.mkdir_p(work_dir + '/tmc-sandbox')
    FileUtils.ln_s(File.expand_path('../output'), work_dir + '/tmc-sandbox/output')
    FileUtils.ln_s(File.expand_path('../web'), work_dir + '/tmc-sandbox/web')
    @script_path = File.expand_path('./manage-sandboxes')
    @test_suite_dir = File.expand_path(File.dirname(__FILE__))
    Dir.chdir(work_dir)
  end
  
  def teardown
    Dir.chdir(@test_suite_dir)
    FileUtils.rm_rf(work_dir)
  end
  
  def test_create
    invoke('create', '3101')
    invoke('create', '3102')
    assert File.exist?('3101')
    assert File.exist?('3102')
    site_yml = YAML.load_file('3101/site.yml')
    assert_equal(File.expand_path('./tmc-sandbox/output'), site_yml['sandbox_files_root'])
  end
  
  def test_destroy
    invoke('create', '3101')
    invoke('create', '3102')
    invoke('destroy', '3101')
    assert !File.exist?('3101')
    assert File.exist?('3102')
  end
  
  def test_start_stop
    invoke('create', '3101')
    invoke('start', '3101')
    assert File.exist?('3101/webrick.pid')
    pid = File.read('3101/webrick.pid').to_i
    Process.kill(0, pid) # should not throw if the process exists
    
    invoke('stop', '3101')
    assert !File.exist?('3101/webrick.pid')
    assert_raises(Errno::ESRCH) { Process.kill(0, pid) } # (yeah, theoretically fragile test if someone races to the same pid)
  end
  
  def test_stop_on_destroy
    invoke('create', '3101')
    invoke('start', '3101')
    pid = File.read('3101/webrick.pid').to_i
    
    invoke('destroy', '3101')
    assert !File.exist?('3101/webrick.pid')
    assert_raises(Errno::ESRCH) { Process.kill(0, pid) }
  end
  
  def test_rebuild
    invoke('create', '3101')
    File.open('3101/foo.txt', 'wb') {|f| f.write('junk') }
    invoke('start', '3101')
    pid = File.read('3101/webrick.pid').to_i
    
    invoke('rebuild', '3101')
    
    new_pid = File.read('3101/webrick.pid').to_i
    assert !File.exist?('3101/foo.txt')
    refute_equal(pid, new_pid)
    
    invoke('stop', '3101')
  end
  
  def test_onboot
    invoke('create', '3101')
    invoke('create', '3102')
    
    invoke('onboot')
    assert File.exist?('3101/webrick.pid')
    assert File.exist?('3102/webrick.pid')
    
    invoke('stop', '3101')
    invoke('stop', '3102')
  end
  
  
private
  def invoke(*args)
    invoke_no_output(*args)
    #invoke_with_output(*args) # for debugging
  end

  def invoke_with_output(*args)
    system(@script_path, *args)
  end
  
  def invoke_no_output(*args)
    system("#{@script_path} " + Shellwords.join(args) + " > output.txt 2>&1")
    raise "#{$?} with output:\n#{File.read('output.txt')}" unless $?.success?
  end

  def work_dir
    '/tmp/manage-sandboxes_test'
  end
end

