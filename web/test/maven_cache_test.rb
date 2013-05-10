require File.dirname(File.realpath(__FILE__)) + '/test_helper.rb'
require './plugins/maven_cache'
require 'paths'
require 'process_user'
require 'test_network_setup'
require 'fileutils'

# This test is unfortunately VERY slow, since Maven in UML, even through a HTTP cache,
# needs very many dependencies when starting from scratch and is quite slow at downloading them.
class MavenCacheTest < MiniTest::Unit::TestCase
  include TestNetworkSetup

  def setup
    ProcessUser.drop_root!

    AppLog.set(Logger.new(Paths.log_dir + 'test.log'))

    @tmpdir = Paths.work_dir + 'test_tmp' + 'maven_cache_test'
    FileUtils.rm_rf(@tmpdir)
    FileUtils.mkdir_p(@tmpdir)

    FileUtils.mkdir_p(maven_cache_work_dir)

    @test_settings = Settings.get.clone
    @conf = @test_settings['plugins']['maven_cache']
    @conf['enabled'] = true
    @conf['img_size'] = "48M"
    @conf['alternate_work_dir'] = maven_cache_work_dir

    @do_teardown = true
    if !ProcessUser.can_become_root?
      warn "maven_cache tests must be run as root. Skipping."
      @do_teardown = false
      skip
    end

    fail "Please install e2tools to run this test" if `which e2ls`.strip.empty?

    @test_root_dir = File.dirname(File.realpath(__FILE__))

    ProcessUser.become_root!

    setup_network(TapDevice.new(@conf['tap_device'], @conf['tap_ip'], Settings.tmc_user)) do
      # network is torn down if this block fails
      ProcessUser.drop_root!
      @mc = MavenCache.new(@test_settings)
    end
  end

  def teardown
    if @do_teardown
      AppLog.debug "Ending test"
      @mc.kill_daemon_if_running

      teardown_network

      FileUtils.rm_rf(@tmpdir)
      AppLog.debug "----- TEST FINISHED -----"
    end
  end
  
  # This is a very basic test, but enough to be reasonably confident that
  # it doesn't crash and actually downloads something.
  def test_maven_cache
    tar_file = "#{@tmpdir}/submission.tar"
    tar_fixture('maven_project', tar_file)
    
    @mc.start_caching_deps(tar_file)

    AppLog.debug "Test task added"

    assert_equal 1, @mc.maven_projects_seen
    assert_equal 1, @mc.daemon_start_count
    
    @mc.wait_for_daemon

    check_dep_exists_in_both_images("org/apache/commons/commons-io/1.3.2")
  end
  
  def test_maven_cache_two_tasks
    tar_file = "#{@tmpdir}/submission.tar"
    tar_fixture('maven_project', tar_file)
    @mc.start_caching_deps(tar_file)
    tar_fixture('maven_project2', tar_file)
    @mc.start_caching_deps(tar_file)
    
    AppLog.debug "Test tasks added"
    
    # Should only start the daemon once
    assert_equal 2, @mc.maven_projects_seen
    assert_equal 1, @mc.daemon_start_count
    
    @mc.wait_for_daemon

    check_dep_exists_in_both_images("org/apache/commons/commons-io/1.3.2")
    check_dep_exists_in_both_images("com/google/code/gson/gson/2.2.1")
  end

  def test_skips_project_already_seen
    tar_file = "#{@tmpdir}/submission.tar"
    tar_fixture('maven_project', tar_file)
    @mc.start_caching_deps(tar_file)
    @mc.wait_for_daemon
    tar_fixture('maven_project', tar_file)
    @mc.start_caching_deps(tar_file)

    AppLog.debug "Test tasks added"

    # Should skip the project once it's seen for the second time,
    # after the first download has succeeded.
    assert_equal 2, @mc.maven_projects_seen
    assert_equal 1, @mc.maven_projects_skipped_immediately
    assert_equal 1, @mc.daemon_start_count

    @mc.wait_for_daemon

    check_dep_exists_in_both_images("org/apache/commons/commons-io/1.3.2")
  end

  def test_same_task_twice_quickly
    tar_file = "#{@tmpdir}/submission.tar"
    tar_fixture('maven_project', tar_file)
    @mc.start_caching_deps(tar_file)
    tar_fixture('maven_project', tar_file)
    @mc.start_caching_deps(tar_file)

    AppLog.debug "Test tasks added"

    # We just check that is basically works
    @mc.wait_for_daemon

    check_dep_exists_in_both_images("org/apache/commons/commons-io/1.3.2")
  end
  
private
  # For debugging
  def print_debug_logs
    print_debug_log('log')
    print_debug_log('rsync-log')
  end

  def print_debug_log(name)
    tar_path = "#{maven_cache_work_dir}/#{name}.tar"
    begin
      AppLog.debug "Log file in #{name}.tar:"
      cmd = Shellwords.join(['tar', '--to-stdout', '-xf', tar_path, 'log.txt'])
      AppLog.debug `#{cmd} 2>&1`
    rescue
      AppLog.debug "No #{name}.tar file produced"
    end
  end

  def tar_fixture(fixture, tar_file)
    ShellUtils.sh! [
      'tar',
      '-C',
      "#{fixtures_path}/#{fixture}",
      '-cf',
      tar_file,
      '.'
    ]
  end

  def fixtures_path
    "#{@test_root_dir}/fixtures"
  end

  def maven_cache_work_dir
    "#{@tmpdir}/maven_cache_work_dir"
  end
  
  def check_dep_exists_in_both_images(dep)
    components = dep.split("/")
    version = components.pop
    name = components.pop
    
    for img in ['1.img', '2.img']
      cmd = Shellwords.join(['e2ls', "#{maven_cache_work_dir}/#{img}:/maven/repository/#{dep}"])
      ls_output = `#{cmd} 2>&1`
      assert ls_output.include?("#{name}-#{version}.jar"), "#{name}-#{version}.jar not found. ls output:\n#{ls_output}"
      assert ls_output.include?("#{name}-#{version}.pom"), "#{name}-#{version}.pom not found. ls output:\n#{ls_output}"
    end
  end
end
