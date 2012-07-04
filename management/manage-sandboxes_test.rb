
require 'minitest/autorun'
require 'fileutils'
require 'yaml'
require 'shellwords'
require 'etc'

# Note: this test may leave instances running if it fails.
# Note: by default this test suppresses output. See invoke() below.
class ManageSandboxesTest < MiniTest::Unit::TestCase
  def setup
    Dir.chdir(management_dir)
    FileUtils.rm_rf(work_dir)
    FileUtils.mkdir_p(work_dir)
    @script_path = File.expand_path("#{management_dir}/manage-sandboxes")
    Dir.chdir(work_dir)
    
    current_user = Etc.getlogin
    
    write_config <<EOS
class SandboxManagerConfig < SandboxManager::BaseConfig
  def tmc_user
    '#{current_user}'
  end
end
EOS
  end
  
  def teardown
    Dir.chdir(management_dir)
    FileUtils.rm_rf(work_dir)
  end
  
  def test_create
    invoke('create', '3101')
    invoke('create', '3102')
    assert File.exist?('3101')
    assert File.exist?('3102')
    site_yml = YAML.load_file('3101/site.yml')
    assert_equal(File.realpath("#{management_dir}/../output"), site_yml['sandbox_files_root'])
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
  
  def test_network_setup
    if Process.uid == 0
      write_config <<EOS
class SandboxManagerConfig < SandboxManager::BaseConfig
  include SandboxManager::NetworkConfig
  
  def tmc_user
    'root'
  end
end
EOS
      invoke('create', '3077')
      ifaces_file = File.read('/etc/network/interfaces')
      assert(ifaces_file.include?("iface tmc_tap77"), "Network interface was not configured")
      
      invoke('start', '3077')
      assert(`ifconfig`.include?('tmc_tap77'), "Network interface was not brought up")
      
      invoke('stop', '3077')
      assert(!`ifconfig`.include?('tmc_tap77'), "Network interface was not brought down")
      
      invoke('destroy', '3077')
    else
      skip("Need to be root to run this test")
    end
  end
  
  
private
  def invoke(*args)
    args = ['--config', test_config_file] + args
    invoke_no_output(*args)
    #invoke_with_output(*args) # comment above and uncomment this for debugging
  end

  def invoke_with_output(*args)
    system(@script_path, *args)
  end
  
  def invoke_no_output(*args)
    system("#{@script_path} " + Shellwords.join(args) + " > output.txt 2>&1")
    raise "#{$?} with output:\n#{File.read('output.txt')}" unless $?.success?
  end
  
  def write_config(config)
    File.open(test_config_file, 'wb') do |f|
      f.write(config)
    end
  end
  
  def management_dir
    @@management_dir ||= File.dirname(File.realpath(__FILE__))
  end

  def work_dir
    '/tmp/manage-sandboxes_test'
  end
  
  def test_config_file
    "#{work_dir}/test_config.rb"
  end
end

