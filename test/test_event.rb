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
    @ev = EventDispatcher.new
  end

  def teardown
  end

  def test_dispatch
    param = "bla"
    n = 5
    n_received = 0

    n.times do |cur_n|
      @ev.subscribe(:test_event) do |my_arg|
	assert_equal(param, my_arg)
	n_received += 1
      end
    end

    @ev.subscribe(:other_event) do |my_arg|
    end

    @ev.dispatch(:test_event, param)
    @ev.dispatch(:other_event, "other")

    assert_equal(n, n_received)
  end

  def test_unsubscribe
    param = "bla"
    n_received = 0

    h = @ev.subscribe(:test_event) do |my_arg|
      assert_equal(param, my_arg)
      n_received += 1
    end

    @ev.dispatch(:test_event, param)

    @ev.unsubscribe(:test_event, h)

    @ev.dispatch(:test_event, param)

    assert_equal(1, n_received)
  end

end
