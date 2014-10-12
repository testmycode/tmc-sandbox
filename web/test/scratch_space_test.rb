require File.dirname(File.realpath(__FILE__)) + '/test_helper.rb'
require './plugins/scratch_space'
require 'fileutils'
require 'paths'
require 'process_user'
require 'shell_utils'
require 'shellwords'

class ScratchSpaceTest < MiniTest::Unit::TestCase
  def setup
    fail "Please install e2tools to run this test" if `which e2ls`.strip.empty?

    ProcessUser.drop_root!

    AppLog.set(Logger.new(Paths.log_dir + 'test.log'))

    @tmpdir = Paths.work_dir + 'test_tmp' + 'scratch_space_test'
    FileUtils.rm_rf(@tmpdir)
    FileUtils.mkdir_p(@tmpdir)

    @test_settings = Settings.get.clone
    @test_settings['max_instances'] = 2
    @conf = @test_settings['plugins']['scratch_space']
    @conf['enabled'] = true
    @conf['img_size'] = "48M"
    @conf['alternate_work_dir'] = @tmpdir
  end

  def test_scratch_space
    ss = ScratchSpace.new(@test_settings)

    instance = MiniTest::Mock.new
    3.times { instance.expect(:index, 1) }

    extra_images = ss.extra_images(:instance => instance)
    ss.before_exec(:instance => instance)

    img = extra_images[:ubdf]
    assert !img.nil?
    assert !img.empty?
    assert File.exists?(img)
    assert 48 * 1024 * 1024, File.size(img)

    ShellUtils.sh!(['e2mkdir', "#{img}:/foo"])

    ss.before_exec(:instance => instance)  # should clear out the 'foo' directory

    cmd = Shellwords.join(['e2ls', "#{img}:/"])
    ls_output = `#{cmd} 2>&1`
    assert_equal 'lost+found', ls_output.strip  # no other directories
  end
end
