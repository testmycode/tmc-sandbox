# The web interface
# See site.defaults.yml for configuration.
require './init.rb'

require 'fileutils'
require 'yaml'
require 'multi_json'
require 'pathname'
require 'shellwords'
require 'net/http'
require 'uri'
require 'lockfile'
require 'logger'
require 'active_support/inflector'
require 'hash_deep_merge'

require 'subprocess_with_timeout'
require 'misc_utils'

class SandboxApp
  def self.debug_log # Dunno if Logger is safe to use in subprocesses, but don't care since it's a debug tool.
    @debug_log ||= Logger.new('/dev/null')
  end
  
  def self.debug_log=(new_logger)
    @debug_log = new_logger
  end
  
  
  module Paths
    extend Paths
    
    def web_dir
      Pathname.new(__FILE__).expand_path.parent
    end
    
    def work_dir
      web_dir + 'work'
    end
    
    def root_dir
      @@root_dir
    end
    
    def self.root_dir=(new_root_dir)
      @@root_dir = Pathname.new(new_root_dir).expand_path(web_dir)
    end
    
    def kernel_path
      root_dir + 'linux.uml'
    end
    
    def rootfs_path
      root_dir + 'rootfs.squashfs'
    end
    
    def initrd_path
      root_dir + 'initrd.img'
    end
    
    def output_tar_path
      work_dir + 'output.tar'
    end
    
    def vm_log_path
      work_dir + 'vm.log'
    end
    
    def plugin_path
      web_dir + 'plugins'
    end
  end
  
  class Plugin
    include Paths
    
    def initialize(settings)
      @settings = settings
      @plugin_settings = settings['plugins'][plugin_name]
    end
    
    def plugin_name
      ActiveSupport::Inflector.underscore(self.class.to_s)
    end
    
    attr_reader :settings
    
    # Run just before starting the UML subprocess.
    # options:
    #   :tar_file => path to submission .tar file for this request.
    def before_exec(options)
    end
  end
  
  class PluginManager
    include Paths
    
    def initialize(settings)
      @settings = settings
      
      @plugins = []
      if @settings['plugins'].is_a?(Hash)
        plugin_names = @settings['plugins'].keys.sort # arbitrary but predictable load order
        for plugin_name in plugin_names
          if @settings['plugins'][plugin_name]['enabled']
            SandboxApp.debug_log.debug "Loading plugin #{plugin_name}"
            require "#{plugin_path}/#{plugin_name}.rb"
            class_name = ActiveSupport::Inflector.camelize(plugin_name)
            @plugins << Object.const_get(class_name).new(@settings)
          end
        end
      end
    end
    
    def run_hook(hook, *args)
      for plugin in @plugins
        begin
          plugin.send(hook, *args)
        rescue
          SandboxApp.debug_log.debug "Plugin hook #{plugin}.#{hook} raised exception: #{$!}"
        end
      end
    end
  end
  
  
  class Runner
    include Paths
    
    def initialize(settings, plugin_manager)
      @settings = settings
      @plugin_manager = plugin_manager
      nuke_work_dir!
      
      @subprocess = SubprocessWithTimeout.new(@settings['timeout'].to_i, SandboxApp.debug_log) do
        $stdin.close
        $stdout.reopen("#{vm_log_path}", "w")
        $stderr.reopen($stdout)
        nocloexec = [$stdout, $stderr]
        
        `dd if=/dev/zero of=#{output_tar_path} bs=#{@settings['max_output_size']} count=1`
        exit!(1) unless $?.success?
        
        args = [
          "#{kernel_path}",
          "initrd=#{initrd_path}",
          "ubdarc=#{rootfs_path}",
          "ubdbr=#{@tar_file.path}",
          "ubdc=#{output_tar_path}",
          "mem=#{@settings['instance_ram']}",
          "con=null"
        ]
        if @settings['extra_image_ubdd']
          ubdd = @settings['extra_image_ubdd']
          SandboxApp.debug_log.debug "Using #{ubdd} as ubdd"
          args << "ubddrc=#{ubdd}"
          ubdd_file = File.open(ubdd, File::RDONLY)
          ubdd_file.flock(File::LOCK_SH) # Released when UML exits
          nocloexec << ubdd_file
        end
        if @settings['extra_uml_args'].is_a?(Enumerable)
          args += @settings['extra_uml_args']
        elsif @settings['extra_uml_args'].is_a?(String)
          args << @settings['extra_uml_args']
        end
        
        cmd = Shellwords.join(args)
        
        SandboxApp.debug_log.debug "PID #{Process.pid} executing: #{cmd}"
        MiscUtils.cloexec_all_except(nocloexec)
        Process.exec(cmd)
      end
      
      @subprocess.when_done do |process_status|
        exit_code = nil
        status =
          if process_status == :timeout
            :timeout
          elsif process_status.success?
            begin
              exit_code = extract_file_from_tar(output_tar_path, 'exit_code.txt').to_i
            rescue
              SandboxApp.debug_log.warn "Failed to untar exit_code.txt"
              exit_code = nil
            end
            if exit_code == 0
              :finished
            else
              :failed
            end
          else
            SandboxApp.debug_log.warn "Sandbox failed with status #{process_status.inspect}"
            :failed
          end
        
        SandboxApp.debug_log.debug "Status: #{status}. Exit code: #{exit_code.inspect}."

        output = {
          'test_output' => try_extract_file_from_tar(output_tar_path, 'test_output.txt'),
          'stdout' => try_extract_file_from_tar(output_tar_path, 'stdout.txt'),
          'stderr' => try_extract_file_from_tar(output_tar_path, 'stderr.txt')
        }
        
        @notifier.send_notification(status, exit_code, output) if @notifier
      end
    end
    
    def start(tar_file, notifier)
      raise 'busy' if busy?
      
      nuke_work_dir!
      @tar_file = tar_file
      @notifier = notifier
      
      @plugin_manager.run_hook(:before_exec, :tar_file => @tar_file)
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
      SandboxApp.debug_log.debug "Clearing work dir"
      FileUtils.rm_rf work_dir
      FileUtils.mkdir_p work_dir
    end

    def extract_file_from_tar(tar_path, file_name)
      result = `tar --to-stdout -xf #{output_tar_path} #{file_name} 2>/dev/null`
      raise "Failed to extract #{file_name} from #{tar_path}" if !$?.success?
      result
    end

    def try_extract_file_from_tar(tar_path, file_name)
      begin
        extract_file_from_tar(tar_path, file_name)
      rescue
        ""
      end
    end
  end
  
  
  class Notifier
    def initialize(url, token)
      @url = url
      @token = token
    end
    
    def send_notification(status, exit_code, output)
      postdata = output.merge({
        'token' => @token,
        'status' => status.to_s
      })
      postdata['exit_code'] = exit_code if exit_code != nil

      SandboxApp.debug_log.debug "Notifying #{@url}"
      resp = Net::HTTP.post_form(URI(@url), postdata)
    end
  end
end


class SandboxApp
  include SandboxApp::Paths

  class BadRequest < StandardError; end

  def initialize(settings_overrides = {})
    @settings = SandboxApp.load_settings.merge(settings_overrides)
    SandboxApp.debug_log = Logger.new(@settings['debug_log_file']) unless @settings['debug_log_file'].to_s.empty?
    SandboxApp::Paths.root_dir = @settings['sandbox_files_root']
    init_check
    @plugin_manager = PluginManager.new(@settings)
    @runner = Runner.new(@settings, @plugin_manager)
  end
  
  attr_reader :settings

  def call(env)
    raw_response = nil
    Lockfile('lock') do
      @req = Rack::Request.new(env)
      @resp = Rack::Response.new
      @resp['Content-Type'] = 'application/json; charset=utf-8'
      @respdata = {}
      
      serve_request
      
      raw_response = @resp.finish do
        @resp.write(MultiJson.encode(@respdata))
      end
    end
    raw_response
  end
  
  def kill_runner
    @runner.kill
  end
  
  def wait_for_runner_to_finish
    @runner.wait
  end
  
  def self.load_settings
    s = YAML.load_file(Paths.web_dir + 'site.defaults.yml')
    if File.exist?(Paths.web_dir + 'site.yml')
      s = s.deep_merge(YAML.load_file(Paths.web_dir + 'site.yml'))
    end
    s
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
end

