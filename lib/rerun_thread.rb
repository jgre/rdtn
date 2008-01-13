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

module RerunThread

  def spawnThread(*args, &block)
    return Thread.new(*args) do |*args|
      lastErrorTime = 0
      
      ret = nil
      # If two error occur within the same second, we give up; 
      # something is severely broken.
      while not Time.now.to_i == lastErrorTime
	begin
	  ret = block.call(*args)
	rescue => ex
	  lastErrorTime = Time.now.to_i
	  rerror(self, ex)
	  rinfo(self, "Restarting thread operation in #{self.class.to_s}")
	  err = true
	else
	  err = false
	  break
	end
      end
      if err
	rerror(self, "Errors in thread for class #{self.class.to_s} are reoccuring too fast; giving up.")
      end
      ret
    end
  end

end
