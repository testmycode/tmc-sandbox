
require 'hash_deep_merge'
require 'yaml'
require 'paths'

# The contents of site.defaults.yml + site.yml
module Settings
  def self.get
    @data ||= load
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
