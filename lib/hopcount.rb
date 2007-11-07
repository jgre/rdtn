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

require "bundle"

class HopCountBlock < Bundling::Block

  include GenParser

  attr_accessor :hopCount

  HOP_COUNT_BLOCK  = 192

  def initialize(bundle, copyCount = 0)
    super(bundle)
    @hopCount = hopCount

    defField(:hcblockLength, :decode => GenParser::SdnvDecoder)
    defField(:hc, :decode => GenParser::SdnvDecoder, :handler => :hopCount=)
  end

  def to_s
    data = ""
    data << HOP_COUNT_BLOCK
    data << flags
    hcStr = Sdnv.encode(@hopCount)
    data << Sdnv.encode(hcStr.length)
    data << hcStr
    return data
  end

end

regBundleBlock(HopCountBlock::HOP_COUNT_BLOCK, HopCountBlock)

class CopyCountBlock < Bundling::Block

  include GenParser

  attr_accessor :copyCount

  COPY_COUNT_BLOCK = 193

  def initialize(bundle, copyCount = 0)
    super(bundle)
    @copyCount = copyCount

    defField(:ccblockLength, :decode => GenParser::SdnvDecoder)
    defField(:cc, :decode => GenParser::SdnvDecoder, :handler => :copyCount=)
  end

  def to_s
    data = ""
    data << COPY_COUNT_BLOCK
    data << flags
    ccStr = Sdnv.encode(@copyCount)
    data << Sdnv.encode(ccStr.length)
    data << ccStr
    return data
  end

end

regBundleBlock(CopyCountBlock::COPY_COUNT_BLOCK, CopyCountBlock)
