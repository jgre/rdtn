$:.unshift File.join(File.dirname(__FILE__), '../../sim')

require 'rubygems'
require 'test/unit'
require 'shoulda'
require 'logentry'

class LogEntryTest < Test::Unit::TestCase

  should 'store time, event id, and two node ids' do
    entry = Sim::LogEntry.new(1, :testEvent, 3, 2)
    assert_equal 1, entry.time
    assert_equal :testEvent, entry.eventId
    assert_equal 3, entry.nodeId1
    assert_equal 2, entry.nodeId2
  end

  should 'make the second node id optional' do
    entry = Sim::LogEntry.new(1, :testEvent, 3)
    assert !entry.nodeId2
  end

  should 'store additional parameters by name' do
    entry = Sim::LogEntry.new(1, :testEvent, 3, 2, :test_val=>'bla', :xyz=>42)
    assert_equal 'bla', entry.test_val
    assert_equal 42, entry.xyz
  end

end
