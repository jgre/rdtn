$:.unshift File.join(File.dirname(__FILE__), "../sim/")
$:.unshift File.join(File.dirname(__FILE__), "../sim/stats")

require 'networkmodel'
require 'trafficmodel'
require 'statistics'

require 'gnuplot'

dir = ARGV[0]
puts dir

networkfile = File.join(dir, 'network')
trafficfile = File.join(dir, 'traffic')
variantfile = File.join(dir, 'variant')
variant = open(variantfile) {|f| YAML.load(f)}
network = open(networkfile) {|f| Marshal.load(f)}
traffic = open(trafficfile) {|f| Marshal.load(f)}

#puts "Expected (greedy) #{traffic.numberOfExpectedBundles}"
#puts "Expected (opportunistic) #{traffic.numberOfExpectedBundles(:net => network)}"

delays = traffic.delays.sort
#delays2 = traffic.delays(true).sort

bins = Hash.new{|h, k| h[k] = 0}
binsize = 60
delays.each {|delay| bins[delay/60*60] += 1}

cum_delays = []
bins.values.each {|n| cum_delays << cum_delays.last.to_f + n/delays.length.to_f}

Gnuplot.open do |gp|
  Gnuplot::Plot.new(gp) do |plot|
    #plot.data << Gnuplot::DataSet.new([(1..delays2.length).to_a, delays2]) do |ds|
    #  ds.title = "delay (with registrations)"
    #  ds.with = "linespoints"
    #end
    plot.terminal 'svg'
    plot.output   'delay_dist.svg'
    plot.xlabel   'delay (hours)'
    plot.ylabel   'cumulative frequency'
    plot.title    '{:subscription_range => 5, :storage_limit => 10}'

    plot.data << Gnuplot::DataSet.new([bins.keys.map{|d| d/3600.0}, cum_delays]) do |ds|
    #plot.data << Gnuplot::DataSet.new([(1..delays1.length).to_a, delays1]) do |ds|
      ds.title = "DPSP (known subscription filter) delay (hours)"
      ds.with = "linespoints"
    end
  end
end
