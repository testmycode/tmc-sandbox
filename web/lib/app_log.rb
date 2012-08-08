
require 'logger'

# Global log for the rack app
class AppLog
  def self.get
    @log ||= Logger.new($stdout)
  end

  def self.set(logger)
    @log = logger
  end

  def self.debug(msg)
    get.debug(msg)
  end

  def self.info(msg)
    get.info(msg)
  end

  def self.warn(msg)
    get.warn(msg)
  end

  def self.error(msg)
    get.error(msg)
  end

  def self.fatal(msg)
    get.fatal(msg)
  end

  def self.unknown(msg)
    get.unknown(msg)
  end


  def self.method_missing(name, *args, &block)
    self.get.send(name, *args, &block)
  end

  def self.fmt_exception(ex)
    parts = [ex.message] + ex.backtrace
    parts.join("\n        from ")
  end
end
