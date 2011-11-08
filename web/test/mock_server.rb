require 'net/http'
require 'webrick'

class MockServer
  def url
    "http://localhost:11988/notify"
  end

  def interact(&block)
    @req_data = nil
    
    pipe_block do |pipe_in, pipe_out|
      server_pid = fork_server_process(pipe_in, pipe_out)
      pipe_out.close
      
      begin
        reader = Thread.fork do
          @req_data = MultiJson.decode(pipe_in.read)
        end
      
        wait_for_server_to_be_ready
        block.call
      ensure
        reader.join if reader
        
        Process.kill("KILL", server_pid)
        Process.waitpid(server_pid)
      end
    end
    
    @req_data
  end
  
private
  def fork_server_process(pipe_in, pipe_out)
    Process.fork do
      $stdin.close
      $stdout.close
      $stderr.close
      pipe_in.close
      
      app = Rack::Builder.new do
        map '/ready' do
          ready = lambda do
            [200, {'Content-Type' => 'text/plain'}, ["ready"]]
          end
          run ready
        end
        
        map '/notify' do
          notify = lambda do |env|
            req = Rack::Request.new(env)
            pipe_out.write(MultiJson.encode({:content_type => env['CONTENT_TYPE'], :params => req.params}))
            pipe_out.close
            [200, {'Content-Type' => 'text/plain'}, ["OK"]]
          end
          run notify
        end
      end.to_app
      
      Rack::Handler::WEBrick.run(app, :Host => 'localhost', :Port => 11988, :Logger => WEBrick::Log.new('/dev/null'))
    end
  end
  
  def wait_for_server_to_be_ready
    while true
      begin
        Net::HTTP.get(URI('http://localhost:11988/ready'))
        break
      rescue Errno::ECONNREFUSED
        sleep 0.1
      end
    end
  end
  
  def pipe_block(&block)
    # IO.pipe with a block not supported on Ruby 1.8.7
    infd, outfd = IO.pipe
    begin
      block.call(infd, outfd)
    ensure
      infd.close unless infd.closed?
      outfd.close unless outfd.closed?
    end
  end
end
