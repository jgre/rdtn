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
require "event-loop/timer"

require "contactmgr"
require "rdtnevent"
require "tcpcl"
require "eidscheme"

class TestContactManager < Test::Unit::TestCase

  def test_insertion
    cm = ContactManager.new
    link = TCPCL::TCPLink.new
    eid = EID.new("dtn://test/fasel")
    link.remoteEid = eid

    # We need to do this through the event loop to give the event dispatcher
    # time to deliver
    EventLoop.later do
      result = cm.findLink {|l| l == link}
      assert_equal(link, result)
      #result = cm.findLinkByEid(eid)
      #assert_nil(result)

      EventDispatcher.instance.dispatch(:contactClosed, link)
      #EventDispatcher.instance.dispatch(:contactEstablished, link)
    end
    #1.seconds.from_now do
    #  result = cm.findLinkByEid(eid)
    #  assert_equal(link, result)
    #  EventDispatcher.instance.dispatch(:contactClosed, link)
    #end

    3.seconds.from_now do
      result = cm.findLink {|l| l == link}
      assert_nil(result)
      #result = cm.findLinkByEid(eid)
      #assert_nil(result)
      
      EventLoop.quit()
    end

    EventLoop.run()

  end
end
