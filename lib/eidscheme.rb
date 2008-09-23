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

EID_REGEXP = /^([[:alnum:]]+):([[:print:]]+)$/

class String

  def is_eid?
    self =~ EID_REGEXP
  end

  def scheme
    if empty?                then 'dtn'
    elsif self =~ EID_REGEXP then $1
    else raise InvalidEid, str
    end
  end

  def ssp
    if empty?                then 'none'
    elsif self =~ EID_REGEXP then $2
    else raise InvalidEid, str
    end
  end

  def scheme=(scheme)
    if empty?     then self << scheme << ':none'
    elsif is_eid? then gsub!(/^[[:alnum:]]+:/, "#{scheme}:")
    else raise InvalidEid, self
    end
  end

  def ssp=(ssp)
    if empty?     then self << 'dtn:' << ssp
    elsif is_eid? then gsub!(/:[[:print:]]+$/, ":#{ssp}")
    else raise InvalidEid, self
    end
  end

  def eid_append(str)
    res = ""
    res.scheme = scheme
    if ssp[-1].chr == "/" and str.to_s[0].chr == "/"
      res.ssp = ssp + str[1..-1]
    elsif ssp[-1].chr != "/" and str.to_s[0].chr != "/"
      res.ssp = ssp + "/" + str.to_s
    else
      res.ssp = ssp + str.to_s
    end
    return res
  end

end
