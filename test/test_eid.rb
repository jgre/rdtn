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
require "eidscheme"


class TestEID < Test::Unit::TestCase

  def test_join
    eid1 = EID.new("dtn:test")
    eid2 = EID.new("dtn:test/")
    eid3 = EID.new
    str1 = "/test"
    str2 = "test"

    result = "dtn:test/test"

    assert_equal(result, eid1.join(str1).to_s)
    assert_equal(result, eid2.join(str1).to_s)
    assert_equal(result, eid1.join(str2).to_s)
    assert_equal(result, eid2.join(str2).to_s)
  end

end
