
require 'paths'
require 'tempfile'

class LockFile
  def initialize(file)
    @file = file
  end

  attr_reader :file

  def lock(lock_type = File::LOCK_EX)
    @file.flock(lock_type)
  end

  def unlock
    @file.flock(File::LOCK_UN)
  end

  def with_lock(lock_type = File::LOCK_EX, &block)
    @file.flock(lock_type)
    begin
      return false if (lock_type & File::LOCK_NB != 0) && ret == false

      if block.arity == 1
        block.call(self)
      else
        block.call
      end
    ensure
      @file.flock(File::LOCK_UN)
    end
  end

  def self.open(path, lock_type = File::LOCK_EX, &block)
    File.open(path, File::RDONLY | File::CREAT) do |f|
      LockFile.new(f).with_lock(lock_type, &block)
    end
  end

  def self.open_private(lock_type = File::LOCK_EX, &block)
    Tempfile.new('LockFile_private', Paths.lock_dir.to_s) do |f|
      LockFile.new(f).with_lock(lock_type, &block)
    end
  end
end