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
require "clientregcl"
require "clientlib"


class TestAppLib < Test::Unit::TestCase

  def setup
    RdtnLogger.instance.level = Logger::ERROR
    @appIf = AppIF::AppInterface.new("client0")
  end

  def teardown
    EventDispatcher.instance.clear
    @appIf.close
  end

  def test_applib1
    bundleContent="test!"
    begin
      bundleContent = open(File.join(File.dirname(__FILE__), "mbfile")) do |f|
	f.read
      end
    rescue
      RdtnLogger.instance.warn("Could not open large testfile")
    end

    bundleOrig="dtn://bla.fasel"

    c=RdtnClient.new
    c.open("localhost",7777)
    r=RegInfo.new(bundleOrig)
    c.register(r)
    b=Bundling::Bundle.new(bundleContent, "dtn://my.dest")
    c.sendBundle(b)
    c.unregister(r)

    eventSent = false
    EventDispatcher.instance.subscribe(:bundleParsed) do |bundle| 
      eventSent = true
      assert_equal(bundleContent.length, bundle.payload.length)
    end

    sleep(1)
    c.close

    assert(eventSent, "Bundle event was not received")

  end


end
