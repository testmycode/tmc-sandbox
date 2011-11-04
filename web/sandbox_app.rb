# The web interface
# See site.defaults.yml for configuration.

require 'fileutils'
require 'yaml'
require 'multi_json'
require 'pathname'
require 'shellwords'

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
  
  class Runner
    include Paths
    
    def initialize(settings)
      @settings = settings
      nuke_work_dir!
    end
    
    def start(tar_file)
      raise 'busy' if busy?
      
      nuke_work_dir!
      
      @pid = Process.fork do
        $stdout.reopen("#{vm_log_path}", "w")
        $stderr.reopen($stdout)
        
        `dd if=/dev/zero of=#{output_tar_path} bs=#{@settings['max_output_size']} count=1`
        exit!(1) unless $?.success?
        
        cmd = Shellwords.join([
          "#{kernel_path}",
          "initrd=#{initrd_path}",
          "ubda=#{rootfs_path}",
          "ubdb=#{tar_file.path}",
          "ubdc=#{output_tar_path}",
          "mem=#{@settings['instance_ram']}"
        ])
        
        Process.exec(cmd)
      end
    end
    
    def update_status
      wait_for_process(true)
      #TODO: kill on time limit (and set a big-ish cpu time limit?)
    end
    
    def busy?
      @pid != nil
    end
    
    def has_output?
      output_tar_path.exist?
    end
    
    def output
      `tar --to-stdout -xf #{output_tar_path} output.txt`
    end
    
    def wait
      wait_for_process(false)
    end
    
    def kill
      if @pid
        Process.kill("KILL", @pid)
        wait_for_process(false)
      end
    end
    
  private
    
    def nuke_work_dir!
      FileUtils.rm_rf work_dir
      FileUtils.mkdir_p work_dir
    end
    
    def wait_for_process(nohang)
      if @pid
        pid, status = Process.waitpid2(@pid, nohang ? Process::WNOHANG : 0)
        if status
          @return_status = status
          @pid = nil
        end
      end
    end
  end
end

class SandboxApp
  include SandboxApp::Paths

  def initialize
    init_check
    @settings = load_settings
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

  def settings
    @settings
  end
  
  def kill_runner
    @runner.kill
  end
  
  def wait_for_runner_to_finish
    @runner.wait
  end

private
  def serve_request
    @runner.update_status
    if @req.post?
      if !@runner.busy?
        @runner.start(@req['file'][:tempfile])
        @respdata[:status] = 'ok'
      else
        @resp.status = 500
        @respdata[:status] = 'busy'
      end
    else
      if @runner.busy?
        @respdata[:status] = 'busy'
      else
        @respdata[:status] = 'idle'
        if @runner.has_output?
          @respdata[:output] = @runner.output
        end
      end
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

