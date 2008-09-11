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

require "rdtnerror"

class InvalidEid < ProtocolError
  def initialize(str)
    super("Invalid EID: #{str}")
  end
end

class EID
  attr_reader :scheme, :ssp

  def initialize(str=nil)
    if str and str != ""
      str = str.to_s # Just in case str is actually an EID object
      if str =~ /([[:alnum:]]+):([[:print:]]+)/
	@scheme = $1
	@ssp = $2
        @str = str
      else
	raise InvalidEid, str
      end
    else
      @scheme = "dtn"
      @ssp = "none"
      @str = 'dtn:none'
    end
  end

  def scheme=(scheme)
    @scheme = scheme
    @str    = nil
  end

  def ssp=(ssp)
    @ssp = ssp
    @str = nil
  end

  def to_s
    @str ||= "#@scheme:#@ssp" unless @scheme.empty? or @ssp.empty?
  end

  def indexingPart
    return self.to_s
  end

  def join(str)
    res = EID.new
    res.scheme = @scheme
    if @ssp[-1].chr == "/" and str.to_s[0].chr == "/"
      res.ssp = @ssp + str[1..-1]
    elsif @ssp[-1].chr != "/" and str.to_s[0].chr != "/"
      res.ssp = @ssp + "/" + str.to_s
    else
      res.ssp = @ssp + str.to_s
    end
    return res
  end

  def ==(eid2)
    self.to_s == eid2.to_s
  end

end
