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

require "stringio"
require "sdnv"

module GenParser

  def defField(fieldId, params)
    @genParserFields = [] if not defined? @genParserFields
    res = @genParserFields.find do |obj| 
      if obj[0] == fieldId
	obj[1].merge!(params)
      end
    end
    @genParserFields << res = [fieldId, params] unless res
  end

  def parse(buf)
    if buf.class == String
      sio = StringIO.new(buf)
    elsif buf.kind_of? StringIO
      sio = buf
    else
      raise TypeError, "Parser needs input as String or StringIO."
    end
    @genParserFields.each do |field|
      if field[1].has_key?(:ignore) and field[1][:ignore]
	next
      end
      if field[1].has_key?(:length): length = field[1][:length]
      else length = nil
      end
      if field[1].has_key?(:decode)
	data, length = field[1][:decode].call(sio, length) 
      elsif length
	data = sio.read(length)
	if not data or data.length < length
	  dlen = data ? data.length : 0
	  raise InputTooShort, length - dlen
	end
      else
	raise RuntimeError, "Cannot parse field #{field[0]} without decoder or length indication."
      end

      if field[1].has_key?(:condition)
	if not field[1][:condition].call(data)
	  raise ProtocolError, "Condition for field '#{field[0]}' not fulfilled."
	end
      end

      if field[1].has_key?(:block)
	field[1][:block].call(data) 
      end

      if field[1].has_key?(:handler)
	if field[1].has_key?(:object)
	  obj = field[1][:object]
	else
	  obj = self
	end
	obj.send(field[1][:handler], data) 
      end
    end
  end

  def GenParser.decodeNum(sio, length)
    if not length
      raise TypeError, "Need to know the length of Numeric value"
    end
    data = sio.read(length)
    if not data or data.length < length
      raise InputTooShort, length
    end
    result = case length
	     when 1: data[0]
	     when 2: data[0, length].unpack('n')[0]
	     when 4: data[0, length].unpack('N')[0]
	     when 8: data[0, length].unpack('Q')[0]
	     else
	       raise NotImplementedError, "Unsupported length for numbers: #{length} octets"
	     end
    return result, length
  end

  def GenParser.decodeNullTerminated(sio, length=nil)
    oldPos = sio.pos
    data = sio.gets(0.chr)
    if length and data.length > length
      data.slice!(length, -1) # Cut off the unwanted end
      sio.pos = oldPos+length
    else
      length = data.length
    end
    data.slice!(-1) if data[-1] == 0
    return data, length
  end

  def GenParser.dontDecode(sio, length=nil)
    return nil, 0
  end

  NumDecoder = GenParser.method(:decodeNum)
  NullTerminatedDecoder = GenParser.method(:decodeNullTerminated)
  NullDecoder = GenParser.method(:dontDecode)
  SdnvDecoder = Sdnv.method(:decode)

end
