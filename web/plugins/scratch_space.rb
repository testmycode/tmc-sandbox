require 'sandbox_app'
require 'ext2_utils'
require 'number_utils'
require 'shell_utils'

# Provides the sandbox with an empty ext2 formatted disk image as 'ubdf'
class ScratchSpace < SandboxApp::Plugin
  def initialize(*args)
    super

    if @plugin_settings['alternate_work_dir']
      @image_dir = Pathname(@plugin_settings['alternate_work_dir'])
    else
      @image_dir = Paths.work_dir + 'scratch_space'
    end

    FileUtils.mkdir_p(@image_dir)

    @size = NumberUtils.byte_spec_to_int(@plugin_settings['img_size'])

    @image_paths = []
    @settings['max_instances'].times do |i|
      path = "#{@image_dir}/#{i}.img"
      create_image(path) if !File.exists?(path) || File.size(path) != @size
      @image_paths << path
    end
  end

  def extra_images(options)
    {
      :ubdf => @image_paths[options[:instance].index]
    }
  end

  def before_exec(options)
    Ext2Utils.mke2fs(@image_paths[options[:instance].index])
  end

  private

  def create_image(path)
    File.unlink(path) if File.exists?(path)
    ShellUtils.sh!(['fallocate', '-l', @size, path])
  end
end
