$:.unshift File.join(File.dirname(__FILE__), '../../sim/stats')
$:.unshift File.join(File.dirname(__FILE__), '../../sim')

require 'rubygems'
require 'test/unit'
require 'shoulda'
require 'eventqueue'

class EventQueueTest < Test::Unit::TestCase

  def setup
    @eq = Sim::EventQueue.new

    # Get 100000 random integers between 0 and 100000 and a random float between
    # 0 and 1
    @data = (1..100000).map {|i| rand(100000) + rand} 

    @data.each {|time| @eq.addEventSorted(time, 1, 2, :simConnection)}
  end

  should 'push events to the end' do
    eq = Sim::EventQueue.new
    1000.times {|time| eq.addEvent(time, 1, 2, :simConnection)}
    assert_equal 1000, eq.length
  end

  should 'be sorted' do
    assert_equal @data.sort, @eq.map {|ev| ev.time}
  end

  should 'be accessible during traversal' do
    @eq.each do |ev|
      unless @data.length > 100
	val = ev.time + rand(1000000)
	@eq.addEventSorted(val, 1, 2, :simConnection)
	@data << val
      end
    end
    assert_equal @data.sort, @eq.map {|ev| ev.time}
  end

end
