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

require "stringio"
require "rdtnerror"

if RUBY_VERSION.include?('1.8')
  class Fixnum; def ord; return self; end; end
end

module Sdnv

  def decode(buf, slen=nil)
    if buf.class == String
      sio = StringIO.new(buf)
    elsif buf.class == StringIO
      sio = buf
    else
      raise TypeError, "Need SDNV input as String or StringIO"
    end
    if sio.pos - sio.length == 0
      raise InputTooShort, nil # We cannot tell how long this SDNV is.
    end
    n=i=0
    sio.each_byte do |v|
      n = n << 7
      n = n + (v & 0x7F)
      if (v >> 7) == 0
        slen = i + 1
        break
      elsif (i==buf.length()-1) or (slen and i>slen) 
	n = nil
	raise InputTooShort, nil # We cannot tell how long this SDNV is.
	break
      end
      i += 1
    end
    return [n,slen]
  end


  def encode(n)
    r = ""
    if (n >=0)
      flag = 0
      done = false
      while(not done)
        newbits = n & 0x7F
        n = n >> 7
        r = (newbits + flag).chr + r
        if(flag==0) then flag = 0x80
        end
        if(n==0) then done=true
        end
      end
    end
    return r
  end

end # module Sdnv



include Sdnv

# Mixin module for number types
module SdnvEncodable

  def to_sdnv
    Sdnv.encode(self)
  end

end # module SdnvEncodable


# Mixin module for string types
module SdnvDecodable
#  include Sdnv
  def from_sdnv()
    Sdnv.decode(self)[0]
  end

end # module SdnvDecodable


class Fixnum
  include SdnvEncodable
end

class Bignum
  include SdnvEncodable
end

class String
  include SdnvDecodable
end




