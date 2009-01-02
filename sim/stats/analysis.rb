$:.unshift File.join(File.dirname(__FILE__), "..")
$:.unshift File.join(File.dirname(__FILE__))

require 'networkmodel'
require 'trafficmodel'

Struct.new('Dataset', :dataset, :values)

class Analysis

  def initialize(variants)
    @variants = variants
  end

  def plot_results(options)
    ds  = options[:dataset]
    ret = []
    @variants.sort_by{|v| v[0][ds]}.each do |variant|
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
