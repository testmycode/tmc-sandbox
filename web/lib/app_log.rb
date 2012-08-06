
require 'logger'

# Global log for the rack app
class AppLog
  def self.get
    @log ||= Logger.new($stdout)
  end

  def self.set(logger)
    @log = logger
  end

  def self.method_missing(name, *args, &block)
    self.get.send(name, *args, &block)
  end

  def self.fmt_exception(ex)
    parts = [ex.message] + ex.backtrace
    parts.join("\n        from ")
  end
end
