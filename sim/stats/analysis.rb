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

    tuples   = {}
    processed.each do |entry|
      if entry[x_axis] and entry[y_axis]
        enum_key = entry.select {|k, v| enum.include? k}
        comb_key = entry.select {|k, v| combine == k}
        comb = tuples[enum_key]  ||= {}
        val  = comb[comb_key] ||= []
        val << [entry[x_axis], entry[y_axis], entry[error]]
      end
    end

    res = {}
    tuples.each do |enum_key, entry|
      en   = res[enum_key] = {}
      entry.each do |comb_key, comb|
        tuple_lst = comb.sort_by(&:first)
        hash = {}
        hash[x_axis] = tuple_lst.map(&:first)
        hash[y_axis] = tuple_lst.map {|e| e[1]}
        hash[error]  = tuple_lst.map(&:last)
        hash.delete(error) if hash[error].compact.empty?
        en[comb_key] = hash
      end
    end
    res
  end

  def self.plot(aggregated, options)

    x_axis  = options[:x_axis]
    y_axis  = options[:y_axis]
    dir     = options[:dir]
    translate = options[:translate] || {}

    miny = aggregated.values.inject([]){|memo, set| memo + set.values.inject([]){|memo, data| memo + data[y_axis]}}.compact.min
    maxy = aggregated.values.inject([]){|memo, set| memo + set.values.inject([]){|memo, data| memo + data[y_axis]}}.compact.max
    miny -= miny*0.1
    maxy += maxy*0.1

    FileUtils.mkdir_p dir

    aggregated.each do |key, plotset|
      fname = File.join(dir, "#{key} [#{y_axis}].svg".gsub(/[\":\{\}\/ ,]/, ""))
      Gnuplot.open do |gp|
	Gnuplot::Plot.new(gp) do |plot|
	  plot.title    key.to_s
	  plot.terminal 'svg'
	  plot.output   fname
	  plot.xlabel   translate[x_axis] || x_axis.to_s
	  plot.ylabel   translate[y_axis] || y_axis.to_s

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
