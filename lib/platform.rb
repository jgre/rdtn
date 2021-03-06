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

require 'socket'
require 'singleton'

class RdtnPlatform
  if (RUBY_PLATFORM == "i386-mswin32")
    Socket::IP_MULTICAST_LOOP = 11 unless Socket.const_defined?('IP_MULTICAST_LOOP')
    Socket::IP_ADD_MEMBERSHIP = 12 unless Socket.const_defined?('IP_ADD_MEMBERSHIP')
  end 
  
  def udpmaxdgram 
    if (RUBY_PLATFORM == "universal-darwin9.0") #FreeBSD? Mac OS X 10.4?
      return 9216 
    end
    
    return 65000
  end
  
 def soreuseaddr(socket)
   socket.setsockopt(Socket::SOL_SOCKET, Socket::SO_REUSEADDR, 1)
   if (RUBY_PLATFORM == "universal-darwin9.0")
       socket.setsockopt(Socket::SOL_SOCKET, Socket::SO_REUSEPORT, 1)
   end
 end
end






