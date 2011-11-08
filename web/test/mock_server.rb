require 'net/http'
require 'webrick'

class MockServer
  def url
    "http://localhost:11988/notify"
  end

  def interact(&block)
    IO.pipe do |pipe_in, pipe_out|
      server_pid = Process.fork do
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
      
      pipe_out.close
      
      req_data = nil
      reader = Thread.fork do
        req_data = MultiJson.decode(pipe_in.read)
      end
      
      while true
        begin
          res = Net::HTTP.get(URI('http://localhost:11988/ready'))
          break
        rescue Errno::ECONNREFUSED
          sleep 0.1
        end
      end
      
      begin
        block.call
      ensure
        reader.join
        
        Process.kill("KILL", server_pid)
        Process.waitpid(server_pid)
        
        return req_data
      end
    end
  end
end
