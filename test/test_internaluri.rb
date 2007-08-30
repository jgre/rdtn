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
require "internaluri"
require "bundle"

class MockStore
  attr_reader :deleted
  @@bundle = Bundling::Bundle.new("test", "dtn:dest")

  def bundle
    return @@bundle
  end

  def getBundle(id)
    if id == @@bundle.bundleId
      return @@bundle
    else
      return nil
    end
  end

  def getBundlesMatchingDest(dest)
    if dest == @@bundle.destEid
      return [@@bundle]
    else
      return []
    end
  end

  def deleteBundle(id)
    if id == @@bundle.bundleId
      @deleted = true
    end
  end
end

class MockAppProxy
  attr_accessor :uri

  def sendEvent(uri, *args)
    @uri = uri
  end
end

class TestIURI < Test::Unit::TestCase

  def test_query_bundle
    store = MockStore.new
    ri = RequestInfo.new(QUERY, self)
    uri = "rdtn:bundles/#{store.bundle.bundleId}/"

    typeCode, hash = PatternReg.resolve(uri, ri, store)
    assert_equal(RESOLVE, typeCode)
    assert_equal({:uri => uri, :bundle => store.bundle}, hash)

    methUri = uri + "destEid/"
    typeCode, hash = PatternReg.resolve(methUri, ri, store)
    assert_equal(RESOLVE, typeCode)
    assert_equal({:uri => methUri, :bundleMeth => store.bundle.destEid}, hash)
  end

  def test_post_bundle
    uri = "rdtn:bundles/"
    ri = RequestInfo.new(POST, self)
    bundle = Bundling::Bundle.new("test", "dtn:dest")
    event = false

    EventDispatcher.instance.subscribe(:bundleParsed) do |b, cl|
      assert_equal(bundle, b)
      event = true
    end

    typeCode, hash = PatternReg.resolve(uri, ri, nil, {:bundle => bundle})
    assert_equal(STATUS, typeCode)
    assert_equal({:uri => uri, :status => 200, :message => "OK"}, hash)
    assert(event)
  end

  def test_post_route
    uri = "rdtn:routetab/"
    ri = RequestInfo.new(POST, self)
    dest = "dtn://test.dtn/.*"
    event = false
    
    EventDispatcher.instance.subscribe(:routeAvailable) do |rentry|
      assert_equal(self, rentry.link)
      assert_equal(dest, rentry.destination.source)
      event = true
    end

    typeCode, hash = PatternReg.resolve(uri, ri, nil, {:target => dest})
    						       
    assert_equal(STATUS, typeCode)
    assert_equal({:uri => uri, :status => 200, :message => "OK"}, hash)
    assert(event)
  end

  def test_delete_route
    uri = "rdtn:routetab/"
    ri = RequestInfo.new(DELETE, self)
    dest = "dtn://test.dtn/.*"
    event = false
    
    EventDispatcher.instance.subscribe(:routeLost) do |link, target|
      assert_equal(self, link)
      assert_equal(dest, target.to_s)
      event = true
    end

    typeCode, hash = PatternReg.resolve(uri, ri, nil, {:target => dest,
    						       :link   => self})
    assert_equal(STATUS, typeCode)
    assert_equal({:uri => uri, :status => 200, :message => "OK"}, hash)
    assert(event)
  end

  def test_event
    uri = "rdtn:events/linkCreated/"
    map = MockAppProxy.new
    ri = RequestInfo.new(POST, map)

    typeCode, hash = PatternReg.resolve(uri, ri, nil, {})
    assert_equal(STATUS, typeCode)
    assert_equal({:uri => uri, :status => 200, :message => "OK"}, hash)

    EventDispatcher.instance.dispatch(:linkCreated, self)

    assert_equal(uri, map.uri)
  end

  def test_search
    uri = "rdtn:bundles/"
    ri = RequestInfo.new(QUERY, self)
    store = MockStore.new
    dest = store.bundle.destEid

    typeCode, hash = PatternReg.resolve(uri, ri, store, {:destEid => dest})
    assert_equal(RESOLVE, typeCode)
    assert_equal({:uri => uri, :bundle => store.bundle}, hash)

    typeCode, hash = PatternReg.resolve(uri, ri, store, {:destEid => "hugo"})
    assert_equal(STATUS, typeCode)
    assert_equal({:uri => uri, :status=> 404, :message => "Not Found"}, hash)
  end

  def test_delete
    ri = RequestInfo.new(DELETE, self)
    store = MockStore.new
    uri = "rdtn:bundles/#{store.bundle.bundleId}/"

    typeCode, hash = PatternReg.resolve(uri, ri, store)
    assert_equal(STATUS, typeCode)
    assert_equal({:uri => uri, :status => 200, :message => "OK"}, hash)
    assert(store.deleted)

  end

  def teardown
    EventDispatcher.instance.clear
  end

end
