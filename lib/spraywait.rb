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

require "rdtnevent"
require "genparser"
require "queue"

class SprayWaitFilter

  def initialize
    @subHandler = RdtnConfig::Settings.instance.subscriptionHandler
  end

  def filterBundle?(bundle, neighbor = nil)
    if neighbor
      if Regexp.new(neighbor.to_s) =~ bundle.destEid.to_s
	# neighbor is destination, so the bundle should be delivered directly
	return false
      elsif @subHandler and @subHandler.neighborSubs[neighbor.to_s] and @subHandler.neighborSubs[neighbor.to_s].subscribedLocal?(bundle.destEid.to_s)
	# neighbor is original subscriber, so the bundle should be delivered
	# directly
	return false
      end
    end
  end

end

regFilter(:sprayWaitFilter, SprayWaitFilter)

class CopyCountTask < Bundling::TaskHandler

  def processBundle(bundle)
    localEid = RdtnConfig::Settings.instance.localEid.to_s
    if Regexp.new(localEid) =~ bundle.destEid.to_s
      # For bundle originated from this router, assign the initial number of
      # allowed copies 
      nCopies = Settings.instance.sprayWaitCopies
      bundle.addBlock(Bundling::CopyCountBlock.new(bundle, nCopies)) if nCopies
    end
    self.state = :processed
  end

  def processDeletion(bundle)
    self.state = :deleted
  end

end

regWFTask(5, CopyCountTask)

class NetworkSizeEstimator
end
