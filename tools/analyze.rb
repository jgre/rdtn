#!/usr/bin/env ruby
$: << File.join(File.dirname(__FILE__), '../sim/stats/')
require 'yaml'
require 'networkmodel'
require 'trafficmodel'
require 'optparse'

OptionParser.accept(Time, /(\d{2})(\d{2})(\d{2})/) do |time, hour, min, sec|
  n = Time.now
  Time.local(n.year, n.month, n.day, hour.to_i, min.to_i, sec.to_i)
end
OptionParser.accept(Date, /(\d{4})(\d{2})(\d{2})/) do |date, year, month, day|
  puts "Date #{year}, #{month}, #{day}"
  Time.local(year.to_i, month.to_i, day.to_i)
end

date    = "*"
time    = "*"
variant = "*"
all     = false
opts    = OptionParser.new
opts.on('-d', '--date DATE', Date) {|d| date = d.strftime('%Y%m%d')}
opts.on('-t', '--time TIME', Time) {|t| time = t.strftime('%H%M%S')}
opts.on('-v', '--variant INDEX')   {|i| variant = i}
opts.on('-a', '--all')             {all = true}
specs = opts.parse(ARGV)

specs = ["*"] if specs.empty?

RESDIR = File.join(File.dirname(__FILE__), '../simulations/results')
expr   = File.join(RESDIR, "{#{specs.join(',')}}-#{variant}-#{date}-#{time}")

results = Dir.glob(expr).sort_by {|dirname| File.mtime(dirname)}

exit 1 if results.empty?

results[(all ? 0 : -1)..-1].each do |dir|
  networkfile = File.join(dir, 'network')
  trafficfile = File.join(dir, 'traffic')
  variantfile = File.join(dir, 'variant')

  next unless File.exist?(networkfile) and File.exist?(trafficfile)

  puts "Opening stats for from #{dir}"

  if File.exist? variantfile
    STDOUT.write(open(variantfile) {|f| f.read})
  end

  $network = open(networkfile) {|f| Marshal.load(f)}
  $traffic = open(trafficfile) {|f| YAML.load(f)}

  if $0 == __FILE__
    puts "#{$network.numberOfNodes} nodes"
    puts "#{$traffic.numberOfBundles} bundles"
    puts "#{$traffic.numberOfExpectedBundles} expected bundles"
    puts "#{$traffic.numberOfDeliveredBundles} bundles delivered"
    puts "#{$traffic.deliveryRatio * 100}% deliveryRatio"
    puts "#{$traffic.numberOfTransmissions} transmissions"
    puts
  end
end
