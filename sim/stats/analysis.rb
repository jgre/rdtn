$:.unshift File.join(File.dirname(__FILE__), "..")
$:.unshift File.join(File.dirname(__FILE__))

require 'networkmodel'
require 'trafficmodel'

class Dataset
  attr_accessor :identifier, :rows
  attr_reader   :dat_conf

  class Row
    attr_accessor :network, :traffic
    attr_reader   :inputs, :values, :errors

    def initialize(variant, network, traffic)
      @inputs  = variant
      @network = network
      @traffic = traffic
      @values  = {}
      @errors  = {}

      variant.each {|name, val| value(name, val)}
    end

    def value(name, val = nil)
      @values[name] = val if val
      @values[name]
    end

    def std_error(name, val = nil)
      @errors[name] = val if val
      @errors[name]
    end

    def to_s
      "#{@values.values.join(' ')}"
    end

    def dump
      @values.values
    end

  end

  def initialize(dataset = {})
    @identifier = dataset
    @rows    = []
  end

  def to_s
    @rows.inject("") {|memo, row| memo+"#{row.to_s}\n"}
  end

  def dump
    [@dataset, @rows.map {|row| row.dump}]
  end

end

class Analysis

  attr_accessor :dataset, :x_axis, :gnuplot
  attr_reader   :datasets

  # variants is a list of lists with the following structure:
  # * A Hash of the configuration of the run of an experiment (e.g. {:a => 1,
  #   :b1 =>} where :a and :b are variables in the the experiment),
  # * the network model of the experiment run,
  # * the traffic model of the experiment run.
  def initialize(variants, options = {}, &configure)
    @variants   = variants
    @datasets   = []
    @experiment = options[:experiment] || 'test'
    @rows       = []
    configure[self]
  end

  def configure_plot(&configure)
    @plot_conf = configure
  end

  def configure_data(options = {}, &configure)
    @variants.each do |variant|
      row = Dataset::Row.new(variant[0],variant[1],variant[2])
      configure[row, row.network, row.traffic]
      @rows << row
    end
  end

  def combine_datasets(options = {})
    x_axis = options[:x_axis]
    # Sort variants into a hash where all variant variables except for the x
    # values are keys.
    variant_hash = Hash.new {|h, k| h[k] = []}
    @rows.each do |row|
      variant_id = Hash.new.merge(row.inputs)
      variant_id.delete(x_axis)
      variant_id.each {|key, val| variant_id[key] = val.last if val.is_a? Array}
      variant_hash[YAML.dump(variant_id)] << row
    end

    # Datasets that will be combined in one plot, are sorted into ds_hash with
    # the same key. That key is the variant_id without the combination id.
    ds_hash = Hash.new{|h, k| h[k] = []}
    variant_hash.each do |vid, rows|
      key = YAML.load(vid)
      key.delete(options[:combine])
      ds_hash[YAML.dump(key)] << (set = Dataset.new(YAML.load(vid)))
      set.rows = rows.sort_by {|row| row.value(x_axis).to_f}
      set.rows.delete_if {|row| row.values.empty?}
    end

    @datasets = ds_hash.values.flatten
    ds_hash
  end

  def plot(options = {}, &plot_conf)
    require 'gnuplot'

    maxima = {}
    minima = {}
    @rows.each do |row|
      row.values.each do |k, v|
	if v.is_a? Numeric
	  maxima[k] = maxima[k] ? [maxima[k], v].max : v
	  minima[k] = minima[k] ? [minima[k], v].min : v
	end
      end
    end

    dirname = File.join(File.dirname(__FILE__),
			"../../simulations/analysis/#{@experiment}")
    FileUtils.mkdir_p dirname

    combine_datasets(options).each do |k, combined_sets|
      key = YAML.load(k)

      y_axis = options[:y_axis].clone
      x_axis = options[:x_axis]

      ds_name = (key.to_s + y_axis.to_s).gsub(/[\":\{\}\/ ,]/, "")
      fname   = File.join(dirname, ds_name + '.svg')

      only_once = (options[:only_once] || []).clone

      Gnuplot.open do |gp|
	Gnuplot::Plot.new(gp) do |plot|
	  plot.title    key
	  plot.terminal 'svg'
	  plot.output   fname
	  plot.xlabel   x_axis.to_s
	  plot.ylabel   y_axis.first.to_s

	  maxy = y_axis.map {|y_name| maxima[y_name]}.max
	  miny = y_axis.map {|y_name| minima[y_name]}.min
	  maxy += maxy*0.1
	  miny -= miny*0.1
	  plot.yrange   "[#{miny}:#{maxy}]"

	  @plot_conf[plot] if @plot_conf

	  combined_sets.each do |dataset|
	    combine = options[:combine]

	    x = dataset.rows.map {|row| row.value(x_axis)}

	    y_axis.each do |name|
	      y     = dataset.rows.map {|row| row.value(name)}
	      error = dataset.rows.map {|row| row.std_error(name)}
	      plot.data << Gnuplot::DataSet.new([x, y, error]) do |ds|
		if only_once.include?(name)
		  ds.title = name
		else
		  ds.title = "#{combine ? dataset.identifier[combine] : key} #{name}"
		end
		ds.with = error.empty? ? "linespoints" : "yerrorlines"
		dataset.dat_conf[ds] if dataset.dat_conf
	      end
	    end

	    y_axis -= only_once

	  end
	end
      end
    end
  end

  def self.dump(datasets, name)
    dir = File.join(File.dirname(__FILE__),"../../simulations/analysis/#{name}")
    FileUtils.mkdir_p dir
    datasets.each do |ds|
      fname = ds.dataset.to_s.gsub(/[\":\{\}\/ ,]/, "")
      open(File.join(dir, fname), 'w') {|f| f.write(ds.to_s)}
    end
  end

end
