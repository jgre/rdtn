#  Copyright (C) 2008 Janico Greifenberg <jgre@jgre.org>
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

$:.unshift File.join(File.dirname(__FILE__), "..", "..", "lib")
$:.unshift File.join(File.dirname(__FILE__), "..", "..", "sim")
$:.unshift File.join(File.dirname(__FILE__), "..", "..", "sim", 
                     "plugins", "trace-parsers")

require "test/unit"
require "tempfile"
require "eventqueue"
require "mitparser"

SAMPLE_MIT_TRACE = <<END_OF_STRING
@1435 0 <-> 1 up
@1447 0 <-> 1 down
@2408177 3 <-> 2 up
@2408339 3 <-> 2 down
END_OF_STRING

class TestMITParser < Test::Unit::TestCase

  def setup
    tf = Tempfile.new("sample_trace")
    tf.write(SAMPLE_MIT_TRACE)
    tf.close
    @path = tf.path
  end

  def test_parse
    parser = MITParser.new(:tracefile => @path)
    ev = parser.events
    assert_equal(4, ev.events.length)

    assert_equal(1435, ev.events[0].time)
    assert_equal(0, ev.events[0].nodeId1)
    assert_equal(1, ev.events[0].nodeId2)
    assert_equal(:simConnection, ev.events[0].type)

    assert_equal(1447, ev.events[1].time)
    assert_equal(0, ev.events[1].nodeId1)
    assert_equal(1, ev.events[1].nodeId2)
    assert_equal(:simDisconnection, ev.events[1].type)

    assert_equal(2408177 , ev.events[2].time)
    assert_equal(3, ev.events[2].nodeId1)
    assert_equal(2, ev.events[2].nodeId2)
    assert_equal(:simConnection, ev.events[2].type)

    assert_equal(2408339 , ev.events[3].time)
    assert_equal(3, ev.events[3].nodeId1)
    assert_equal(2, ev.events[3].nodeId2)
    assert_equal(:simDisconnection, ev.events[3].type)
  end

end
