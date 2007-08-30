#  Copyright (C) 2007 Janico Greifenberg <jgre@jgre.org> and 
#  Dirk Kutscher <dku@tzi.org>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

$:.unshift File.join(File.dirname(__FILE__), "..", "lib")

require "test/unit"
require "subscriptionhandler"
require "bundle"

class MockLink < Link
  attr_accessor :remoteEid, :bundle, :bundles

  def initialize
    @bundles = []
    super
  end

  def sendBundle(bundle)
    @bundle = bundle
    @bundles.push(bundle)
  end

  def close
  end

  def received?(bundle)
    @bundles.any? {|b| b.to_s == bundle.to_s}
  end

end

class MockClient
  attr_accessor :uri, :subscriptions

  def initialize
    @subscriptions = []
  end

  def register(eid, &handler)
    @uri = eid
    @handler = handler
  end

  def addRoute(uri, target)
    @subscriptions.push(uri)
  end

  def sendBundle(bundle)
    bundle.incomingLink = self
    @handler.call(bundle)
  end

  def deleteBundle(id)
  end
end

class MockContactManager

  def initialize(link)
    @link = link
  end

  def findLinkByName(name)
    return @link
  end
end

class TestSubscriptionHandler < Test::Unit::TestCase

  Uris = ["dtn://test1/", "dtn://test2", "http://tzi.org"]

  def setup
    @client = MockClient.new
    @link = MockLink.new
    RdtnConfig::Settings.instance.store = Storage.new("store")
    @shandler = SubscriptionHandler.new(@client, 2)
    Uris.each {|uri| @shandler.subscribe(uri, MockClient.new)}
  end

  def teardown
    RdtnConfig::Settings.instance.store.clear
    begin
      File.delete("store")
    rescue
    end
    EventDispatcher.instance.clear
  end

  def test_subscribe
    # Add a duplicate
    @shandler.subscribe(Uris[0], MockClient.new)
    assert_equal(Uris, @shandler.subscribedUris)
  end

  def test_subscription_bundles
    EventDispatcher.instance.dispatch(:linkCreated, @link)
    client2 = MockClient.new
    shandler2 = SubscriptionHandler.new(client2)

    sleep(1)
    # Feed the subscription bundle of the first handler to the client of the
    # second one.
    client2.sendBundle(@shandler.generateSubscriptionBundle)
    assert_equal(Uris, shandler2.subscribedUris)
    assert_equal(Uris, client2.subscriptions)
  end

  def test_check
    shortUri = "dtn://shortlived"
    # Add a subscription that expires soon
    @shandler.subscribe(shortUri, MockClient.new, Time.now, Time.now + 1)
    assert_equal(Uris + [shortUri], @shandler.subscribedUris)
    sleep(3)
    assert_equal(Uris, @shandler.subscribedUris)

  end

end
