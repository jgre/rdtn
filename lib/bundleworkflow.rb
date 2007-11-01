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
require "rdtnevent"
require "bundle"

module Bundling

  class BadInput < RuntimeError
    def initialize(currentTask)
      super("Bad input for task #{currentTask.class.name}")
    end
  end

  # A BundleWorkflow manages the processing of a bundle.
  #
  # A workflow object is created for each bundle that is received. It maintains
  # a queue of data that is parsed into a bundle.
  # The process has the following steps:
  # - Store the bundle
  # - Reassemble fragments if necessary
  # - Handle Administrative Records and Custody
  # - Forward the bundle
  class BundleWorkflow

    def BundleWorkflow.registerEvents
      EventDispatcher.instance.subscribe(:bundleParsed) do |bundle|
        if bundle
	  bwf = BundleWorkflow.new(bundle)
	  bwf.processBundle
	end
      end
    end

    def initialize(bundle)
      @bundle = bundle
      @taskQueue = [
	StoreHandler.new(self),
	ReassemblyHandler.new(self),
	CustodyHandler.new(self),
	AdminRecHandler.new(self),
	Forwarder.new(self)
      ]
      @curTaskIndex = 0

    end

    # We do not dump the actual bundle but only its id
    def marshal_dump
      [@bundle.bundleId, @taskQueue, @curTaskIndex]
    end

    def marshal_load(params)
      store = RdtnConfig::Settings.instance.store
      @bundle    = store.getBundle(params[0]) if store
      if @bundle 
	@taskQueue    = params[1]
	@curTaskIndex = params[2]
      else        
	@taskQueue    = []
	@curTaskIndex = -1
      end
    end

    def curTask
      @taskQueue[@curTaskIndex]
    end

    def finished?
      not curTask
    end

    def deletionFinished?
      @curTaskIndex < 0
    end

    def nextTask
      @curTaskIndex += 1
    end

    def prevTask
      @curTaskIndex -= 1
    end

    def processBundle
      until finished?
	curTask.processBundle(@bundle)
	if curTask.state == :processed: nextTask 
	else break
	end
      end
      return nil
    end

    def processDeletion
      until deletionFinished?
	prevTask if finished?
	curTask.processDeletion(@bundle)
	if curTask.state == :deleted: prevTask
	else break
	end
      end
      return nil
    end

  end

  class TaskHandler

    # States: ':initial', ':processed', ':deleted'
    attr_accessor :state
    attr_reader   :workflow
    protected     :workflow, :state=

    def initialize(workflow)
      @workflow = workflow
      @state    = :initial
    end

  end

  class StoreHandler < TaskHandler

    def processBundle(bundle)
      store = RdtnConfig::Settings.instance.store
      if store
	begin
	  store.storeBundle(bundle)
	rescue BundleAlreadyStored
	  puts "Already stored."
	  return nil
	end
	store.save
      end
      self.state = :processed
    end

    def processDeletion(bundle)
      store = RdtnConfig::Settings.instance.store
      if store
	store.deleteBundle(bundle.bundleId)
	store.save
      end
      self.state = :deleted
    end

  end

  class ReassemblyHandler < TaskHandler
    
    def processBundle(bundle)
      self.state = :processed
    end

    def processDeletion(bundle)
      self.state = :deleted
    end

  end

  class CustodyHandler < TaskHandler

    def processBundle(bundle)
      self.state = :processed
    end

    def processDeletion(bundle)
      self.state = :deleted
    end

  end

  class AdminRecHandler < TaskHandler

    def processBundle(bundle)
      self.state = :processed
    end

    def processDeletion(bundle)
      self.state = :deleted
    end

  end

  class Forwarder < TaskHandler

    def processBundle(bundle)
      EventDispatcher.instance.subscribe(:bundleForwarded) do |bndl, link|
	self.state = :processed if bundle.bundleId == bndl.bundleId
      end
      EventDispatcher.instance.dispatch(:bundleToForward, bundle)
    end

    def processDeletion(bundle)
      self.state = :deleted
    end

  end

end # module Bundling
