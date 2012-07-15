# The Rack app.

require 'fileutils'
require 'multi_json'
require 'pathname'
require 'net/http'
require 'uri'
require 'lockfile'
require 'logger'
require 'active_support/inflector'

require 'app_log'
require 'paths'
require 'settings'
require 'misc_utils'
require 'sandbox_instance'

class SandboxApp
  class Plugin
    def initialize(settings)
      @settings = settings
      @plugin_settings = settings['plugins'][plugin_name]
    end
    
    def plugin_name
      ActiveSupport::Inflector.underscore(self.class.to_s)
    end
    
    attr_reader :settings

    #
    # Run just before starting the UML subprocess.
    # options:
    #   :instance => SandboxInstance object
    #   :tar_file => path to submission .tar file for this request.
    #
    def before_exec(options)
    end

    #
    # Should return a hash like 'ubdd[rc]' => '/path/to/image' of
    # images to give to the VM. Read-only images will get a shared flock.
    # options:
    #   :instance => SandboxInstance object
    #
    def extra_images(options)
      {}
    end

    # Whether this plugin is interested in serving the given Rack::Request
    def can_serve_request?(req)
      false
    end

    def serve_request(req, resp, respdata)
      raise "Not implemeted"
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
            AppLog.debug "Loading plugin: #{plugin_name}"
            require "#{Paths.plugin_path}/#{plugin_name}.rb"
            class_name = ActiveSupport::Inflector.camelize(plugin_name)
            @plugins << Object.const_get(class_name).new(@settings)
          end
        end
      end
    end

    def plugin(plugin_name)
      class_name = ActiveSupport::Inflector.camelize(plugin_name)
      if Object.const_defined?(class_name)
        cls = Object.const_get(class_name)
        @plugins.find {|plugin| plugin.is_a?(cls) }
      else
        nil
      end
    end
    
    def run_hook(hook, *args)
      rets = []
      for plugin in @plugins
        begin
          rets << plugin.send(hook, *args)
        rescue
          AppLog.debug "Plugin hook #{plugin}.#{hook} raised exception: #{$!}"
        end
      end
      rets
    end

    def serve_request(req, resp, respdata)
      plugin = @plugins.find {|pl| pl.can_serve_request?(req) }
      if plugin
        plugin.serve_request(req, resp, respdata)
        true
      else
        false
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

      AppLog.debug "Notifying #{@url}"
      Net::HTTP.post_form(URI(@url), postdata)
    end
  end

  class BadRequest < StandardError; end


  def initialize(settings_overrides = {})
    @settings = Settings.get.deep_merge(settings_overrides)

    AppLog.set(Logger.new(@settings['app_log_file'])) if @settings['app_log_file']
    AppLog.info("Starting up")

    init_check

    @plugin_manager = PluginManager.new(@settings)

    @instances = []
    @settings['max_instances'].times do |i|
      @instances << SandboxInstance.new(i, @settings, @plugin_manager)
    end
  end
  
  attr_reader :settings, :plugin_manager

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
      elsif @plugin_manager.serve_request(@req, @resp, @respdata)
        # ok
      else
        @respdata[:status] = 'not_found'
        @resp.status = 404
      end
    rescue BadRequest
      @respdata[:status] = 'bad_request'
      @resp.status = 500
    rescue
      AppLog.warn("Error processing request:\n#{AppLog.fmt_exception($!)}")
      @respdata[:status] = 'error'
      @resp.status = 500
    end
  end
  
  def serve_post_task
    inst = @instances.find(&:idle?)
    if inst
      raise BadRequest.new('missing file parameter') if !@req['file'] || !@req['file'][:tempfile]
      notifier = if @req['notify'] then Notifier.new(@req['notify'], @req['token']) else nil end
      inst.start(@req['file'][:tempfile].path) do |status, exit_code, output|
        notifier.send_notification(status, exit_code, output) if notifier
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
    @respdata[:loadavg] = File.read("/proc/loadavg").split(' ')[0..2] if File.exist?("/proc/loadavg")
  end
  
  def init_check
    raise 'kernel not compiled' unless File.exist? Paths.kernel_path
    raise 'rootfs not prepared' unless File.exist? Paths.rootfs_path
    raise 'initrd not made' unless File.exist? Paths.initrd_path
  end
end
