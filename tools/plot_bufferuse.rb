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

lst = (1..network.numberOfNodes).map do |node|
  use = traffic.bufferUse(3600, node).map {|use| (use / 1024**2) / 10.0 * 100}
  [network.degree(node-1), use.mean, use.sterror]
end
lst = lst.sort_by(&:first)

Gnuplot.open do |gp|
  Gnuplot::Plot.new(gp) do |plot|
    plot.terminal 'svg'
    plot.output   'bufferuse_dist.svg'
    #plot.logscale :y
    plot.title    '{:subscription_range => 5, :storage_limit => 10}'
    plot.xlabel   'contacts'
    plot.ylabel   'buffer use'

    plot.data << Gnuplot::DataSet.new([lst.map(&:first), lst.map{|i| i[1]}, lst.map(&:last)]) do |ds|
      ds.title = "buffer use"
      ds.with = "yerrorbars"
    end
    #plot.data << Gnuplot::DataSet.new([bins.keys, cum_degrees]) do |ds|
    #  ds.title = "degrees"
    #  ds.with = "linespoints"
    #end
  end
end
