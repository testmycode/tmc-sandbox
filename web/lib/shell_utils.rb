
module ShellUtils
  def sh!(*cmd)
    cmd = Shellwords.join(*cmd)
    output = `#{cmd} 2>&1`
    raise "Failed: #{cmd}. Exit code: #{$?.exitstatus}. Output:\n#{output}" if !$?.success?
  end

  def find_program(program, dirs)
    for dir in dirs
      candidate = "#{dir}/#{program}"
      return candidate if File.exist?(candidate)
    end
    program
  end

  extend self
end
