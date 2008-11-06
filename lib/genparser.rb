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

unless ''.respond_to? :bytesize
  class String
    def bytesize
      self.length
    end
  end
end

module GenParser

  module ClassMethods

    def _genParseMethods
      res = public_instance_methods.find_all {|meth| /^_genParse/ =~ meth}
      res.sort_by do |meth|
        /^_genParse(\d+)/ =~ meth
        $1.to_i
      end
    end

    def field(fieldId, params = {}, &block)
      index = _genParseMethods.length
      attr_accessor fieldId
      define_method("_genParse#{index}_#{fieldId}") do |sio|
        if params.has_key?(:length)
          val = params[:length]
          length = val.is_a?(Symbol) ? self.send(val) : val
        else
          length = nil
        end

        unless params[:decode] or length
          raise RuntimeError, "Cannot parse field #{fieldId} without decoder or length indication."
        end

        decode = params[:decode] || lambda do |io, len|
	  mypos = io.pos
          dat = io.read(len)
          if not dat or dat.bytesize < length
            dlen = dat ? dat.bytesize : 0
            raise InputTooShort, len - dlen
          end
          [dat, dat.bytesize]
        end

        check = lambda do |dat|
          unless params[:condition].nil? or params[:condition].call(dat)
            raise ProtocolError,"Condition for field '#{fieldId}' not satisfied"
          end
        end

        handle = lambda do |dat|
          if params.has_key?(:handler)
            self.send(params[:handler], dat)
          elsif block
            block.call(self, dat) 
          else
            send("#{fieldId}=", dat)
            #instance_variable_set("@#{fieldId}", dat)
          end
        end

        if params[:array]
          length.times do |i|
            data, length = decode.call(sio, nil)
            check.call(data)
            handle.call(data)
          end
        else
          data, length = decode.call(sio, length) 
          check.call(data)
          handle.call(data)
        end

      end
    end

  end

  def self.included(host_class)
    host_class.extend(ClassMethods)
  end

  def parse(buf)
    @finishedIndex = 0
    if buf.class == String
      sio = StringIO.new(buf)
    elsif buf.kind_of? StringIO
      sio = buf
    else
      raise TypeError, "Parser needs input as String or StringIO."
    end

    self.class._genParseMethods.each_with_index do |meth, i|
      self.send(meth, sio)
      @finishedIndex = i
    end
  end

  def parserFinished?
    if @finishedIndex
      return @finishedIndex == (self.class._genParseMethods.length - 1)
    else
      false
    end
  end

  def marshal_dump
    vars = instance_variables.find_all {|var| var != "@genParserFields"}
    vars.map {|var| [var, instance_variable_get(var)]}
  end

  def marshal_load(arr)
    arr.each {|var, val| instance_variable_set(var, val)}
  end

  def to_yaml_properties
    instance_variables.find_all {|var| var != "@genParserFields"}
  end

  def GenParser.decodeNum(sio, length)
    if not length
      raise TypeError, "Need to know the length of Numeric value"
    end
    data = sio.read(length)
    if not data or data.bytesize < length
      raise InputTooShort, length
    end
    result = case length
	     when 1 then data.respond_to?(:bytes) ? data.bytes.first : data[0]
	     when 2 then data[0, length].unpack('n')[0]
	     when 4 then data[0, length].unpack('N')[0]
	     when 8 then data[0, length].unpack('Q')[0]
	     else
	       raise NotImplementedError, "Unsupported length for numbers: #{length} octets"
	     end
    return result, length
  end

  def GenParser.decodeNullTerminated(sio, length=nil)
    oldPos = sio.pos
    data = sio.gets(0.chr)
    if length and data.bytesize > length
      data.slice!(length, -1) # Cut off the unwanted end
      sio.pos = oldPos+length
    else
      length = data.bytesize
    end
    data.slice!(-1) if data[-1] == 0 or data[-1] == "\0"
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
