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
# $Id$

$:.unshift File.join(File.dirname(__FILE__), "..", "lib")

require "test/unit"
require "storage"
require "rdtnlog"
require "bundle"
require "fileutils"


class Test_storage_perBundle < Test::Unit::TestCase

  def test_create_filename
    bundle1 = Bundling::Bundle.new("payload", "dtn://test", "localhost:src")
    store_name1 = Storage_perBundle::create_filename(bundle1)
    extname = File.extname(store_name1) 

    assert_equal(".pstore", extname)
   
    fnmatch = File.fnmatch("s*d*t*f*", store_name1)
    assert(fnmatch)

    bundle2 = Bundling::Bundle.new("payload", "dtn://test", "LOCALHOST:src")
    store_name2 = Storage_perBundle::create_filename(bundle2)
      
    assert_not_equal(store_name1, store_name2)
  end

  def test_eql?
    bundle1 = Bundling::Bundle.new(payload="bundle stored",
				   destEid="dtn://test", srcEid="localhost:src")
    bi = BundleInfo.new(bundle1)
    bi_new = BundleInfo.new(bundle1)
    assert(bi.eql?(bi_new))
    assert_equal(bi.hash, bi_new.hash)

    bundle2 = Bundling::Bundle.new(payload="bundle",
				   destEid="dtn://test", srcEid="localhost:src")
    bi_new2 = BundleInfo.new(bundle2)
    assert(!bi.eql?(bi_new2))
    assert(bi.hash != bi_new2.hash)

    bundle3 = Bundling::Bundle.new(payload="bundle stored",
				   destEid="dtn://t", srcEid="localhost:src")
    bi_new3 = BundleInfo.new(bundle3)
    assert(!bi.eql?(bi_new3))
    assert(bi.hash != bi_new3.hash)

    bundle4 = Bundling::Bundle.new(payload="bundle stored",
				   destEid="dtn://test", srcEid="localhost:s")
    bi_new4 = BundleInfo.new(bundle4)
    assert(!bi.eql?(bi_new4))
    assert(bi.hash != bi_new4.hash)
  end

=begin
  def eventListener(bundle)
    @parsedBundle = bundle
  end

  def test_eventDispatcher
    @parsedBundle = nil
    EventDispatcher.instance.subscribe(:bundleParsed) do |bundle|
      self.eventListener(bundle)
    end
    EventDispatcher.instance.dispatch(:bundleParsed, "bundle")
   
    assert_equal("bundle", @parsedBundle)
  end
=end

  #test for 'save(bundle), without event dispatcher'
  def test_save
    log = RdtnLogger.instance()
    log.level = Logger::DEBUG
    
    bundle = Bundling::Bundle.new(payload="bundle stored",
				  destEid="dtn://test", srcEid="localhost:src")
    RDTNConfig.instance.storageDir = "/tmp/rdtnTest"
    spb1 = Storage_perBundle.new

    #EventDispatcher should be called, but it is difficult to test, 
    #because we don't know at what time `dispatch' will be done.
    #EventDispatcher.instance.dispatch(:bundleParsed, bundle)

    spb1.save(bundle)
    bundleInfo = BundleInfo.new(bundle)

=begin
    puts "bundleInfo: <#{bundleInfo}>"

    spb1.bundleInfos.transaction do
      keys = spb1.bundleInfos.roots
      
      puts ">> bundleInfos.roots:"
      keys.each {|k|
        puts "key: <#{k}> <#{spb1.bundleInfos.root?(k)}> =#{k.eql?(bundleInfo)}="
	puts k.class == bundleInfo.class
	puts k.destEid == bundleInfo.destEid, k.destEid, bundleInfo.destEid
	puts k.srcEid == bundleInfo.srcEid, k.srcEid, bundleInfo.srcEid
        puts k.creationTimestamp == bundleInfo.creationTimestamp
        puts k.lifetime == bundleInfo.lifetime
        puts k.bundleId == bundleInfo.bundleId
        puts k.fragmentOffset == bundleInfo.fragmentOffset
	puts "fn: <#{spb1.bundleInfos[k]}>"
      }
    end
=end
 
    assert(!spb1.timeToDie?(bundleInfo))
    load = spb1.load(bundleInfo)

    assert_equal("bundle stored", load.payload)
    assert_equal("dtn://test", load.destEid.to_s)
    assert_equal("localhost:src", load.srcEid.to_s)

    assert_equal(bundle.to_s, load.to_s)

    FileUtils.remove_dir(RDTNConfig.instance.storageDir)
  end
 
  def test_get_bundleInfoList

  end

  def test_ruby_file
    fn = "/tmp/a/b/c/test.rb"
    basename = File.basename(fn)
    dirname = File.dirname(fn)
    assert_equal("test.rb", basename)
    assert_equal("/tmp/a/b/c", dirname)
    assert_equal(fn, File.join(dirname, basename))
  end

  def test_ruby_pstore
    ps = PStore.new("/tmp/rpstore")
    bundle = Bundling::Bundle.new(payload="bundle stored",
				  destEid="dtn://test", srcEid="localhost:src")
    bundleInfo = BundleInfo.new(bundle)
    extraBI = BundleInfo.new(bundle)
    ps.transaction do
      ps[bundleInfo] = "fn"
      assert(bundleInfo.eql?(extraBI))
      assert(ps.root?(bundleInfo))
      assert(ps.root?(extraBI))
      assert_equal("fn", ps[extraBI])
    end
    File.delete("/tmp/rpstore")
  end

 
 
end#Test_storage_perBundle

