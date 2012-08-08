require File.dirname(File.realpath(__FILE__)) + '/test_helper.rb'
require "rack/test"
require 'tempfile'
require 'pathname'
require 'fileutils'
require 'multi_json'
require 'hash_deep_merge'

require 'sandbox_app'
require 'ext2_utils'
require 'mock_server'
require 'process_user'
require 'shell_utils'
require 'test_network_setup'

class SandboxAppTest < MiniTest::Unit::TestCase
  include Rack::Test::Methods
  include TestNetworkSetup
  
  def app
    if !@app
      @app = make_new_app
    end
    @app
  end

  def make_new_app(options = {})
    options = {
      'timeout' => 30,
      'max_instances' => 1,
      'plugins' => nil,
      'network' => nil,
      'app_log_file' => nil
    }.deep_merge(options)
    SandboxApp.new(options)
  end
  
  def setup
    ShellUtils.sh!(['chown', Settings.tmc_user, Paths.log_dir + 'test.log'])
    ProcessUser.drop_root!
    AppLog.set(Logger.new(Paths.log_dir + 'test.log'))
    @tempfiles = []
  end
  
  def teardown
    @tempfiles.each {|f| f.unlink }
    if @app
      @app.wait_for_instances_to_finish
    end
    AppLog.debug "----- TEST FINISHED -----"
  end
  
  def test_runs_task_and_posts_back_notification_when_done
    post_with_notify '/tasks.json', :file => tar_fixture('successful'), :token => '123123'
    
    assert_equal 'application/x-www-form-urlencoded', @notify_content_type

    assert_equal '123123', @notify_params['token']
    assert_equal 'finished', @notify_params['status']
    assert_equal '0', @notify_params['exit_code']
    assert_equal 'this is the test_output.txt of fixtures/successful', @notify_params['test_output'].strip
  end

  def test_can_respond_to_multiple_requests
    post_with_notify '/tasks.json', :file => tar_fixture('successful'), :token => '123123'
    
    post_with_notify '/tasks.json', :file => tar_fixture('successful'), :token => '456456'
    
    assert_equal 'application/x-www-form-urlencoded', @notify_content_type
    
    assert_equal '456456', @notify_params['token']
    assert_equal 'finished', @notify_params['status']
    assert_equal '0', @notify_params['exit_code']
    assert_equal 'this is the test_output.txt of fixtures/successful', @notify_params['test_output'].strip
  end
  
  def test_responds_busy_when_all_instances_are_busy
    @app = make_new_app('max_instances' => 2)
    post '/tasks.json', :file => tar_fixture('sleeper')
    assert last_response.ok?
    post '/tasks.json', :file => tar_fixture('sleeper')
    assert last_response.ok?
    
    post '/tasks.json', :file => tar_fixture('sleeper')
    
    assert !last_response.ok?
    assert_equal 'busy', json_response['status']
    
    app.kill_instances # finish faster
  end

  def test_get_status
    @app = make_new_app('max_instances' => 3)
    post '/tasks.json', :file => tar_fixture('sleeper')
    assert last_response.ok?
    post '/tasks.json', :file => tar_fixture('sleeper')
    assert last_response.ok?

    get '/status.json'
    assert last_response.ok?
    assert_equal 2, json_response['busy_instances']
    assert_equal 3, json_response['total_instances']

    app.kill_instances # finish faster
  end
 
  def test_responds_with_error_on_bad_request
    post '/tasks.json', {} # no file parameter
    
    assert !last_response.ok?
    assert_equal 'bad_request', json_response['status']
  end
  
  def test_task_may_time_out
    @app = make_new_app('timeout' => '1')
    
    post_with_notify '/tasks.json', :file => tar_fixture('sleeper')
    
    assert_equal 'timeout', @notify_params['status']
    assert_nil @notify_params['exit_code']
  end
  
  def test_failed_runs_may_have_output
    post_with_notify '/tasks.json', :file => tar_fixture('unsuccessful_with_output'), :token => '123123'
    
    assert_equal 'application/x-www-form-urlencoded', @notify_content_type
    
    assert_equal '123123', @notify_params['token']
    assert_equal 'failed', @notify_params['status']
    assert_equal '42', @notify_params['exit_code']
    assert_equal 'this is the test_output.txt of fixtures/unsuccessful_with_output', @notify_params['test_output'].strip
  end

  def test_network
    if !ProcessUser.can_become_root?
      warn "sandbox_app network test must be run as root. Skipping."
      skip
    end

    @app = make_new_app('network' => {
      'enabled' => true,
      'dnsmasq' => true,
      'squid' => true
    })

    with_network(tapdev_for_sandbox) do
      ProcessUser.drop_root!

      post_with_notify '/tasks.json', :file => tar_fixture('network_test'), :token => '123123'

      assert_equal 'application/x-www-form-urlencoded', @notify_content_type

      assert_equal 'finished', @notify_params['status']
      assert_equal '0', @notify_params['exit_code']
      assert_equal 'yay, downloaded it', @notify_params['test_output'].strip
    end
  end

  def test_network_and_maven_cache
    if !ProcessUser.can_become_root?
      warn "sandbox_app network and maven cache test must be run as root. Skipping."
      skip
    end

    @tmpdir = Dir.mktmpdir("maven_cache_test") do |tmpdir|
      @app = make_new_app(maven_cache_enable_options(tmpdir))

      with_network([tapdev_for_sandbox, tapdev_for_maven_cache]) do
        ProcessUser.drop_root!

        post_with_notify '/tasks.json', :file => tar_fixture('maven_project'), :token => '123'

        assert_equal 'finished', @notify_params['status']
        assert_equal '0', @notify_params['exit_code']
        assert @notify_params['test_output'].include?('"status":"PASSED"')

        mvn_cache = @app.plugin_manager.plugin('maven_cache')
        mvn_cache.wait_for_daemon

        post_with_notify '/tasks.json', :file => tar_fixture('show_mvn_cache'), :token => '456'
        assert_equal 'finished', @notify_params['status']
        assert_equal '0', @notify_params['exit_code']
        assert @notify_params['test_output'].include?("/ubdd/maven/repository/org/apache/commons/commons-io/1.3.2")
      end
    end
  end

  def test_maven_cache_image_locking
    if !ProcessUser.can_become_root?
      warn "sandbox_app maven cache locking test must be run as root. Skipping."
      skip
    end

    @tmpdir = Dir.mktmpdir("maven_cache_test") do |tmpdir|
      @app = make_new_app(maven_cache_enable_options(tmpdir))

      with_network([tapdev_for_sandbox, tapdev_for_maven_cache]) do
        ProcessUser.drop_root!

        mvn_cache = @app.plugin_manager.plugin('maven_cache')
        mvn_cache.start_caching_deps(tar_fixture_file('maven_project'))

        MiscUtils.poll_until(:time_limit => 10) { File.exist?("#{tmpdir}/current.img") }
        assert mvn_cache.daemon_running?
        MiscUtils.poll_until(:time_limit => 10, :timeout_error => "Didn't see current.img locked") do
          got_lock = false
          File.open("#{tmpdir}/current.img", File::RDONLY) do |f|
            got_lock = f.flock(File::LOCK_EX | File::LOCK_NB)
            f.flock(File::LOCK_UN) if got_lock
          end
          got_lock
        end

        mvn_cache.kill_daemon_if_running
        mvn_cache.wait_for_daemon
      end
    end
  end

  def test_maven_cache_populate_request
    if !ProcessUser.can_become_root?
      warn "sandbox_app maven cache populate request test must be run as root. Skipping."
      skip
    end

    @tmpdir = Dir.mktmpdir("maven_cache_test") do |tmpdir|
      @app = make_new_app(maven_cache_enable_options(tmpdir))

      with_network([tapdev_for_sandbox, tapdev_for_maven_cache]) do
        ProcessUser.drop_root!

        mvn_cache = @app.plugin_manager.plugin('maven_cache')

        post '/maven_cache/populate.json', :file => tar_fixture('maven_project')

        MiscUtils.poll_until(:time_limit => 10, :timeout_error => "Maven cache daemon did not start") do
          mvn_cache.daemon_running?
        end
        # That it runs is good enough for us. These tests take so long as it is :(

        mvn_cache.kill_daemon_if_running
        mvn_cache.wait_for_daemon
      end
    end
  end

private
  def fixture_path
    Pathname.new(__FILE__).expand_path.parent + 'fixtures'
  end

  def tar_fixture(name)
    file = tar_fixture_file(name)
    Rack::Test::UploadedFile.new(file, "application/x-tar", true)
  end

  def tar_fixture_file(name)
    file = Tempfile.new(['tmc-sandbox-fixture', '.tar'])
    file.close
    @tempfiles << file
    `tar -C #{fixture_path + name} -cf #{file.path} .`
    raise 'failed to tar' unless $?.success?
    file.path
  end
  
  def json_response
    assert last_response['Content-Type'] == 'application/json; charset=utf-8'
    MultiJson.decode(last_response.body)
  end
  
  def post_with_notify(sandbox_path, sandbox_params)
    srv = MockServer.new
    req_data = srv.interact do
      post sandbox_path, sandbox_params.merge(:notify => srv.url)
      app.wait_for_instances_to_finish
    end
    raise 'No data received from MockServer. Did the program send any?' if req_data == nil
    @notify_content_type = req_data['content_type']
    @notify_params = req_data['params']
  end

  def tapdev_for_sandbox
    TapDevice.new("tap_tmc0", "192.168.#{@app.settings['network']['private_ip_range_start']}.1", Settings.tmc_user)
  end

  def tapdev_for_maven_cache
    mvn_cache = @app.settings['plugins']['maven_cache']
    TapDevice.new(mvn_cache['tap_device'], "#{mvn_cache['tap_ip']}", Settings.tmc_user)
  end

  def network_enable_options
    {
      'network' => {
        'enabled' => true,
        'dnsmasq' => true,
        'squid' => true
      }
    }
  end

  def maven_cache_enable_options(work_dir)
    opts = {
      'network' => {
        'enabled' => true,
        'dnsmasq' => true,
        'squid' => true
      },
      'plugins' => {
        'maven_cache' => Settings.get['plugins']['maven_cache']
      },
      'timeout' => 300 # maven downloads usually take a while :(
    }
    cache_opts = opts['plugins']['maven_cache']
    cache_opts['enabled'] = true
    cache_opts['img_size'] = "48M"
    cache_opts['alternate_work_dir'] = work_dir
    opts
  end
end

