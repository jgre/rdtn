
task :default => [:test]

task :test do
  require "rake/runtest"
  Rake.run_tests "test/test_*.rb"
end

#Rake::TestTask.new() do |t|
#  t.libs = []
#  #t.loader = :direct
#  #t.test_files = ["test/test_routetab.rb", "test/test_tcpcl.rb"]
#  #t.verbose = true
#end
