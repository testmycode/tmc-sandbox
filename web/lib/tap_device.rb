
require 'shell_utils'

class TapDevice
  def initialize(name, ip_addr, user)
    @name = name
    @ip_addr = ip_addr
    @user = user

    raise "Unexpected kind of IP address" unless @ip_addr =~ /^192.168.\d+.1/
  end

  attr_reader :name, :ip_addr, :user

  # Like 192.168.123.0/24
  def subnet
    @ip_addr.gsub(/\d+$/, '0/24')
  end

  def broadcast_addr
    @ip_addr.gsub(/\d+$/, '255')
  end

  def exist?
    ifaces = `ifconfig -a`.split("\n").map {|line| if line =~ /^(\S+)/ then $1 else nil end }.reject(&:nil?)
    ifaces.include?(@name)
  end

  def create
    ShellUtils.sh! ['ip', 'tuntap', 'add', 'dev', @name, 'mode', 'tap', 'user', @user]
  end

  def up
    ShellUtils.sh! ['ifconfig', @name, @ip_addr, 'netmask', '255.255.255.0', broadcast_addr, 'up']
  end

  def down
    ShellUtils.sh! ['ifconfig', @name, 'down']
  end

  def destroy
    ShellUtils.sh! ['ip', 'tuntap', 'del', 'dev', @name, 'mode', 'tap']
  end
end