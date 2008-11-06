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
require "setdestparser"

SAMPLE_NS2_TRACE = <<END_OF_STRING
$node_(0) set X_ 1.0
$node_(0) set Y_ 0.0
$node_(0) set Z_ 0.0
$node_(1) set X_ 200.0
$node_(1) set Y_ 0.0
$node_(1) set Z_ 0.0
$node_(2) set X_ 500.0
$node_(2) set Y_ 0.0
$node_(2) set Z_ 0.0
$ns_ at 10.0 "$node_(1) setdest 300.0 10.0 100.0"
END_OF_STRING

class TestMITParser < Test::Unit::TestCase

  def setup
    tf = Tempfile.new("sample_trace")
    tf.write(SAMPLE_NS2_TRACE)
    tf.close
    @path = tf.path
  end

  def test_parse
    parser = SetdestParser.new(:duration => 20, :tracefile => @path)
    ev = parser.events
    assert_equal(3, ev.events.length)

    assert_equal(0, ev.events[0].time)
    assert_equal(1, ev.events[0].nodeId1)
    assert_equal(2, ev.events[0].nodeId2)
    assert_equal(:simConnection, ev.events[0].type)

    assert_equal(10, ev.events[1].time)
    assert_equal(1, ev.events[1].nodeId1)
    assert_equal(2, ev.events[1].nodeId2)
    assert_equal(:simDisconnection, ev.events[1].type)

    assert_equal(10, ev.events[2].time)
    assert_equal(2, ev.events[2].nodeId1)
    assert_equal(3, ev.events[2].nodeId2)
    assert_equal(:simConnection, ev.events[2].type)
  end

end
