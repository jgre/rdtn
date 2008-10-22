$:.unshift File.join(File.dirname(__FILE__), '../../sim/stats')
$:.unshift File.join(File.dirname(__FILE__), '../../sim')

require 'rubygems'
require 'test/unit'
require 'shoulda'
require 'trafficmodel'
require 'networkmodel'
require 'logentry'

class QuotaEvictionTest < Test::Unit::TestCase

  context 'TrafficModel with quota-based eviction' do

    setup do
      @t0   = Time.now
      @tm = TrafficModel.new(@t0)
      @tm.event(Sim::LogEntry.new(1, :registered, 2, nil, :eid=>'dtn://group/'))
      15.times do |i|
	b = Bundling::Bundle.new(i.to_s, 'dtn://group/', 'dtn://kasuari1/',
				 :multicast => true, :lifetime => nil)
	@tm.event(Sim::LogEntry.new(0, :bundleCreated, 1, nil, 
				    :bundle => b))
      end
    end

    should 'count only bundles as expected that fit into the quota' do
      assert_equal 10, @tm.numberOfExpectedBundles(:quota => 10)
    end

  end

end
