
# Proxies method calls to a wrapped object until 'close' is called.
# After that, raises an exception if more method calls are attempted
class CloseableWrapper < BasicObject
  DEFAULT_WHITELIST = [:to_s]

  def initialize(wrapped, whitelist = DEFAULT_WHITELIST)
    @wrapped = wrapped
    @closed = false
    @whitelist = whitelist
  end

  def method_missing(name, *args, &block)
    name = name.to_sym
    raise 'Method call on a closed object' if @closed && !@whitelist.include?(name)
    @wrapped.__send__(name, *args, &block)
  end
  
  def close
    begin
      method_missing(:close)
    ensure
      @closed = true
    end
  end
end
