lambda do
  testdir = File.dirname(File.realpath(__FILE__))
  tests = Dir.entries(testdir).select {|e| e.end_with?('_test.rb') }
  tests.sort!
  for test in tests
    require "#{testdir}/#{test}"
  end
end.call
