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
require "rdtnevent"

class TestEvent < Test::Unit::TestCase
  
  def setup
  end

  def teardown
    EventDispatcher.instance.clear
  end

  def test_dispatch
    param = "bla"
    n = 5
    n_received = 0

    n.times do |cur_n|
      EventDispatcher.instance().subscribe(:test_event) do |my_arg|
	assert_equal(param, my_arg)
	n_received += 1
      end
    end

    EventDispatcher.instance().subscribe(:other_event) do |my_arg|
    end

    EventDispatcher.instance().dispatch(:test_event, param)
    EventDispatcher.instance().dispatch(:other_event, "other")

    assert_equal(n, n_received)
  end

  def test_unsubscribe
    param = "bla"
    n_received = 0

    h = EventDispatcher.instance().subscribe(:test_event) do |my_arg|
      assert_equal(param, my_arg)
      n_received += 1
    end

    EventDispatcher.instance().dispatch(:test_event, param)

    EventDispatcher.instance().unsubscribe(:test_event, h)

    EventDispatcher.instance().dispatch(:test_event, param)

    assert_equal(1, n_received)
  end

  def test_unsubscribeIf
    param = "bla"
    n_received = 0

    h = lambda  do |my_arg|
      assert_equal(param, my_arg)
      n_received += 1
    end

    EventDispatcher.instance().subscribe(:usi_test_event, &h)
    EventDispatcher.instance().subscribe(:usi_other_event, &h)

    EventDispatcher.instance().dispatch(:usi_test_event, param)
    EventDispatcher.instance().dispatch(:usi_other_event, param)

    EventDispatcher.instance().unsubscribeIf do |id, handler|
      handler.to_s == h.to_s
    end

    EventDispatcher.instance().dispatch(:usi_test_event, param)
    EventDispatcher.instance().dispatch(:usi_other_event, param)

    assert_equal(2, n_received)
  end

end
