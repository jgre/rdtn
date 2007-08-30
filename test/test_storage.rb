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
require "storage"
require "bundle"


class TestStorage < Test::Unit::TestCase

  def setup
    EventDispatcher.instance.clear
    @store = Storage.new("store")
  end

  def teardown
    begin
      File.delete("store")
    rescue
    end
  end

  def test_storage1
    
    0.upto(99) do |i|
      b=Bundling::Bundle.new(i.to_s)
      @store.storeBundle(b)
    end

    @store.save

    @store.clear

    newstore=Storage.new("store")
    newstore.load


    idlist=newstore.listBundles

    0.upto(99) do |i|
      b=newstore.getBundle(idlist[i])
      assert_equal(i.to_s, b.payload)
    end
    
  end


  def test_storage2
    
    0.upto(99) do |i|
      b=Bundling::Bundle.new(i.to_s)
      b.destEid=EID.new("dtn://test/" + i.to_s)
      @store.storeBundle(b)
    end

    @store.save
    @store.clear

    newstore=Storage.new("store")
    newstore.load

    blist=newstore.getBundlesMatching() do |bundleInfo|
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



end
