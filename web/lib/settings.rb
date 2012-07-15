
require 'hash_deep_merge'
require 'yaml'
require 'paths'
require 'etc'

# The contents of site.defaults.yml + site.yml
module Settings
  def self.get
    if !@data
      @data = load
      u = @data['tmc_user'].to_s
      if u =~ /^\d+$/
        @uid = u.to_i
        @user = Etc.getpwuid(@uid).name
      else
        @user = u
        @uid = Etc.getpwnam(@user).uid
      end

      g = @data['tmc_group'].to_s
      if g =~ /^\d+$/
        @gid = g.to_i
        @group = Etc.getgrgid(@gid).name
      else
        @group = g
        @gid = Etc.getgrnam(@group).gid
      end
    end
    @data
  end

  def self.tmc_user
    get
    @user
  end

  def self.tmc_group
    get
    @group
  end

  def self.tmc_user_id
    get
    @uid
  end

  def self.tmc_group_id
    get
    @gid
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
