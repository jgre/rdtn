$:.unshift File.join(File.dirname(__FILE__), "..")
$:.unshift File.join(File.dirname(__FILE__))

require 'networkmodel'
require 'trafficmodel'
require 'gnuplot'

module Analysis

  def self.preprocess(variants, &block)
    ret = variants.map do |var|
      if block.nil?
	var[0]
      else
        ret = block[*var]
        ret = ret.is_a?(Array) ? ret : [ret]
        ret.map {|r| r.merge var[0]}
      end
    end
    ret.flatten
  end

  def self.aggregate(processed, options)
    x_axis  = options[:x_axis]
    y_axis  = options[:y_axis]
    error   = "#{y_axis}_error"
    enum    = options[:enumerate] || []
    combine = options[:combine]   || []

    res = {}
    processed.each do |entry|
      enum_key = entry.select {|k, v| enum.include? k}
      comb_key = entry.select {|k, v| combine == k}
      comb = res[enum_key]  ||= {}
      val  = comb[comb_key] ||= {}
      (val[x_axis] ||= []) << entry[x_axis]
      (val[y_axis] ||= []) << entry[y_axis]
      (val[error]  ||= []) << entry[error] if entry[error]
    end
    res
  end

  def self.plot(aggregated, options)

    x_axis  = options[:x_axis]
    y_axis  = options[:y_axis]
    dir     = options[:dir]
    translate = options[:translate] || {}

    miny = aggregated.values.inject([]){|memo, set| memo + set.values.inject([]){|memo, data| memo + data[y_axis]}}.min
    maxy = aggregated.values.inject([]){|memo, set| memo + set.values.inject([]){|memo, data| memo + data[y_axis]}}.max
    miny -= miny*0.1
    maxy += maxy*0.1

    FileUtils.mkdir_p dir

    aggregated.each do |key, plotset|
      fname = File.join(dir, "#{key} [#{y_axis}].svg".gsub(/[\":\{\}\/ ,]/, ""))
      Gnuplot.open do |gp|
	Gnuplot::Plot.new(gp) do |plot|
	  plot.title    key
	  plot.terminal 'svg'
	  plot.output   fname
	  plot.xlabel   x_axis.to_s
	  plot.ylabel   y_axis.to_s

	  plot.yrange   "[#{miny}:#{maxy}]"

	  yield plot if block_given?

	  plotset.each do |comb_key, data|
	    error = data["#{y_axis}_error"] || []
	    plot.data << Gnuplot::DataSet.new([data[x_axis], data[y_axis], error]) do |ds|
	      title_str = comb_key.values.first || key.values.first
	      ds.title = translate[title_str] || title_str
	      ds.with = error.empty? ? "linespoints" : "yerrorlines"
	    end
	  end 
	end
      end
    end
  end

end
