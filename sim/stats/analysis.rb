$:.unshift File.join(File.dirname(__FILE__), "..")
$:.unshift File.join(File.dirname(__FILE__))

require 'networkmodel'
require 'trafficmodel'

class Dataset
  attr_accessor :dataset, :rows
  attr_reader   :dat_conf

  class Row
    attr_accessor :x, :network, :traffic
    attr_reader   :values, :errors

    def initialize(x, network, traffic)
      @x = x
      @network = network
      @traffic = traffic
      @values  = {}
      @errors  = {}
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
      "#@x #{@values.values.join(' ')}"
    end

    def dump
      [x] + @values.values
    end

  end

  def initialize(dataset = {})
    @dataset = dataset
    @rows    = []
  end

  def to_s
    @rows.inject("") {|memo, row| memo+"#{row.to_s}\n"}
  end

  def dump
    [@dataset, @rows.map {|row| row.dump}]
  end

  def sort!
    @rows = @rows.sort_by {|row| row.x.to_f}
  end

  #def configure_data(&configure)
  #  @dat_conf = configure
  #end

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
    configure[self]
  end

  def configure_plot(&configure)
    @plot_conf = configure
  end

  def configure_data(options = {}, &configure)
    x_axis = options[:x_axis]
    # Sort variants into a hash where all variant variables except for the x
    # values are keys.
    variant_hash = Hash.new {|h, k| h[k] = []}
    @variants.each do |variant|
      variant_id = Hash.new.merge(variant[0])
      variant_id.delete(x_axis)
      variant_id.each {|key, val| variant_id[key] = val.last if val.is_a? Array}
      variant_hash[YAML.dump(variant_id)] << variant
    end

    # Datasets that will be combined in one plot, are sorted into ds_hash with
    # the same key. That key is the variant_id without the combination id.
    @ds_hash = Hash.new{|h, k| h[k] = []}
    variant_hash.each do |vid, variants|
      variant_id = YAML.load(vid)
      key = Hash.new.merge(variant_id)
      key.delete(options[:combine])
      @ds_hash[YAML.dump(key)] << (set = Dataset.new(variant_id))
      variants.each do |variant|
	row = Dataset::Row.new(variant[0][x_axis],variant[1],variant[2])
	configure[row, row.x, row.network, row.traffic]
	set.rows << row
      end
      set.rows.delete_if {|row| row.values.empty?}
      set.sort!

    end

    @datasets = @ds_hash.values.flatten
  end

  def plot(options = {}, &plot_conf)
    require 'gnuplot'

    y_axis = options[:y_axis]
    x_axis = options[:x_axis]

    dirname = File.join(File.dirname(__FILE__),
			"../../simulations/analysis/#{@experiment}")
    FileUtils.mkdir_p dirname

    @ds_hash.each do |k, combined_sets|
      key = YAML.load(k)

      ds_name = (key.to_s + y_axis.to_s).gsub(/[\":\{\}\/ ,]/, "")
      fname   = File.join(dirname, ds_name + '.svg')

      only_once = options[:only_once] || []

      Gnuplot.open do |gp|
	Gnuplot::Plot.new(gp) do |plot|
	  plot.title    key
	  plot.terminal 'svg'
	  plot.output   fname

	  @plot_conf[plot] if @plot_conf

	  combined_sets.each do |dataset|
	    combine = options[:combine]

	    x = dataset.rows.map {|row| row.x}

	    ys     = Hash.new {|h, k| h[k] = []}
	    errors = Hash.new {|h, k| h[k] = []}
	    dataset.rows.each do |row|
	      row.values.each {|k, val| ys[k]     << val if y_axis.include?(k)}
	      row.errors.each {|k, val| errors[k] << val}
	    end

	    ys.each do |name, y|
	      error = errors[name]
	      plot.data << Gnuplot::DataSet.new([x, y, error]) do |ds|
		if only_once.include?(name)
		  ds.title = name
		else
		  ds.title="#{combine ? dataset.dataset[combine] : key} #{name}"
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
