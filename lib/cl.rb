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

require 'singleton'

# Convergence Layer Base Class

class Connection

end


# Interface class for incoming connections
# Interface objects can generate new Links
class Interface
  attr_accessor :name
end


# Link class for uni- and bi-directional links
# each link has a specific type (the convergence layer type).
# 


class Link
  MIN_READ_BUFFER=1048576

  attr_reader :bytesToRead
  attr_accessor :name

  def initialize
    EventDispatcher.instance().dispatch(:linkCreated, self)
    @bytesToRead = MIN_READ_BUFFER
  end

  # When reading data we rather err to the side of greater numbers, as reading
  # stops anyway, when there is no data left. And we always want to be ready
  # to read something, as we cannot be sure what the other side is up to.
  def bytesToRead=(bytes)
    if bytes and bytes > MIN_READ_BUFFER
      @bytesToRead = bytes
    end
  end


end


class CLReg
  attr_accessor :cl


  def initialize
    @cl={}
  end

  include Singleton



  def reg(name, interface, link)
    @cl[name] = [interface, link]    
  end
end

def regCL(name, interface, link)
  c=CLReg.instance()
  c.reg(name, interface, link)
end
