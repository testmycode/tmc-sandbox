
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
    
    write_config <<EOS
class SandboxManagerConfig < SandboxManager::BaseConfig
  def tmc_user
    '#{tmc_user}'
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
    '#{tmc_user}'
  end
end
EOS
      invoke('create', '3077')
      ifaces_file = File.read('/etc/network/interfaces')
      assert(ifaces_file.include?("iface tap_tmc77 inet static"), "Network interface was not configured")
      assert(ifaces_file.include?("pre-up ip tuntap add dev tap_tmc77 mode tap user #{tmc_user}"),
             "Network interface was configured incorrectly (pre-up line)")
      assert(ifaces_file.include?("post-down ip tuntap del dev tap_tmc77 mode tap"),
             "Network interface was configured incorrectly (post-down line)")
      
      site_yml = YAML.load_file('3077/site.yml')
      assert_equal("eth0=tuntap,tap_tmc77,,192.168.77.1", site_yml['extra_uml_args'])
      
      invoke('start', '3077')
      assert(`ifconfig`.include?('tap_tmc77'), "Network interface was not brought up")
      
      invoke('stop', '3077')
      assert(!`ifconfig`.include?('tap_tmc77'), "Network interface was not brought down")
      
      invoke('destroy', '3077')
    else
      skip("Need to be root to run this test")
    end
  end
  
  
  def test_network_setup_with_maven_cache
    if Process.uid == 0
      write_config <<EOS
class SandboxManagerConfig < SandboxManager::BaseConfig
  include SandboxManager::NetworkConfig
  
  def tmc_user
    '#{tmc_user}'
  end
  
  def enable_maven_cache?
    true
  end
  
  def maven_tapdev
    'tap_mvntest'
  end
  
  def maven_ip
    '192.168.220.1'
  end
end
EOS
      invoke('create', '3077')
      ifaces_file = File.read('/etc/network/interfaces')
      assert(ifaces_file.include?("iface tap_mvntest inet static"),
             "Network interface was not configured")
      assert(ifaces_file.include?("pre-up ip tuntap add dev tap_mvntest mode tap user #{tmc_user}"),
             "Network interface was configured incorrectly (pre-up line)")
      assert(ifaces_file.include?("post-down ip tuntap del dev tap_mvntest mode tap"),
             "Network interface was configured incorrectly (post-down line)")
      
      site_yml = YAML.load_file('3077/site.yml')
      assert_equal(true, site_yml['plugins']['maven_cache']['enabled'])
      assert_equal('tap_mvntest', site_yml['plugins']['maven_cache']['tap_device'])
      assert_equal('192.168.220.1', site_yml['plugins']['maven_cache']['tap_ip'])
      
      invoke('start', '3077')
      assert(`ifconfig`.include?('tap_mvntest'), "Network interface was not brought up")
      assert(`ifconfig`.include?('192.168.220.1'), "Network interface was not brought up with the correct IP")
      
      invoke('stop', '3077')
      assert(`ifconfig`.include?('tap_mvntest'), "Maven network interface was brought down. It shouldn't be.")
      
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
  
  def tmc_user
    result = Etc.getlogin
    if result == 'root'
      if ENV['TMC_USER']
        result = ENV['TMC_USER']
      else
        begin
          Etc.getpwnam('tmc')
        rescue ArgumentError
          fail("Need tmc user. Run this test via sudo or create the 'tmc' user or set TMC_USER in your env.")
        else
          result = 'tmc'
        end
      end
    end
    result
  end
end

