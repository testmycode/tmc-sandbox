require 'paths'
require 'sqlite3'

class DiskCache
  private_class_method :new
  def self.get(name)
    FileUtils.mkdir_p(disk_cache_dir)
    self.send(:new, disk_cache_dir + (name + ".cache.sqlite3"))
  end

  def initialize(path)
    @path = path.to_s
    with_db do |db|
      db.execute("CREATE TABLE IF NOT EXISTS cache (key TEXT PRIMARY KEY NOT NULL, value TEXT NOT NULL, updated_at INT NOT NULL)")
      db.execute("CREATE INDEX IF NOT EXISTS cache_updated_at_index ON cache (updated_at)")
    end
  end

  def put(key, value)
    with_db do |db|
      db.execute("INSERT OR REPLACE INTO cache (key, value, updated_at) VALUES (?, ?, ?)", key, value, Time.now.to_i)
    end
  end

  def get(key, default = nil)
    with_db do |db|
      result = get_db(db, key)
      if result
        result
      else
        default
      end
    end
  end

  def get_or_put(key, &block)
    with_db do |db|
      result = get_db(db, key)
      if !result
        value = block.call
        begin
          put(key, value)
          value
        rescue
          value
        end
      else
        result
      end
    end
  end

  def delete(key)
    with_db do |db|
      db.execute("DELETE FROM cache WHERE key = ?", key)
    end
  end

  def clear
    with_db do |db|
      db.execute("DELETE FROM cache")
    end
  end

  def delete_older_than_age(age)
    delete_older_than_time(Time.now - age)
  end

  def delete_older_than_time(time)
    with_db do |db|
      db.execute("DELETE FROM cache WHERE updated_at < ?", time)
    end
  end

private
  def with_db(&block)
    db = SQLite3::Database.new(@path)
    begin
      block.call(db)
    ensure
      db.close
    end
  end

  def get_db(db, key)
    db.get_first_value("SELECT value FROM cache WHERE key = ?", key)
  end

  def self.disk_cache_dir
    Paths.work_dir + 'disk_cache'
  end
end
