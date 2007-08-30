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
require "tcpcl"
require "eidscheme"

class TestContactManager < Test::Unit::TestCase

  def setup
  end

  def teardown
    EventDispatcher.instance.clear
  end

  def test_insertion
    cm = ContactManager.new
    link = TCPCL::TCPLink.new
    eid = EID.new("dtn://test/fasel")
    link.remoteEid = eid

    result = cm.findLink {|l| l == link}
    assert_equal(link, result)

    link.close

    result = cm.findLink {|l| l == link}
    assert_nil(result)

  end
end
