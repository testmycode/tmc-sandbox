
require 'settings'

module ProcessUser
  extend self

  def can_become_root?
    Process::Sys.getuid == 0
  end

  def is_root?
    Process::Sys::geteuid == 0
  end

  def become_root!
    Process::Sys.seteuid(0)
  end

  def drop_root!
    Process::Sys.seteuid(Settings.tmc_user_id) if is_root?
  end

  def drop_root_permanently!
    Process::Sys.setreuid(Settings.tmc_user_id, Settings.tmc_user_id) if is_root?
  end

  def as_root(&block)
    if !is_root?
      become_root!
      begin
        block.call
      ensure
        drop_root!
      end
    else
      block.call
    end
  end

  def as_tmc_user(&block)
    if is_root?
      drop_root!
      begin
        block.call
      ensure
        become_root!
      end
    else
      block.call
    end
  end
end
