
class LockFile
  def self.open(path, lock_type = File::LOCK_EX, &block)
    raise "May not use LOCK_NB with LockFile.open" if (lock_type & File::LOCK_NB) != 0
    File.open(path, File::RDONLY | File::CREAT) do |f|
      begin
        f.flock(lock_type)
        if block.arity == 1
          block.call(f)
        else
          block.call
        end
      ensure
        f.flock(File::LOCK_UN)
      end
    end
  end
end