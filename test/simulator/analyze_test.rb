$:.unshift File.join(File.dirname(__FILE__), '../../sim/stats')
$:.unshift File.join(File.dirname(__FILE__), '../../sim')

require 'rubygems'
require 'test/unit'
require 'shoulda'
require 'trafficmodel'
require 'networkmodel'
require 'logentry'
require 'analysis'
require 'mocha'

class AnalyzeTest < Test::Unit::TestCase

  def setup
    @variants = [
      [{:routing => :epidemic, :size => 10}, nil, stub(:averageDelay => 3600, :numberOfDeliveredBundles => 42, :delays => [1000, 2000, 600])],
      [{:routing => :epidemic, :size => 20}, nil, stub(:averageDelay => 3700, :numberOfDeliveredBundles => 62, :delays => [1500, 1000, 500, 700])],
      [{:routing => :dpsp, :size => 10}, nil, stub(:averageDelay => 3602, :numberOfDeliveredBundles => 2, :delays => [2, 600, 1500, 1500])],
      [{:routing => :dpsp, :size => 20}, nil, stub(:averageDelay => 2600, :numberOfDeliveredBundles => 77, :delays => [1600, 1000])]
    ]
  end

  should 'preprocess into a list of hashes' do
    results = Analysis.preprocess(@variants)
    assert_equal 4, results.length
    results.each {|res| assert_kind_of Hash, res}
  end

  should 'call a block from preprocess' do
    results = Analysis.preprocess(@variants) do |variant, net, traffic|
      {:meanDelay => traffic.averageDelay, :delivered => traffic.numberOfDeliveredBundles}
    end
    expected = [
      {:routing => :epidemic, :size => 10, :meanDelay => 3600, :delivered =>42},
      {:routing => :epidemic, :size => 20, :meanDelay => 3700, :delivered =>62},
      {:routing => :dpsp, :size => 10, :meanDelay => 3602, :delivered => 2},
      {:routing => :dpsp, :size => 20, :meanDelay => 2600, :delivered => 77}
    ]
    assert_same_elements expected, results
  end

  should 'allow multiple values to be returned for one variant' do
    results = Analysis.preprocess(@variants) do |variant, net, traffic|
      ret = []
      ret << {:meanDelay => traffic.averageDelay, :delivered => traffic.numberOfDeliveredBundles}
      traffic.delays.each_with_index do |delay, i|
	ret << {:delayIndex => i, :delay => delay}
      end
      ret
    end
    expected = [
      {:routing => :epidemic, :size => 10, :meanDelay => 3600, :delivered =>42},
      {:routing => :epidemic, :size => 20, :meanDelay => 3700, :delivered =>62},
      {:routing => :dpsp, :size => 10, :meanDelay => 3602, :delivered => 2},
      {:routing => :dpsp, :size => 20, :meanDelay => 2600, :delivered => 77},

      {:routing => :epidemic, :size => 10, :delayIndex => 0, :delay => 1000},
      {:routing => :epidemic, :size => 10, :delayIndex => 1, :delay => 2000},
      {:routing => :epidemic, :size => 10, :delayIndex => 2, :delay => 600},
      {:routing => :epidemic, :size => 20, :delayIndex => 0, :delay => 1500},
      {:routing => :epidemic, :size => 20, :delayIndex => 1, :delay => 1000},
      {:routing => :epidemic, :size => 20, :delayIndex => 2, :delay => 500},
      {:routing => :epidemic, :size => 20, :delayIndex => 3, :delay => 700},
      {:routing => :dpsp, :size => 10, :delayIndex => 0, :delay => 2},
      {:routing => :dpsp, :size => 10, :delayIndex => 1, :delay => 600},
      {:routing => :dpsp, :size => 10, :delayIndex => 2, :delay => 1500},
      {:routing => :dpsp, :size => 10, :delayIndex => 3, :delay => 1500},
      {:routing => :dpsp, :size => 20, :delayIndex => 0, :delay => 1600},
      {:routing => :dpsp, :size => 20, :delayIndex => 1, :delay => 1000},
    ]
    assert_same_elements expected, results
  end

  should 'aggregate the data according to given x and y axes' do
    processed = Analysis.preprocess(@variants) do |variant, net, traffic|
      {:meanDelay => traffic.averageDelay, :delivered => traffic.numberOfDeliveredBundles}
    end

    results = Analysis.aggregate processed, :x_axis => :size, :y_axis => :meanDelay, :enumerate => [:routing]

    expected = {
      {:routing => :epidemic} => {{} => {:size => [10, 20], :meanDelay => [3600, 3700]}},
      {:routing => :dpsp} => {{} => {:size => [10, 20], :meanDelay => [3602, 2600]}}
    }
    assert_equal expected, results
  end

  should 'add error values when aggregating data' do
    processed = Analysis.preprocess(@variants) do |variant, net, traffic|
      {:meanDelay => traffic.averageDelay, "meanDelay_error" => 0.5}
    end

    results = Analysis.aggregate processed, :x_axis => :size, :y_axis => :meanDelay, :enumerate => [:routing]

    expected = {
      {:routing => :epidemic} => {{} => {:size => [10, 20], :meanDelay => [3600, 3700], "meanDelay_error" => [0.5, 0.5]}},
      {:routing => :dpsp} => {{} => {:size => [10, 20], :meanDelay => [3602, 2600], "meanDelay_error" => [0.5, 0.5]}}
    }
    assert_equal expected, results
  end

  should 'observe combinations when aggregating data' do
    variants = [
      [{:routing => :epidemic, :size => 10, :lifetime => 1800}, nil, stub(:numberOfDeliveredBundles => 42)],
      [{:routing => :epidemic, :size => 20, :lifetime => 1800}, nil, stub(:numberOfDeliveredBundles => 62)],
      [{:routing => :epidemic, :size => 10, :lifetime => 3600}, nil, stub(:numberOfDeliveredBundles => 43)],
      [{:routing => :epidemic, :size => 20, :lifetime => 3600}, nil, stub(:numberOfDeliveredBundles => 63)],
      [{:routing => :dpsp, :size => 10, :lifetime => 1800}, nil, stub(:numberOfDeliveredBundles => 2)],
      [{:routing => :dpsp, :size => 20, :lifetime => 1800}, nil, stub(:numberOfDeliveredBundles => 77)],
      [{:routing => :dpsp, :size => 10, :lifetime => 3600}, nil, stub(:numberOfDeliveredBundles => 3)],
      [{:routing => :dpsp, :size => 20, :lifetime => 3600}, nil, stub(:numberOfDeliveredBundles => 73)]
    ]
    processed = Analysis.preprocess(variants) do |variant, net, traffic|
      {:delivered => traffic.numberOfDeliveredBundles}
    end

    results = Analysis.aggregate processed, :x_axis => :size, :y_axis => :delivered, :combine => :routing, :enumerate => [:lifetime]

    expected = {
      {:lifetime => 1800} => {
        {:routing => :epidemic} => {:size => [10, 20], :delivered => [42, 62]},
        {:routing => :dpsp} => {:size => [10, 20], :delivered => [2, 77]}
      },
      {:lifetime => 3600} => {
        {:routing => :epidemic} => {:size => [10, 20], :delivered => [43, 63]},
        {:routing => :dpsp} => {:size => [10, 20], :delivered => [3, 73]}
      }
    }
    assert_equal expected, results
  end

  should 'plot the aggregated data' do
    processed = Analysis.preprocess(@variants) do |variant, net, traffic|
      {:meanDelay => traffic.averageDelay, :delivered => traffic.numberOfDeliveredBundles}
    end

    results = Analysis.aggregate processed, :x_axis => :size, :y_axis => :meanDelay, :enumerate => [:routing]

    dir = "tmp/"
    Analysis.plot results, :x_axis => :size, :y_axis => :meanDelay, :dir => dir
    assert File.exist?(File.join(dir, "routing=>epidemic[meanDelay].svg"))
    assert File.exist?(File.join(dir, "routing=>dpsp[meanDelay].svg"))
  end

  context 'plotting the aggregated data with combinations' do

    setup do
      processed = Analysis.preprocess(@variants) do |variant, net, traffic|
	{:meanDelay => traffic.averageDelay, :delivered => traffic.numberOfDeliveredBundles}
      end
      @results = Analysis.aggregate processed, :x_axis => :size, :y_axis => :meanDelay, :combine => :routing
      @dir = "tmp/"
      FileUtils.rm_rf @dir
    end

    teardown {FileUtils.rm_rf @dir}

    should 'plot two datasets' do
      Gnuplot::Plot.any_instance.expects(:data).times(2).returns([])
      Analysis.plot @results, :x_axis => :size, :y_axis => :meanDelay, :dir => @dir
    end

    should 'create only one file' do
      Analysis.plot @results, :x_axis => :size, :y_axis => :meanDelay, :dir => @dir
      assert_same_elements [File.join(@dir, "[meanDelay].svg")], Dir.glob("#{@dir}*")
    end

    should 'print custom labels on the graph' do
      block_called = false
      Analysis.plot(@results, :x_axis => :size, :y_axis => :meanDelay, :dir => @dir) do |plot|
	plot.title "mytitle"
	plot.xlabel "myx"
	plot.ylabel "myy"
	block_called = true
      end
      assert block_called
    end

    should 'use a translation hash to print labels' do
      Gnuplot::DataSet.any_instance.expects(:title=).at_least_once.with :Routing
      translate = {:dpsp => :Routing, :epidemic => :Routing}
      Analysis.plot(@results, :x_axis => :size, :y_axis => :meanDelay, :dir => @dir, :translate => translate)
    end

  end

  should 'set common minima and maxima for datasets' do
    Gnuplot::Plot.any_instance.expects(:yrange).at_least_once.with("[2340.0:4070.0]")
    processed = Analysis.preprocess(@variants) do |variant, net, traffic|
      {:meanDelay => traffic.averageDelay, :delivered => traffic.numberOfDeliveredBundles}
    end

    results = Analysis.aggregate processed, :x_axis => :size, :y_axis => :meanDelay, :enumerate => [:routing]

    dir = "tmp/"
    Analysis.plot results, :x_axis => :size, :y_axis => :meanDelay, :dir => dir
    FileUtils.rm_rf dir
  end

  should 'plot error bars' do
    Gnuplot::DataSet.any_instance.expects(:with=).at_least_once.with "yerrorlines"
    processed = Analysis.preprocess(@variants) do |variant, net, traffic|
      {:meanDelay => traffic.averageDelay, "meanDelay_error" => 50}
    end

    results = Analysis.aggregate processed, :x_axis => :size, :y_axis => :meanDelay, :enumerate => [:routing]

    dir = "tmp/"
    Analysis.plot results, :x_axis => :size, :y_axis => :meanDelay, :dir => dir
    FileUtils.rm_rf dir
  end

end
