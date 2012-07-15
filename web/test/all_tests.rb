require File.dirname(File.realpath(__FILE__)) + '/test_helper.rb'
lambda do
  testdir = File.dirname(File.realpath(__FILE__))
  tests = Dir.entries(testdir).select {|e| e.end_with?('_test.rb') }
  tests.sort!

  puts "Note: some of these tests normally take several minutes to run."
  puts

  for test in tests
    puts "Running #{test}"
    system("ruby #{testdir}/#{test}")
  end
end.call
