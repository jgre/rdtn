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
# $Id$

module RerunThread

  def spawnThread(*args, &block)
    RdtnLogger.instance.debug("Starting thread")
    return Thread.new(*args) do |*args|
      lastErrorTime = 0
      
      # If two error occur within the same second, we give up; 
      # something is severely broken.
      while not Time.now.to_i == lastErrorTime
	begin
	  block.call(*args)
	rescue => ex
	  lastErrorTime = Time.now.to_i
	  RdtnLogger.instance.error(ex)
	  RdtnLogger.instance.info("Restarting thread operation in #{self.class.to_s}")
	else
	  Thread.current.exit
	end
      end
      RdtnLogger.instance.error("Errors in thread for class #{self.class.to_s} are reoccuring too fast; giving up.")
      Thread.current.exit
    end
  end

end
