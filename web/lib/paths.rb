require 'pathname'

module Paths
  extend self

  def root_dir
    Pathname(::WEBAPP_ROOT).parent
  end

  def web_dir
    root_dir + 'web'
  end

  def work_dir
    web_dir + 'work'
  end

  def log_dir
    web_dir + 'log'
  end

  def lock_dir
    web_dir + 'lock'
  end

  def uml_dir
    root_dir + 'uml'
  end

  def kernel_path
    uml_dir + 'output' + 'linux.uml'
  end

  def rootfs_path
    uml_dir + 'output' +'rootfs.squashfs'
  end

  def initrd_path
    uml_dir + 'output' + 'initrd.img'
  end

  def plugin_path
    web_dir + 'plugins'
  end

  def dnsmasq_path
    root_dir + 'misc' + 'dnsmasq'
  end

  def squidroot_dir
    root_dir + 'misc' + 'squidroot'
  end

  def squid_path
    squidroot_dir + 'sbin' + 'squid'
  end

  def squid_config_path
    squidroot_dir + 'etc' + 'squid.conf'
  end

  def squid_startup_log_path
    log_dir + 'squid-startup.log'
  end
end