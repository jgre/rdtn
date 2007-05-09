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
#
# $Id: fileup.py 8 2006-12-22 20:00:21Z jgre $

$:.unshift File.join(File.dirname(__FILE__), "..", "lib")

require "test/unit"
require "storage"
require "rdtnlog"
require "bundle"


class TestAppLib < Test::Unit::TestCase


  def test_storage1
    log=RdtnLogger.instance()
    log.level=Logger::DEBUG
    
    store = Storage.new
    
    0.upto(99) do |i|
      b=Bundling::Bundle.new(i.to_s)
      store.storeBundle(b)
    end

    store.save("/tmp/bundlestore")

    newstore=Storage.new
    newstore.load("/tmp/bundlestore")


    idlist=newstore.listBundles

    0.upto(99) do |i|
      b=newstore.getBundle(idlist[i])
      assert_equal(i.to_s, b.payload)
    end
    
  end


  def test_storage2
    log=RdtnLogger.instance()
    log.level=Logger::DEBUG
    
    store = Storage.new

    log.debug("creating bundles")
    
    0.upto(99) do |i|
      b=Bundling::Bundle.new(i.to_s)
      b.dest_eid="dtn://test/" + i.to_s
      store.storeBundle(b)
    end

    store.save("/tmp/bundlestore")

    log.debug("loading store")
    newstore=Storage.new
    newstore.load("/tmp/bundlestore")

    log.debug("trying to match 1 bundle")
    blist=newstore.getBundlesMatching() do |bundleInfo|
#      log.debug("trying to match"  + bundleInfo.dest_eid)
      bundleInfo.dest_eid =~ /dtn:\/\/test\/.*/
      bundleInfo.dest_eid =~ /.*test\/99/
    end

    assert_equal(blist.length(),1)


    log.debug("trying to match all bundles")
    blist=newstore.getBundlesMatching() do |bundleInfo|
#      log.debug("trying to match"  + bundleInfo.dest_eid)
      bundleInfo.dest_eid =~ /dtn:\/\/test\/.*/
    end

    assert_equal(blist.length(),100)


    log.debug("trying to match 1 bundle")
    blist=newstore.getBundlesMatchingDest("dtn://test/0") 
    assert_equal(blist.length(),1)


  end



end
