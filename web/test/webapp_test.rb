require 'minitest/autorun'
require "rack/test"
require 'tempfile'
require 'pathname'
require 'fileutils'
require 'multi_json'

require './sandbox_app'
require 'ext2_utils'
require './test/mock_server'

class WebappTest < MiniTest::Unit::TestCase
  include Rack::Test::Methods
  
  def app
    if !@app
      @app = make_new_app
    end
    @app
  end
  
  def make_new_app(options = {})
    options = {
      'timeout' => '30'
    }.deep_merge(options)
    options['plugins'] = nil
    SandboxApp.new(options)
  end
  
  def setup
    @tempfiles = []
  end
  
  def teardown
    @tempfiles.each {|f| f.unlink }
    if @app
      @app.wait_for_runner_to_finish
    end
    SandboxApp.debug_log.debug "----- TEST FINISHED -----"
  end
  
  def test_runs_task_and_posts_back_notification_when_done
    post_with_notify '/', :file => tar_fixture('successful'), :token => '123123'
    
    assert_equal 'application/x-www-form-urlencoded', @notify_content_type
    
    assert_equal '123123', @notify_params['token']
    assert_equal 'finished', @notify_params['status']
    assert_equal '0', @notify_params['exit_code']
    assert_equal 'this is the test_output.txt of fixtures/successful', @notify_params['test_output'].strip
  end
  
  def test_can_respond_to_multiple_requests
    post_with_notify '/', :file => tar_fixture('successful'), :token => '123123'
    
    post_with_notify '/', :file => tar_fixture('successful'), :token => '456456'
    
    assert_equal 'application/x-www-form-urlencoded', @notify_content_type
    
    assert_equal '456456', @notify_params['token']
    assert_equal 'finished', @notify_params['status']
    assert_equal '0', @notify_params['exit_code']
    assert_equal 'this is the test_output.txt of fixtures/successful', @notify_params['test_output'].strip
  end
  
  def test_post_responds_busy_when_previous_task_running
    post '/', :file => tar_fixture('sleeper')
    assert last_response.ok?
    
    post '/', :file => tar_fixture('sleeper')
    
    assert !last_response.ok?
    assert_equal 'busy', json_response['status']
    
    app.kill_runner # finish faster
  end
 
  def test_responds_with_error_on_bad_request
    post '/', {} # no file parameter
    
    assert !last_response.ok?
    assert_equal 'bad_request', json_response['status']
  end
  
  def test_task_may_time_out
    @app = make_new_app('timeout' => '1')
    
    post_with_notify '/', :file => tar_fixture('sleeper')
    
    assert_equal 'timeout', @notify_params['status']
    assert_nil @notify_params['exit_code']
  end
  
  def test_failed_runs_may_have_output
    post_with_notify '/', :file => tar_fixture('unsuccessful_with_output'), :token => '123123'
    
    assert_equal 'application/x-www-form-urlencoded', @notify_content_type
    
    assert_equal '123123', @notify_params['token']
    assert_equal 'failed', @notify_params['status']
    assert_equal '42', @notify_params['exit_code']
    assert_equal 'this is the test_output.txt of fixtures/unsuccessful_with_output', @notify_params['test_output'].strip
  end
  
  def test_ubdd_locking
    Tempfile.open('ubdd.img') do |file|
      ShellUtils.sh!(['fallocate', '-l', "8M", file.path])
      Ext2Utils.mke2fs(file.path)
      @app = make_new_app('extra_image_ubdd' => file.path)
      post '/', :file => tar_fixture('sleeper')
      assert last_response.ok?
      
      sleep 2
      begin
        assert_equal false, file.flock(File::LOCK_EX | File::LOCK_NB)
        assert_equal 0, file.flock(File::LOCK_SH | File::LOCK_NB)
        assert_equal 0, file.flock(File::LOCK_UN)
      ensure
        @app.kill_runner
      end
      
      # It takes a little while for locks to be released.
      # Possibly because UML's children aren't wait()'ed instantly by init.
      start = Time.now
      ok = false
      while Time.now <= start + 2
        if file.flock(File::LOCK_EX | File::LOCK_NB) == 0
          file.flock(File::LOCK_UN)
          ok = true
          break
        else
          sleep 0.01
        end
      end
      fail 'Failed to lock file after UML died.' if !ok
    end
  end
  
  def test_ubdd_use
    Tempfile.open('ubdd.img') do |file|
      ShellUtils.sh!(['fallocate', '-l', "8M", file.path])
      Ext2Utils.mke2fs(file.path)
      @app = make_new_app('extra_image_ubdd' => file.path)
      
      post_with_notify '/', :file => tar_fixture('use_ubdd')
      
      assert_equal 'finished', @notify_params['status']
      assert_equal '0', @notify_params['exit_code']
      assert @notify_params['test_output'].include?('hello.txt')
      assert @notify_params['test_output'].include?('lost+found') # made by mke2fs
    end
  end

private
  def fixture_path
    Pathname.new(__FILE__).expand_path.parent + 'fixtures'
  end

  def tar_fixture(name)
    file = Tempfile.new(['tmc-sandbox-fixture', '.tar'])
    file.close
    @tempfiles << file
    `tar -C #{fixture_path + name} -cf #{file.path} .`
    raise 'failed to tar' unless $?.success?
    Rack::Test::UploadedFile.new(file.path, "application/x-tar", true)
  end
  
  def json_response
    assert last_response['Content-Type'] == 'application/json; charset=utf-8'
    MultiJson.decode(last_response.body)
  end
  
  def post_with_notify(sandbox_path, sandbox_params)
    srv = MockServer.new
    req_data = srv.interact do
      post sandbox_path, sandbox_params.merge(:notify => srv.url)
      app.wait_for_runner_to_finish
    end
    raise 'No data received from MockServer. Did the program send any?' if req_data == nil
    @notify_content_type = req_data['content_type']
    @notify_params = req_data['params']
  end
end

