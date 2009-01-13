$:.unshift File.join(File.dirname(__FILE__), '../../sim/stats')
$:.unshift File.join(File.dirname(__FILE__), '../../sim')

require 'rubygems'
require 'test/unit'
require 'shoulda'
require 'trafficmodel'
require 'networkmodel'
require 'logentry'
require 'analysis'

class AnalyzeTest < Test::Unit::TestCase

  context 'Analyzing the results for an experiment with two variables' do

    setup do
      @variants = [
        [{:a => 1, :b => 4}, NetworkModel.new, TrafficModel.new(0)],
        [{:a => 2, :b => 4}, NetworkModel.new, TrafficModel.new(0)],
        [{:a => 1, :b => 5}, NetworkModel.new, TrafficModel.new(0)],
        [{:a => 2, :b => 5}, NetworkModel.new, TrafficModel.new(0)]
      ]

      @analysis = Analysis.new(@variants) do |analysis|
        analysis.x_axis  = :b
	analysis.configure_data :x_axis => :b do |row, x, network, traffic|
	  row.value "1", network
	  row.value "2", traffic
        end
      end
      @datasets = @analysis.datasets
    end

    should 'produce datasets identified by variable :a that map variable :b to the network model and the traffic model' do
      expectation = [
        [{:a => 1}, [[4, @variants[0][1], @variants[0][2]],
                     [5, @variants[2][1], @variants[2][2]]]],
        [{:a => 2}, [[4, @variants[1][1], @variants[1][2]],
                     [5, @variants[3][1], @variants[3][2]]]]
      ]
      assert_same_elements expectation, @datasets.map {|ds| ds.dump}
    end

    should 'produce two datasets' do
      assert_equal 2, @datasets.length
      @datasets.each {|ds| assert_kind_of Dataset, ds}
    end

    should 'produce datasets identified by values for variable :a' do
      assert_same_elements [1, 2], @datasets.map {|ds| ds.dataset[:a]}
    end

    should 'contain the :b variable as the first entry in all value rows' do
      @datasets.each do |ds|
        assert_equal [4, 5], ds.rows.map {|row| row.x}
      end
    end

    should 'contain the network and traffic models as y values' do
      assert_same_elements @variants.map{|v| v[1..-1]},
       	@datasets.inject([]) {|memo, ds| memo + ds.rows.map {|v| v.dump[1..-1]}}
    end

  end

  context 'Putting Dataset into a string' do

    setup do
      @ds = Dataset.new({:a => 1})
      @ds.rows = [Dataset::Row.new(4, nil, nil),
                  Dataset::Row.new(5, nil, nil)]
      @ds.rows[0].value "a", 1000
      @ds.rows[0].value "b", 1200
      @ds.rows[1].value "a", 500
      @ds.rows[1].value "b", 900
      @str = @ds.to_s
    end

    should 'give an ASCII table' do
      expected = <<END_OF_STRING
4 1000 1200
5 500 900
END_OF_STRING
      assert_equal expected, @str
    end
  end

  context 'Analyzing the results for an experiment with three variables' do
    setup do
      @variants = [
        [{:a => 1, :b => 4, :c => 42.5}, NetworkModel.new, TrafficModel.new(0)],
        [{:a => 1, :b => 4, :c => 42},   NetworkModel.new, TrafficModel.new(0)],
        [{:a => 2, :b => 4, :c => 43},   NetworkModel.new, TrafficModel.new(0)],
        [{:a => 1, :b => 5, :c => 44},   NetworkModel.new, TrafficModel.new(0)],
        [{:a => 2, :b => 5, :c => 45},   NetworkModel.new, TrafficModel.new(0)]
      ]

      @analysis = Analysis.new(@variants) do |analysis|
	analysis.configure_data :x_axis => :c do |row, x, network_model, traffic_model|
	  row.value "1", network_model
	  row.value "2", traffic_model
        end
      end
      @datasets = @analysis.datasets
    end

    should 'produce datasets identified by variables :a and :b that map variable :c to the network model and the traffic model' do
      expectation = [
        [{:a => 1, :b => 4}, [[42,   @variants[1][1], @variants[1][2]],
        		      [42.5, @variants[0][1], @variants[0][2]]]],
        [{:a => 1, :b => 5}, [[44, @variants[3][1], @variants[3][2]]]],
        [{:a => 2, :b => 4}, [[43, @variants[2][1], @variants[2][2]]]],
        [{:a => 2, :b => 5}, [[45, @variants[4][1], @variants[4][2]]]]
      ]
      assert_same_elements expectation, @datasets.map {|ds| ds.dump}
    end

  end

  should 'cope with empty datasets' do
    @variants = [[{:a => 1, :b => 4},   NetworkModel.new, TrafficModel.new(0)],
                 [{:a => 1, :b => nil}, NetworkModel.new, TrafficModel.new(0)],
                 [{:a => 1, :b => 20},  NetworkModel.new, TrafficModel.new(0)]]
    @analysis = Analysis.new(@variants) do |analysis|
      analysis.configure_data :x_axis => :b do |row, x, network_model, traffic_model|
	unless x.nil?
	  row.value "1", network_model
	  row.value "2", traffic_model
	end
      end
    end
    @datasets = @analysis.datasets
    expectation = [
      [{:a => 1}, [[4,  @variants[0][1], @variants[0][2]],
                   [20, @variants[2][1], @variants[2][2]]]]
    ]
    assert_equal expectation, @datasets.map {|ds| ds.dump}
  end

  should 'use descriptions for datasets (if available)' do
    @variants = [[{:a=>[1,'uno'],:b=>4},NetworkModel.new,TrafficModel.new(0)],
                 [{:a=>2,:b=> nil},NetworkModel.new,TrafficModel.new(0)],
                 [{:a=>2,:b=> 20},NetworkModel.new,TrafficModel.new(0)]]
    @analysis = Analysis.new(@variants) do |analysis|
      analysis.configure_data :x_axis => :b do |row, x, network_model, traffic_model|
	unless x.nil?
	  row.value "1", network_model
	  row.value "2", traffic_model
	end
      end
    end
    @datasets = @analysis.datasets
    expectation = [
      [{:a => 2}, [[20, @variants[2][1], @variants[2][2]]]],
      [{:a => 'uno'},[[4,@variants[0][1],@variants[0][2]]]]
    ]
    assert_same_elements expectation, @datasets.map {|ds| ds.dump}
  end

  should 'be able to deal with returns from the block that are not arrays' do
    @variants = [[{:a=>1, :b => 4}, NetworkModel.new, TrafficModel.new(0)]]
    @analysis = Analysis.new(@variants) do |analysis|

      analysis.configure_data :x_axis => :b do |row, x, network_model, traffic_model|
	row.value "1", network_model unless x.nil?
      end
    end
    @datasets = @analysis.datasets
    expectation = [[{:a => 1}, [[4, @variants[0][1]]]]]
    assert_equal expectation, @datasets.map {|ds| ds.dump}
  end

  context 'Analysis with Enabled Gnuplot' do

    setup do
      @variants = [
        [{:scen => 1, :routing => "epidemic", :bundles => 42.5}, NetworkModel.new, TrafficModel.new(0)],
        [{:scen => 1, :routing => "epidemic", :bundles => 42},   NetworkModel.new, TrafficModel.new(0)],
        [{:scen => 2, :routing => "epidemic", :bundles => 43},   NetworkModel.new, TrafficModel.new(0)],
        [{:scen => 2, :routing => "epidemic", :bundles => 43.5}, NetworkModel.new, TrafficModel.new(0)],
        [{:scen => 1, :routing => "DPSP", :bundles => 44},   NetworkModel.new, TrafficModel.new(0)],
        [{:scen => 1, :routing => "DPSP", :bundles => 44.5}, NetworkModel.new, TrafficModel.new(0)],
        [{:scen => 2, :routing => "DPSP", :bundles => 45},   NetworkModel.new, TrafficModel.new(0)],
        [{:scen => 2, :routing => "DPSP", :bundles => 45.5}, NetworkModel.new, TrafficModel.new(0)]
      ]
      @experiment = 'MyTestExperiment'
      @dir = File.join(File.dirname(__FILE__),"../../simulations/analysis/#{@experiment}")
      FileUtils.rm_rf @dir
    end

    teardown do
      FileUtils.rm_rf @dir
    end

    should 'create an svg file' do
      @analysis = Analysis.new(@variants,:experiment=>@experiment) do |analysis|
        analysis.x_axis  = :bundles
        analysis.gnuplot = true

        analysis.configure_plot do |plot|
          plot.ylabel "Why?"
          plot.xlabel "What?"
        end
        analysis.configure_data :x_axis => :bundles do |row, x, network_model, traffic_model|
	  row.value "1", rand unless x.nil?
        end
	analysis.plot :x_axis => :bundles, :y_axis => ["1"]
      end
      assert File.exist?(File.join(@dir, 'scen1routingepidemic1.svg'))
      assert File.exist?(File.join(@dir, 'scen2routingepidemic1.svg'))
      assert File.exist?(File.join(@dir, 'scen1routingDPSP1.svg'))
      assert File.exist?(File.join(@dir, 'scen2routingDPSP1.svg'))
    end

    should 'combine datasets into one plot when the :combine option is set' do
      @analysis = Analysis.new(@variants,:experiment=>@experiment) do |analysis|
        analysis.configure_data :combine => :routing, :x_axis => :bundles do |row, x, network_model, traffic_model|
	  row.value "1", rand unless x.nil?
        end
	analysis.plot :x_axis => :bundles, :y_axis => ["1"]
      end
      assert_same_elements [File.join(@dir, 'scen11.svg'), File.join(@dir, 'scen21.svg')], Dir.glob("#{@dir}/*.svg")
    end

    should 'combine data with different values into one plot' do
      @analysis = Analysis.new(@variants,:experiment=>@experiment) do |analysis|
        analysis.configure_data :combine => :routing, :x_axis => :bundles do |row, x, network_model, traffic_model|
	  unless x.nil?
	    row.value "delivered", x
	    row.value "delay",     x + 10
	  end
	end
	analysis.plot :x_axis => :bundles, :y_axis => ["delivered", "delay"]
      end
      assert_same_elements [File.join(@dir, 'scen1delivereddelay.svg'),
	File.join(@dir, 'scen2delivereddelay.svg')],
       	Dir.glob("#{@dir}/*.svg")
    end

    should 'plot errorbars, if the standard error is supplied' do
      @analysis = Analysis.new(@variants,:experiment=>@experiment) do |analysis|
        analysis.x_axis  = :bundles
	analysis.configure_data :combine => :routing, :x_axis => :bundles do |row, x, network_model, traffic_model|
	  unless x.nil?
	    row.value     "delay", x + 10
	    row.std_error "delay", 10
	  end
	end
        analysis.plot :x_axis => :bundles, :y_axis => ["delay"] #do |dataset|
        #end
      end
      assert_same_elements [File.join(@dir, 'scen1delay.svg'), File.join(@dir, 'scen2delay.svg')], Dir.glob("#{@dir}/*.svg")
    end

  end

end
