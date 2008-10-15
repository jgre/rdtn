
task :default => [:test]

task :test do
  require "rake/runtest"
  begin
    require "rubygems"
    require "specdoc"
  rescue LoadError
  end
  Rake.run_tests "test/*test*.rb"
  Rake.run_tests "test/simulator/*test*.rb"
end

