require 'shell_utils'

module Ext2Utils
  def mke2fs(path)
    program = find_util('mke2fs')
    ShellUtils.sh!([program, '-F', path])
  end
  
  def fsck(path, options = {})
    options = {
      :force => false,
      :autorepair => true
    }.merge(options)
    program = find_util('e2fsck')
    cmd = []
    cmd << program
    cmd << '-f' if options[:force]
    cmd << '-y' if options[:autorepair]
    cmd << path
    output = `#{Shellwords.join(cmd)} 2>&1`
    if ![0, 1, 2].include?($?.exitstatus)
      raise "e2fsck on #{path} failed.\n#{output}"
    end
  end
  
  extend self
  
private
  def find_util(name)
    ShellUtils.find_program(name, ['/sbin', '/usr/sbin', '/usr/local/sbin'])
  end
end

