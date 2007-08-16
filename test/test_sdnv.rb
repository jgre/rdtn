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
require "sdnv"

class TestSdnv < Test::Unit::TestCase
  
  include Sdnv

  def test_self_encode_decode
    0.upto(10000) do |n|
      assert_equal(n,decode(encode(n))[0])
    end
  end


  # test cases from draft-eddy-dtn-sdnv-02
  def test_cases_draft_eddy_sdnv
    tests = [[0xABC, 0x95.chr() + 0x3C.chr()],
             [0x1234, 0xA4.chr() + 0x34.chr()],
              [0x4234, 0x81.chr() + 0x84.chr() +0x34.chr()],
              [0x7F, 0x7F.chr()]]

    tests.each do |tp|
      assert_equal(tp[1], encode(tp[0]))
      assert_equal(tp[0], decode(tp[1])[0])
      # Test if the length is set correctly
      assert_equal(tp[1].length, decode(tp[1])[1])
    end
  end

  def test_too_short
    assert_raise(InputTooShort) {res = decode(StringIO.new(0x95.chr()))}
    #assert_nil(res[0])
  end
  
  def test_sdnv_mixin_Fixnum
    0.upto(10000) do |n|
      assert_equal(n,n.to_sdnv().from_sdnv())
    end
  end

  def test_sdnv_mixin_Bignum
    1000.upto(2000) do |n|
      v=n*10000000
      assert_equal(v,v.to_sdnv().from_sdnv())
    end
  end




end
