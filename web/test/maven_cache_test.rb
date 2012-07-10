require File.dirname(File.realpath(__FILE__)) + '/test_helper.rb'
require './sandbox_app'
require './plugins/maven_cache'

class MavenCacheTest < MiniTest::Unit::TestCase
  def setup
    @@settings ||= SandboxApp.load_settings
    SandboxApp.debug_log = Logger.new(@@settings['debug_log_file'])
    @conf = @@settings['plugins']['maven_cache']
    if !@conf['enabled']
      warn "maven_cache plugin disabled. Not running its tests since it requires system configuration."
      skip
    end
    
    @tmpdir = Dir.mktmpdir("maven_cache_test")
    @conf['img1'] = "#{@tmpdir}/maven/1.img"
    @conf['img2'] = "#{@tmpdir}/maven/2.img"
    @conf['symlink'] = "#{@tmpdir}/maven/current.img"
    @conf['work_dir'] = "#{@tmpdir}/maven/work"
    @conf['img_size'] = "48M"
    
    @mc = MavenCache.new(@@settings)
    
    @test_root_dir = File.dirname(File.realpath(__FILE__))
    @initial_dir = Dir.pwd
  end
  
  def teardown
    if @conf['enabled']
      FileUtils.rm_rf(@tmpdir)
      SandboxApp.debug_log.debug "----- TEST FINISHED -----"
    end
  end
  
  # This is a very basic test, but enough to be reasonably confident that
  # it doesn't crash and actually downloads something.
  def test_maven_cache
    tar_file = "#{@tmpdir}/submission.tar"
    tar_fixture('maven_project', tar_file)
    
    @mc.start_caching_deps(tar_file)
    
    SandboxApp.debug_log.debug "Test task added"
    
    assert_equal 1, @mc.maven_projects_seen
    assert_equal 1, @mc.daemon_start_count
    
    @mc.wait_for_daemon
    
    print_debug_logs

    check_dep_exists_in_both_images("org/apache/commons/commons-io/1.3.2")
  end
  
  def test_maven_cache_two_tasks
    tar_file = "#{@tmpdir}/submission.tar"
    tar_fixture('maven_project', tar_file)
    @mc.start_caching_deps(tar_file)
    tar_fixture('maven_project2', tar_file)
    @mc.start_caching_deps(tar_file)
    
    SandboxApp.debug_log.debug "Test tasks added"
    
    # Should only start the daemon once
    assert_equal 2, @mc.maven_projects_seen
    assert_equal 1, @mc.daemon_start_count
    
    @mc.wait_for_daemon
    
    print_debug_logs

    check_dep_exists_in_both_images("org/apache/commons/commons-io/1.3.2")
    check_dep_exists_in_both_images("com/google/code/gson/gson/2.2.1")
  end
  
private
  # For debugging
  def print_debug_logs
    print_debug_log('log')
    print_debug_log('rsync-log')
  end

  def print_debug_log(name)
    tar_path = "#{work_dir_path}/#{name}.tar"
    begin
      SandboxApp.debug_log.debug "Log file in #{name}.tar:"
      cmd = Shellwords.join(['tar', '--to-stdout', '-xf', tar_path, 'log.txt'])
      SandboxApp.debug_log.debug `#{cmd} 2>&1`
    rescue
      SandboxApp.debug_log.debug "No #{name}.tar file produced"
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
  
  def work_dir_path
    File.realpath(@conf['work_dir'])
  end
  
  def check_dep_exists_in_both_images(dep)
    components = dep.split("/")
    version = components.pop
    name = components.pop
    
    for img in ['1.img', '2.img']
      cmd = Shellwords.join(['e2ls', "#{@tmpdir}/maven/#{img}:/maven/repository/#{dep}"])
      ls_output = `#{cmd} 2>&1`
      assert ls_output.include?("#{name}-#{version}.jar"), "#{name}-#{version}.jar not found. ls output:\n#{ls_output}"
      assert ls_output.include?("#{name}-#{version}.pom"), "#{name}-#{version}.pom not found. ls output:\n#{ls_output}"
    end
  end
end
