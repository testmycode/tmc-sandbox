require 'shell_utils'

module Ext2Utils
  def mke2fs(path)
    program = find_util('mke2fs')
    ShellUtils.sh!([program, '-F', path])
  end

  extend self
  
private
  def find_util(name)
    ShellUtils.find_program(name, ['/sbin', '/usr/sbin', '/usr/local/sbin'])
  end
end

