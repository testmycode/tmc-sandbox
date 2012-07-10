
begin
  require 'misc_utils_ext'
rescue LoadError
  system("rake ext")
  require 'misc_utils_ext'
end

module MiscUtils
  # Methods defined in C:
  #   self.open_fds()
  #     returns an array of open FDs.
  #
  #   self.cloexec(fd)
  #     Enables O_CLOEXEC on the given FD.
  #     Done in C because Ruby won't let us open IO objects on
  #     its internal FDs.
  #
  #   self.wait_for_signal(signal1, signal2, ...)
  #     Waits for and ignores any of the given signals.
  #     I'm not exactly sure why but a waited signal may still be delivered
  #     for some reason and so ought to be trapped just in case.
  
  # Sets O_CLOEXEC on all except the given FDs
  def self.cloexec_all_except(fds)
    fds = to_fd_numbers(fds)
    for fd in open_fds - fds
      cloexec(fd)
    end
  end
  
  # Returns the current backtrace as an array. A debugging aid.
  def self.current_backtrace
    bt = []
    begin
      raise ''
    rescue
      bt = $!.backtrace
      bt.shift
    end
    bt
  end
  
private
  def self.to_fd_numbers(fds)
    fds.map {|fd| if fd.respond_to?(:fileno) then fd.fileno else fd end }
  end
end

