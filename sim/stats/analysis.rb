$:.unshift File.join(File.dirname(__FILE__), "..")
$:.unshift File.join(File.dirname(__FILE__))

require 'networkmodel'
require 'trafficmodel'

Struct.new('Dataset', :dataset, :values)

class Struct::Dataset
  def to_s
    values.inject("") {|memo, val| memo + val.join(" ") + "\n"}
  end
end

module Analysis

  # Generate a list of datasets from the results of one or more experiment runs.
  # The output can be plotted e.g. with GnuPlot.
  # variants is a list of lists with the following structure:
  # * A Hash of the configuration of the run of an experiment (e.g. {:a => 1,
  #   :b1 =>} where :a and :b are variables in the the experiment),
  # * the network model of the experiment run,
  # * the traffic model of the experiment run.
  # options can contain values for :dataset which identifies the top level
  # variable, and :x_axis with identifes the variable that serves a x axis.
  # A block must be passed with takes the dataset identifier, the x value, the
  # network model, and the traffic model es parameters. The block should return
  # the y value or an array of values to be considered results for the given x
  # value.
  # 
  # The function returns a list of datasets (Struct::Dataset).
  def self.analyze(variants, options)
    ds  = options[:dataset]
    ret = []
    variants.sort_by{|v| v[0][ds]}.each do |variant|
      cur_ds_val = variant[0][ds]
      set        = ret.last
      if set.nil? or set.dataset[ds] != cur_ds_val
	ret << set = Struct::Dataset.new({ds => variant[0][ds]}, [])
      end
      x = variant[0][options[:x_axis]]
      set.values << [x] + yield(ds, x, variant[1], variant[2])
    end
    ret
  end

end
