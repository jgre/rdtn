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


  context 'Plotting the results for an experiment with two variables' do

    setup do
      @variants = [
	[{:a => 1, :b => 4}, NetworkModel.new, TrafficModel.new(0)],
	[{:a => 2, :b => 4}, NetworkModel.new, TrafficModel.new(0)],
	[{:a => 1, :b => 5}, NetworkModel.new, TrafficModel.new(0)],
	[{:a => 2, :b => 5}, NetworkModel.new, TrafficModel.new(0)]
      ]
      @analysis = Analysis.new(@variants)

      @datasets = @analysis.plot_results(:dataset => :a, :x_axis => :b) do |dataset, x, network_model, traffic_model|
	[network_model, traffic_model]
      end
    end

    should 'produce two datasets' do
      assert_equal 2, @datasets.length
      @datasets.each {|ds| assert_kind_of Struct::Dataset, ds}
    end

    should 'produce datasets identified by values for variable :a' do
      assert_equal [1, 2], @datasets.map {|ds| ds.dataset[:a]}
    end

    should 'contain the :b variable as the first entry in all value rows' do
      @datasets.each do |ds|
	assert_equal [4, 5], ds.values.map {|row| row[0]}
      end
    end

    should 'contain the network and traffic models as y values' do
      assert_same_elements @variants.map{|v| v[1..-1]},
       	@datasets.inject([]) {|memo, ds| memo + ds.values.map {|v| v[1..-1]}}
    end

  end

end
