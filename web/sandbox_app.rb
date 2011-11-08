# The web interface
# See site.defaults.yml for configuration.

require 'fileutils'
require 'yaml'
require 'multi_json'
require 'pathname'
require 'shellwords'
require 'net/http'
require 'uri'

class SandboxApp
  module Paths
    def web_dir
      Pathname.new(__FILE__).expand_path.parent
    end
    
    def work_dir
      web_dir + 'work'
    end
    
    def root_dir
      web_dir.parent
    end
    
    def tools_dir
      root_dir + 'output'
    end
    
    def kernel_path
      tools_dir + 'linux.uml'
    end
    
    def rootfs_path
      tools_dir + 'rootfs.squashfs'
    end
    
    def initrd_path
      tools_dir + 'initrd.img'
    end
    
    def output_tar_path
      work_dir + 'output.tar'
    end
    
    def vm_log_path
      work_dir + 'vm.log'
    end
  end
  
  
  class SubprocessWithTimeout
    def initialize(timeout, &block)
      @timeout = timeout
      @block = block
      
      @intermediate_pid = nil
    end
    
    # Runs block in an intermediate subprocess immediately after the main subprocess finishes or times out
    def when_done(&block)
      @after_block = block
    end
    
    def start
      raise 'previous run now waited nor killed' if @intermediate_pid
      
      @intermediate_pid = Process.fork do
        worker_pid = Process.fork(&@block)
        timeout_pid = Process.fork do
          [$stdin, $stdout, $stderr].each &:close
          sleep @timeout
        end
        
        finished_pid, status = Process.waitpid2(-1)
        if finished_pid == worker_pid
          Process.kill("KILL", timeout_pid)
          Process.waitpid(timeout_pid)
        else
          Process.kill("KILL", worker_pid)
          status = :timeout
        end
        
        @after_block.call(status)
      end
    end
    
    def running?
      wait(false)
      @intermediate_pid != nil
    end
    
    def wait(block = true)
      if @intermediate_pid
        if Process.waitpid(@intermediate_pid, if block then 0 else Process::WNOHANG end) != nil
          @intermediate_pid = nil
        end
      end
    end
    
    def kill
      if @intermediate_pid
        Process.kill("KILL", @intermediate_pid)
        wait
      end
    end
  end
  
  
  class Runner
    include Paths
    
    def initialize(settings)
      @settings = settings
      nuke_work_dir!
      
      @subprocess = SubprocessWithTimeout.new(@settings['timeout'].to_i) do
        $stdin.close
        $stdout.reopen("#{vm_log_path}", "w")
        $stderr.reopen($stdout)
        
        Process.setsid # Otherwise UML will mess up our console
        
        `dd if=/dev/zero of=#{output_tar_path} bs=#{@settings['max_output_size']} count=1`
        exit!(1) unless $?.success?
        
        cmd = Shellwords.join([
          "#{kernel_path}",
          "initrd=#{initrd_path}",
          "ubda=#{rootfs_path}",
          "ubdb=#{@tar_file.path}",
          "ubdc=#{output_tar_path}",
          "mem=#{@settings['instance_ram']}",
          "con=null"
        ])
        
        Process.exec(cmd)
      end
      
      @subprocess.when_done do |process_status|
        status =
          if process_status == :timeout
            :timeout
          elsif process_status.success?
            :finished
          else
            :failed
          end
        
        output = `tar --to-stdout -xf #{output_tar_path} output.txt` if status == :finished
        @notifier.send_notification(status, output) if @notifier
      end
    end
    
    def start(tar_file, notifier)
      raise 'busy' if busy?
      
      nuke_work_dir!
      @tar_file = tar_file
      @notifier = notifier
      
      @subprocess.start
    end
    
    def busy?
      @subprocess.running?
    end
    
    def wait
      @subprocess.wait
    end
    
    def kill
      @subprocess.kill
    end
    
  private
    
    def nuke_work_dir!
      FileUtils.rm_rf work_dir
      FileUtils.mkdir_p work_dir
    end
  end
  
  
  class Notifier
    def initialize(url, token)
      @url = url
      @token = token
    end
    
    def send_notification(status, output)
      postdata = {
        'token' => @token,
        'status' => status.to_s,
        'output' => output
      }

      resp = Net::HTTP.post_form(URI(@url), postdata)
    end
  end
end


class SandboxApp
  include SandboxApp::Paths

  class BadRequest < StandardError; end

  def initialize(settings_overrides = {})
    init_check
    @settings = load_settings.merge(settings_overrides)
    @runner = Runner.new(@settings)
  end

  def call(env)
    @req = Rack::Request.new(env)
    @resp = Rack::Response.new
    @resp['Content-Type'] = 'application/json; charset=utf-8'
    @respdata = {}
    
    serve_request
    
    @resp.finish do
      @resp.write(MultiJson.encode(@respdata))
    end
  end
  
  def kill_runner
    @runner.kill
  end
  
  def wait_for_runner_to_finish
    @runner.wait
  end

private
  def serve_request
    begin
      if @req.post?
        serve_post_task
      else
        @resp.status = 404
        @respdata[:status] = 'not_found'
      end
    rescue BadRequest
      @respdata[:status] = 'bad_request'
      @resp.status = 500
    rescue
      @respdata[:status] = 'error'
      @resp.status = 500
    end
  end
  
  def serve_post_task
    if !@runner.busy?
      raise BadRequest.new('missing file parameter') if !@req['file'] || !@req['file'][:tempfile]
      notifier = if @req['notify'] then Notifier.new(@req['notify'], @req['token']) else nil end
      @runner.start(@req['file'][:tempfile], notifier)
      @respdata[:status] = 'ok'
    else
      @resp.status = 500
      @respdata[:status] = 'busy'
    end
  end
  
  def init_check
    raise 'kernel not compiled' unless File.exist? kernel_path
    raise 'rootfs not prepared' unless File.exist? rootfs_path
    raise 'initrd not made' unless File.exist? initrd_path
  end
  
  def load_settings
    settings = YAML.load_file(web_dir + 'site.defaults.yml')
    if File.exist?('site.yml')
      settings.merge(YAML.load_file(web_dir + 'site.yml'))
    end
    settings
  end
end

