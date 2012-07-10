# The Rack app.

require 'fileutils'
require 'multi_json'
require 'pathname'
require 'net/http'
require 'uri'
require 'lockfile'
require 'logger'
require 'active_support/inflector'

require 'paths'
require 'settings'
require 'misc_utils'
require 'sandbox_instance'

class SandboxApp
  def self.debug_log # Dunno if Logger is safe to use in subprocesses, but don't care since it's a debug tool.
    @debug_log ||= Logger.new('/dev/null')
  end
  
  def self.debug_log=(new_logger)
    @debug_log = new_logger
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
    def initialize(settings)
      @settings = settings
      
      @plugins = []
      if @settings['plugins'].is_a?(Hash)
        plugin_names = @settings['plugins'].keys.sort # arbitrary but predictable load order
        for plugin_name in plugin_names
          if @settings['plugins'][plugin_name]['enabled']
            SandboxApp.debug_log.debug "Loading plugin #{plugin_name}"
            require "#{Paths.plugin_path}/#{plugin_name}.rb"
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

  class BadRequest < StandardError; end


  def initialize(settings_overrides = {})
    @settings = Settings.get.deep_merge(settings_overrides)
    SandboxApp.debug_log = Logger.new(@settings['debug_log_file']) unless @settings['debug_log_file'].to_s.empty?
    init_check
    @plugin_manager = PluginManager.new(@settings)

    @instances = []
    @settings['max_instances'].times do |i|
      @instances << SandboxInstance.new(i, @settings, @plugin_manager)
    end
  end
  
  attr_reader :settings

  def call(env)
    raw_response = nil
    FileUtils.mkdir_p(Paths.lock_dir)
    Lockfile((Paths.lock_dir + 'sandbox_app.lock').to_s) do
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

  def kill_instances
    @instances.each(&:kill)
  end

  def wait_for_instances_to_finish
    @instances.each(&:wait)
  end

private
  def serve_request
    begin
      if @req.post? && @req.path == '/task.json'
        serve_post_task
      elsif @req.get? && @req.path == '/status.json'
        serve_status
      else
        @respdata[:status] = 'not_found'
        @resp.status = 404
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
    inst = @instances.find(&:idle?)
    if inst
      raise BadRequest.new('missing file parameter') if !@req['file'] || !@req['file'][:tempfile]
      notifier = if @req['notify'] then Notifier.new(@req['notify'], @req['token']) else nil end
      inst.start(@req['file'][:tempfile]) do |status, exit_code, output|
        notifier.send_notification(status, exit_code, output)
      end
      @respdata[:status] = 'ok'
    else
      @resp.status = 500
      @respdata[:status] = 'busy'
    end
  end

  def serve_status
    busy = @instances.count(&:busy?)
    total = @instances.size
    @respdata[:busy_instances] = busy
    @respdata[:total_instances] = total
  end
  
  def init_check
    raise 'kernel not compiled' unless File.exist? Paths.kernel_path
    raise 'rootfs not prepared' unless File.exist? Paths.rootfs_path
    raise 'initrd not made' unless File.exist? Paths.initrd_path
  end
end

