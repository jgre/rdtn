$: << File.join(File.dirname(__FILE__), '..', 'lib')

require 'test/unit'
require 'rubygems'
require 'shoulda'
require 'pubsub'
require 'daemon'

class TestPubSub < Test::Unit::TestCase

  context 'PubSub on a single node' do

    setup do
      @daemon = RdtnDaemon::Daemon.new("dtn://receiver.dtn/")
      @store  = @daemon.config.store
      @daemon.router(:epidemic)
      @uri    = "pubsub://test/collection"
    end

    should 'deliver published data to a subscriber' do
      received = nil
      data     = "test data"
      PubSub.publish(@daemon, @uri, data)
      PubSub.subscribe(@daemon, @uri) {|content| received = content}
      assert_equal data, received
    end

    should 'deliver published data to previously existing subscribers' do
      received = nil
      data     = "test data"
      PubSub.subscribe(@daemon, @uri) {|content| received = content}
      PubSub.publish(@daemon, @uri, data)
      assert_equal data, received
    end

    should 'deliver updated of published data to a subscriber' do
      received = nil
      rev1     = "initial revision"
      rev2     = "updated revision"
      PubSub.subscribe(@daemon, @uri) {|content| received = content}
      PubSub.publish(@daemon, @uri, rev1)
      PubSub.publish(@daemon, @uri, rev2)
      assert_equal rev2, received
    end

    should 'not deliver data that was deleted' do
      received = nil
      data     = "test data"
      PubSub.publish(@daemon, @uri, data)
      PubSub.delete(@daemon, @uri)
      PubSub.subscribe(@daemon, @uri) {|content| received = content}
      assert_nil received
    end

    should 'not deliver updates after unsubscribing' do
      received = nil
      data     = "test data"
      PubSub.subscribe(@daemon, @uri) {|content| received = content}
      PubSub.unsubscribe(@daemon, @uri)
      PubSub.publish(@daemon, @uri, data)
      assert_nil received
    end
    
  end
  
end
