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
require "contactmgr"
require "rdtnevent"
require "eidscheme"

class CMockLink < Link
  attr_accessor :remoteEid, :bundle

  def initialize(config, evDis)
    super(config, evDis)
    @bundles = []
  end

  def open(n, options)
    self.name = n
    @evDis.dispatch(:linkOpen, self)
  end

  def sendBundle(bundle)
    @bundle = bundle
    @bundles.push(bundle)
  end

  def received?(bundle)
    @bundles.any? {|b| b.to_s == bundle.to_s}
  end

end

regCL(:cmock, nil, CMockLink)

class TestContactManager < Test::Unit::TestCase

  def setup
    @evDis  = EventDispatcher.new
    @config = RdtnConfig::Settings.new
  end

  def teardown
  end

  def test_insertion
    cm = ContactManager.new(@config, @evDis)
    link = CMockLink.new(@config, @evDis)
    eid = "dtn://test/fasel"
    link.remoteEid = eid

    result = cm.findLink {|l| l == link}
    assert_equal(link, result)

    link.close

    result = cm.findLink {|l| l == link}
    assert_nil(result)

  end

  def test_opportunity
    linkFound = false
    eventRec  = false
    eid       = "dtn://test"
    cm = ContactManager.new(@config, @evDis)
    @evDis.subscribe(:neighborContact) do |neighbor, link|
      eventRec = true
      assert_equal(eid, neighbor.eid)
    end
    @evDis.subscribe(:linkCreated) do |cmlink|
      linkFound = true
    end

    @evDis.dispatch(:opportunityAvailable, :cmock, {}, eid)

    assert(eventRec)
    assert(linkFound)
  end
    
end
