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

      @datasets = Analysis.analyze(@variants, :dataset => :a, :x_axis => :b) do |dataset, x, network_model, traffic_model|
	[network_model, traffic_model]
      end
    end

    should 'produce datasets identified by variable :a that map variable :b to the network model and the traffic model' do
      expectation = [
	Struct::Dataset.new({:a => 1}, [[4, @variants[0][1], @variants[0][2]],
			                [5, @variants[2][1], @variants[2][2]]]),
	Struct::Dataset.new({:a => 2}, [[4, @variants[1][1], @variants[1][2]],
			                [5, @variants[3][1], @variants[3][2]]])
      ]
      assert_equal expectation, @datasets
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

  context 'Putting Struct::Dataset into a string' do

    setup do
      @ds = Struct::Dataset.new({:a => 1},[[4, 1000, 1200],
				           [5, 500,   900]])
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

end
