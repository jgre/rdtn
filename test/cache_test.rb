$: << File.join(File.dirname(__FILE__), '..', 'lib')
$:.unshift File.join(File.dirname(__FILE__), '../sim/maidenvoyage')

require 'test/unit'
require 'rubygems'
require 'shoulda'
require 'cache'
require 'pubsub'
require 'daemon'
require 'maidenvoyage'
require 'graph'

class TestCache < Test::Unit::TestCase

  simulation_context 'The caches on two connected nodes' do

    uri  = "http://example.com/feed/"
    
    prepare do
      g = Sim::Graph.new
      g.edge :sub1 => :source
      sim.events = g.events

      data = "test data"
      sim.node(:source).register("dtn:internet-gw/") {}
      sim.at(1)  {PubSub.subscribe(sim.node(:sub1), uri) {}; false}
      sim.at(2)  {PubSub.publish(sim.node(:source), uri, data, :lifetime => 50); false}
      sim.at(100){PubSub.publish(sim.node(:source), uri, data); false}
    end

    should 'should evict the subscriber\'s cache after 50 seconds' do
      assert_same_elements [9, 9, 0, 0], traffic_model.cacheUse(25, :sub1)
    end
    
  end

  context 'Caches with a size limit' do

    setup do
      @daemon = RdtnDaemon::Daemon.new("dtn://test/")
      @cache  = @daemon.config.cache
      @cache.limit = 10
    end

    should 'not exceed the limit' do
      uri1 = 'http://example.com/1'
      uri2 = 'http://example.com/2'
      @cache.addContent(uri1, 'a'*10, 0)
      @cache.addContent(uri2, 'a'*10, 0)
      assert_not_nil @cache[uri2]
      assert_nil @cache[uri1]
    end

    context 'and LRU as replacement policy' do

      setup do
        @cache.replacementPolicy = :lru
      end

      should 'remove the least recently used item when the limit is exceeded' do
        uri1 = 'http://example.com/1'
        uri2 = 'http://example.com/2'
        uri3 = 'http://example.com/3'
        @cache.addContent(uri1, 'a'*5, 0)
        @cache.addContent(uri2, 'b'*5, 0)
        @cache.contentUsed(uri1)
        @cache.contentUsed(uri1)
        @cache.contentUsed(uri2)
        @cache.addContent(uri3, 'c'*5, 0)
        assert_not_nil @cache[uri2]
        assert_not_nil @cache[uri3]
        assert_nil @cache[uri1]
      end
      
    end

    context 'and Popularity replacement policy' do

      setup do
        @cache.replacementPolicy = :popularity
      end

      should 'remove the least popular item when the limit is exceeded' do
        uri1 = 'http://example.com/1'
        uri2 = 'http://example.com/2'
        uri3 = 'http://example.com/3'
        @cache.addContent(uri1, 'a'*5, 0)
        @cache.addContent(uri2, 'b'*5, 0)
        @cache.contentUsed(uri1)
        @cache.contentUsed(uri1)
        @cache.contentUsed(uri2)
        @cache.addContent(uri3, 'c'*5, 0)
        assert_not_nil @cache[uri1]
        assert_not_nil @cache[uri3]
        assert_nil @cache[uri2]
      end
      
    end
    
  end

  should 'remove old revisions when #compact is called' do
    daemon = RdtnDaemon::Daemon.new("dtn://test/")
    cache  = daemon.config.cache
    uri    = 'http://example.com/1'
    cache.addContent(uri, 'a', 0)
    cache.addContent(uri, 'a', 1)
    cache.addContent(uri, 'a', 2)
    assert_equal 3, cache.size
    cache.compact
    assert_equal 1, cache.size
    assert_equal 2, cache.currentRevision(uri)
  end

end
