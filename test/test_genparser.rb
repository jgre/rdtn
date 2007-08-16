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
require "genparser"

class MyParser
  include GenParser
  attr_accessor :f1, :f2, :f3, :f4, :f1Len
  attr_reader :fields

  def initialize
    @f1Len = 0

    defField(:f0, :length => 1, 
	     :block => lambda { |data| defField(:f1, :length => data)},
	     :handler => :f1Len=,
	     #:decode => lambda {|data,length|GenParser.decodeNum(data,length)})
	     :decode => GenParser::NumDecoder)
    defField(:f1, :handler => :field1, 
	    :condition => lambda {|data| data == "AA"})
    defField(:f2, :length => 4, :block => self.method(:field2))
    defField(:f3, :length => 2, :block => lambda do |data| 
      @f3 = data
    end)
    defField(:f4, :length => 4, :handler => :f4=)
  end

  def field1(data)
    @f1=data
  end

  def field2(data)
    @f2=data
  end

end

class TestGenParser< Test::Unit::TestCase


  def test_genparse
    f0 = 2.chr
    f1 = "AA"
    f2 = "bbbb"
    f3 = "CC"
    f4 = "dddd"
    input = f0+f1+f2+f3+f4
    mp = MyParser.new
    assert_nothing_raised {mp.parse(input)}
    assert_equal(f0[0], mp.f1Len)
    assert_equal(f1, mp.f1)
    assert_equal(f2, mp.f2)
    assert_equal(f3, mp.f3)
    assert_equal(f4, mp.f4)
  end

  def test_condition
    input = StringIO.new(2.chr + "bla")
    mp = MyParser.new
    assert_raise(ProtocolError) { mp.parse(input) }
  end

  def test_decoders
    str = "abcde"
    short = 1024
    long = 70000
    big = 68719476736

    sio = StringIO.new(str+"\0"+[short].pack('n')+[long].pack('N')+[big].pack('Q'))
    assert_equal([str, str.length+1], GenParser.decodeNullTerminated(sio))
    assert_equal([short, 2], GenParser.decodeNum(sio, 2))
    assert_equal([long, 4], GenParser.decodeNum(sio, 4))
    assert_equal([big, 8], GenParser.decodeNum(sio, 8))

  end
end
