require "rack/test"
require 'tempfile'
require 'pathname'
require 'fileutils'
require 'multi_json'
require './sandbox_app'

class WebappTest < Test::Unit::TestCase
  include Rack::Test::Methods
  
  def app
    @app = SandboxApp.new
  end
  
  def setup
    @tempfiles = []
  end
  
  def teardown
    @tempfiles.each {|f| f.unlink }
    @app.wait_for_runner_to_finish
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
    
    @app.kill_runner # so the test finishes faster
  end
  
  #TODO: test get '/' when busy
  
  #TODO: posting back notification when done
  
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
end

