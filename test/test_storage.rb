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
require "rubygems"
require "shoulda"
require "storage"
require "bundle"


class TestStorage < Test::Unit::TestCase

  def setup
    @evDis  = EventDispatcher.new
    @config = RdtnConfig.new
    @store  = Storage.new(@config, @evDis, nil, "store")
  end

  def teardown
    begin
      File.delete("store")
    rescue
    end
  end

  should 'register itself as ":store" component' do
    assert_equal @store, @config.component(:store)
  end

  def test_storage1
    pl = "test"
    idlist = []

    0.upto(99) do |i|
      b=Bundling::Bundle.new(nil, "dtn://test/")
      idlist.push(b.bundleId)
      b.payload = pl * i
      assert_equal(pl.length * i, b.payload.length)
      @store.storeBundle(b)
    end

    @store.save

    @store.clear

    newstore=Storage.new(@config, @evDis, nil, "store")
    newstore.load

    idlist.each_with_index do |id, i|
      b=newstore.getBundle(id)
      assert_equal(pl.length * i, b.payload.length)
    end
    
  end


  def test_storage_queries
    
    0.upto(99) do |i|
      b=Bundling::Bundle.new(i.to_s)
      b.destEid = "dtn://test/" + i.to_s
      @store.storeBundle(b)
    end

    @store.save
    @store.clear

    newstore=Storage.new(@config, @evDis, nil, "store")
    newstore.load

    blist=newstore.getBundlesMatching do |bundleInfo|
      bundleInfo.destEid.to_s =~ /dtn:\/\/test\/.*/
      bundleInfo.destEid.to_s =~ /.*test\/99/
    end

    assert_equal(blist.length(),1)

    blist=newstore.getBundlesMatching() do |bundleInfo|
      bundleInfo.destEid.to_s =~ /dtn:\/\/test\/.*/
    end

    assert_equal(blist.length(),100)

    blist=newstore.getBundlesMatchingDest("dtn://test/0") 
    assert_equal(blist.length(),1)

  end

  def test_limits
    @store = Storage.new(@config, @evDis, 100)
    b = Bundling::Bundle.new(nil, "dtn://test/")
    id1 = b.bundleId
    b.payload = "x" * 50
    sleep(1)
    b2 = Bundling::Bundle.new(nil, "dtn://test/")
    b2.payload = "x" * 51
    id2 = b2.bundleId
    @store.storeBundle(b2)
    @store.storeBundle(b)

    ret1 = @store.getBundle(id1)
    ret2 = @store.getBundle(id2)
    assert_equal(51, ret2.payload.length)
    assert_nil(ret1)
  end

  def test_duplicates
    b1 = Bundling::Bundle.new("test", "dtn://test.dest", "dtn://test.src")
    b1.forwardLog.addEntry(:forward, :inflight, "dtn://neighbor1")
    @store.storeBundle(b1)
    b2 = b1.deepCopy
    b2.forwardLog.addEntry(:incoming, :transmitted, "dtn://neighbor2")
    res1 = @store.getBundle(b1.bundleId)
    assert_equal("dtn://neighbor1", res1.forwardLog.getLatestEntry.neighbor)
    assert_raise(BundleAlreadyStored) {@store.storeBundle(b2)}
    res2 = @store.getBundle(b1.bundleId)
    assert_equal("dtn://neighbor2", res1.forwardLog.getLatestEntry.neighbor)
  end

end
