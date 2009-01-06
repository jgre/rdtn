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
    get_ds = lambda do |entry|
      ret = {}
      if (ds = options[:dataset]).is_a? Enumerable
	ds.each {|ds_id| ret[ds_id] = entry[ds_id]}
      else
	ret[ds] = entry[ds]
      end
      ret
    end

    ret = []
    # The datasets are sorted as strings as they might contain different
    # datatypes and even be nil. The wrong order of numeric values does not
    # matter since the sorting is only done to have equal values next to each
    # other.
    # The x values are sorted as floats, as they must be sorted in the datasets
    # so that they can be plotted properly.
    variants.sort_by{|v| [get_ds[v[0]].to_s, v[0][options[:x_axis]].to_f]}.each do |variant|
      cur_ds_val = get_ds[variant[0]]
      set        = ret.last
      if set.nil? or get_ds[set.dataset] != cur_ds_val
	ret << set = Struct::Dataset.new(cur_ds_val, [])
      end
      x = variant[0][options[:x_axis]]
      y = yield(cur_ds_val, x, variant[1], variant[2])
      set.values << [x] + y unless y.nil?
    end
    ret
  end

end
