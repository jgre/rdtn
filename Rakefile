
task :default => [:test]

require 'rake/testtask'
Rake::TestTask.new do |t|
  begin
    require "rubygems"
    require "specdoc"
  rescue LoadError
  end
  t.test_files = FileList["test/*test*.rb", "test/simulator/*test*.rb"]
end

