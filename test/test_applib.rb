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


  def test_applib1
    log=RdtnLogger.instance()
    log.level=Logger::DEBUG
    
    bundleContent=""
    bundleOrig="dtn://bla.fasel"

    log.debug("building server interface")

    #a=AppIF::AppInterface.new("app1", "-h localhost -p 7777")

    EventLoop.later do
      log.debug("block 1")
      c=RdtnClient.new
      c.open("localhost",7777)
      r=RegInfo.new(bundleOrig)
      c.register(r)
      b=Bundling::Bundle.new("test!", "dtn://my.dest")
      c.sendBundle(b)
      c.unregister(r)
      c.close()
    end

    EventLoop.after(1) do
#    EventLoop.later do
      log.debug("block 2")
      EventLoop.quit
  end


    log.debug("starting main loop")

    EventLoop.run

    log.debug("done")

  end


end
