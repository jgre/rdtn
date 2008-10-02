#!/usr/bin/env ruby
$: << File.join(File.dirname(__FILE__), '../sim/stats/')
require 'yaml'
require 'networkmodel'
require 'trafficmodel'

RESDIR = File.join(File.dirname(__FILE__), '../simulations/results')
expr   = File.join(RESDIR, ARGV[0].to_s + '*')
latest = Dir.glob(expr).sort.last

exit 1 if latest.nil?

puts "Opening stats for from #{latest}"

$network = open(File.join(latest, 'network')) {|f| Marshal.load(f)}
$traffic = open(File.join(latest, 'traffic')) {|f| YAML.load(f)}

if $0 == __FILE__
  puts "#{$network.numberOfNodes} nodes"
  puts "#{$traffic.numberOfBundles} bundles"
  puts "#{$traffic.numberOfExpectedBundles} expected bundles"
  puts "#{$traffic.numberOfDeliveredBundles} bundles delivered"
  puts "#{$traffic.deliveryRatio * 100}% deliveryRatio"
  puts "#{$traffic.numberOfTransmissions} transmissions"
end
