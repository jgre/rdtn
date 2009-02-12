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

contacts = network.degrees.sort.reverse
neighbors = network.numbersOfNeighbors.sort.reverse

#bins = Hash.new{|h, k| h[k] = 0}
#binsize = 50
#degrees.each {|degree| bins[degree/binsize*binsize] += 1}
#
#cum_degrees = []
#bins.values.each {|n| cum_degrees << cum_degrees.last.to_f + n/degrees.length.to_f}
#puts cum_degrees.inspect
#puts bins.inspect

Gnuplot.open do |gp|
  Gnuplot::Plot.new(gp) do |plot|
    plot.terminal 'svg'
    plot.output   'contact_dist.svg'
    #plot.xlabel   'degree'
    plot.logscale :y
    #plot.ylabel   'cumulative frequency'
    #plot.title    '{:subscription_range => 5, :storage_limit => 10}'

    plot.data << Gnuplot::DataSet.new([(1..contacts.length).to_a, contacts]) do |ds|
      ds.title = "contacts"
      ds.with = "linespoints"
    end
    plot.data << Gnuplot::DataSet.new([(1..neighbors.length).to_a, neighbors]) do |ds|
      ds.title = "neighbors"
      ds.with = "linespoints"
    end
    #plot.data << Gnuplot::DataSet.new([bins.keys, cum_degrees]) do |ds|
    #  ds.title = "degrees"
    #  ds.with = "linespoints"
    #end
  end
end
