require "rack/test"
require 'tempfile'
require 'pathname'
require 'fileutils'
require 'multi_json'
require 'socket' # or mimic 0.4.3 fails with SocketError not found
require 'mimic'
require './sandbox_app'

class WebappTest < Test::Unit::TestCase
  include Rack::Test::Methods
  
  MIMIC_BASEURL = "http://localhost:#{Mimic::MIMIC_DEFAULT_PORT}"
  
  def app
    @app = SandboxApp.new
  end
  
  def setup
    @tempfiles = []
  end
  
  def teardown
    @tempfiles.each {|f| f.unlink }
    @app.wait_for_runner_to_finish
    Mimic.cleanup!
  end
  
  def test_initially_idle_no_output
    get '/'
    
    assert last_response.ok?
    assert_equal 'idle', json_response['status']
    assert_equal nil, json_response['output']
  end
  
  def test_basic_run_wait_get
    post '/', :file => tar_fixture('successful')
    
    assert last_response.ok?
    assert_equal 'ok', json_response['status']
    
    @app.wait_for_runner_to_finish
    
    get '/'
    
    assert last_response.ok?
    assert_equal 'idle', json_response['status']
    assert_equal 'this is the output.txt of fixtures/successful', json_response['output'].strip
  end
  
  def test_post_responds_busy_when_previous_task_running
    post '/', :file => tar_fixture('sleeper')
    assert last_response.ok?
    
    post '/', :file => tar_fixture('sleeper')
    
    assert !last_response.ok?
    assert_equal 'busy', json_response['status']
    
    @app.kill_runner # finish faster
  end
  
  def test_get_responds_busy_when_previous_task_running
    post '/', :file => tar_fixture('sleeper')
    assert last_response.ok?
    
    get '/'
    
    assert last_response.ok?
    assert_equal 'busy', json_response['status']
    
    @app.kill_runner # finish faster
  end
 
  def test_responds_with_error_on_bad_request
    post '/' # no file parameter
    
    assert !last_response.ok?
    assert_equal 'bad_request', json_response['status']
  end
  
  def test_can_post_back_notification_when_done
    post_data = nil
    resp = mimic_ok
    Mimic.mimic do
      post("/my/path") do
        post_data = params
        resp
      end
    end
    
    post '/', :file => tar_fixture('successful'), :notify => MIMIC_BASEURL + '/my/path', :token => '123123'
    
    @app.wait_for_runner_to_finish
    
    assert_not_nil post_data
    assert_equal '123123', post_data['token']
    assert_equal 'finished', post_data['status']
    assert_equal 'this is the output.txt of fixtures/successful', post_data['output'].strip
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
  
  def mimic_ok
    [200, {'Content-Type' => 'text/plain'}, "OK"]
  end
end

