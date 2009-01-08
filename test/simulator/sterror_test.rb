$:.unshift File.join(File.dirname(__FILE__), '../../sim/stats')
$:.unshift File.join(File.dirname(__FILE__), '../../sim')

require 'rubygems'
require 'test/unit'
require 'shoulda'
require 'statistics'

class StatisticsTest < Test::Unit::TestCase
  
  def setup
    # Data taken from http://www.ncsu.edu/labwrite/res/gt/gt-stat-home.html
    @columns = [
      [1, 1, 2, 1, 2],
      [52, 58, 82, 35, 84],
      [48, 66, 74, 86, 78],
      [74, 82, 72, 80, 79]
    ]
  end

  should 'Calculate the mean correctly' do
    assert_equal [1.4, 62.2, 70.4, 77.4], @columns.map {|col| col.mean}
  end

  should 'Calculate the standard deviation correctly' do
    assert_equal [0.5, 20.8, 14.4, 4.2], @columns.map {|col| (col.stdev*10).round/10.0}
  end

  should 'Calculate the standard error correctly' do
    assert_equal [0.2, 9.3, 6.5, 1.9], @columns.map {|col| (col.sterror*10).round/10.0}
  end

end
