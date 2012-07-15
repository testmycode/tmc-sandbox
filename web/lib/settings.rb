
require 'hash_deep_merge'
require 'yaml'
require 'paths'
require 'etc'

# The contents of site.defaults.yml + site.yml
module Settings
  def self.get
    @data ||= load
  end

  def self.tmc_user
    get['tmc_user']
  end

  def self.tmc_group
    get['tmc_group']
  end

  def self.tmc_user_id
    u = self.tmc_user
    if u =~ /^\d+$/
      u.to_i
    else
      Etc.getpwnam(u).uid
    end
  end

  def self.tmc_group_id
    g = self.tmc_group
    if g =~ /^\d+$/
      g.to_i
    else
      Etc.getgrnam(g).gid
    end
  end

private
  def self.load
    s = YAML.load_file(Paths.web_dir + 'site.defaults.yml')
    if File.exist?(Paths.web_dir + 'site.yml')
      s = s.deep_merge(YAML.load_file(Paths.web_dir + 'site.yml'))
    end
    s
  end
end
