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
require "administrative"
require "rdtntime"
require "custodytimer"

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

    def BundleWorkflow.registerEvents(config, evDis)
      evDis.subscribe(:bundleParsed) do |bundle|
        if bundle and !bundle.expired?
	  bwf = BundleWorkflow.new(config, evDis, bundle)
	  bwf.processBundle
	end
      end
      evDis.subscribe(:bundleRemoved) do |bundle|
        if bundle
      	  #puts "BundleDeleted! #{bundle.srcEid}, #{bundle.destEid}" unless bundle.srcEid.to_s == RdtnConfig::Settings.instance.localEid
      	  bwf = BundleWorkflow.new(config, evDis, bundle)
      	  bwf.processDeletion
      	end
      end
    end

    def initialize(config, evDis, bundle)
      @config = config
      @evDis  = evDis
      @bundle = bundle
      @taskQueue = WorkflowTaskReg.instance.makeTasks(@config, @evDis, @bundle)
      @curTaskIndex = 0
    end

    # We do not dump the actual bundle but only its id
    def marshal_dump
      [@bundle.bundleId, @taskQueue, @curTaskIndex]
    end

    def marshal_load(params)
      store = @config.store
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
      	#puts "ProcessBundle #{curTask.class}, #{curTask.state}"
      	curTask.processBundle(@bundle)
      	if curTask.state == :processed then nextTask 
      	else break
      	end
      end
      return nil
    end

    def processDeletion
      until deletionFinished?
        prevTask if finished?
      	curTask.processDeletion(@bundle)
      	if curTask.state == :deleted then prevTask
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

    def initialize(config, evDis, workflow)
      @config   = config
      @evDis    = evDis
      @workflow = workflow
      @state    = :initial
    end

  end

  class StoreHandler < TaskHandler

    def processBundle(bundle)
      store = @config.store
      if store
	begin
	  store.storeBundle(bundle)
	rescue BundleAlreadyStored
	  #puts "(#{@config.localEid}) Already stored."
	  return nil
	end
	store.save
      end
      self.state = :processed
    end

    def processDeletion(bundle)
      store = @config.store
      # if store
      #         store.deleteBundle(bundle.bundleId)
      #         store.save
      # end
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
  
    SUCCESS = true
    FAILURE = false
        
    def processBundle(bundle)
      if bundle.requestCustody?
        rdebug("Requested Custody from #{bundle.custodianEid} for #{bundle.bundleId}")
        if (@config.acceptedCustody)
          if (bundle.custodyAccepted? == false) then
            bundle.custodyAccepted = true
          
            timer = CustodyTimer.new(bundle, @evDis)
            rdebug("Accepted Custody for #{bundle.bundleId}")
          
            # send custody signal and then update custodian
            sendCustodySignal(bundle, SUCCESS)
            bundle.custodianEid = @config.localEid
          end
        end
        # send succeeded custody signal if delivered
        h = @evDis.subscribe(:bundleForwarded) do |bndl, link, action|
          # was the bundle delivered to an app?
          if ((link.kind_of? AppIF::AppProxy) && (bundle.bundleId == bndl.bundleId))
                rdebug("bundle with custody delivered on link: #{link}")
                # generate delivery SR
          
                sendCustodySignal(bundle, SUCCESS)
          
                # prevent nasty loops
                @evDis.unsubscribe(:bundleForwarded, h)          
          end
        end
      end
      self.state = :processed
    end
  
    def processDeletion(bundle)
      self.state = :deleted
    end
  
    def sendCustodySignal(bundle, success)
      # generate custody signal if there is a custodian waiting for it
      
      if (bundle.custodianEid.to_s != "dtn:none")
        cs = CustodySignal.new
        cs.status = CustodySignal::CUSTODY_NO_ADDTL_INFO
        if (bundle.fragment?)
          cs.fragment = true
          cs.fragmentOffset = bundle.fragmentOffset
          cs.fragmentLength = bundle.aduLength
        end
  
        cs.transferSucceeded = success
  
        cs.creationTimestamp = bundle.creationTimestamp
        cs.creationTimestampSeq = bundle.creationTimestampSeq
        cs.eidLength = bundle.srcEid.to_s.length
        cs.srcEid = bundle.srcEid.to_s
        
        b = Bundling::Bundle.new(cs.to_s)
        b.destEid = bundle.custodianEid
  
        b.administrative = true
        b.lifetime = bundle.lifetime
  
        rdebug("Custody Signal to: #{b.destEid}")
  
        @evDis.dispatch(:bundleToForward, b)
      end
    end
  end

  # Generation and handling of AdministrativeRecords happens here
  class AdminRecHandler < TaskHandler
  
    
    def processBundle(bundle)
      if (bundle.administrative?)
        # handle the administrative record
        handleAdminRecord(bundle)
      end
  
      if (bundle.deliverySrr?)
        sendDeliverySrr(bundle)
      end
      
      if (bundle.forwardingSrr?)
        sendForwardingSrr(bundle)
      end
      
      if (bundle.receptionSrr?)
        sendReceptionSrr(bundle)
      end
      
      if (bundle.requestCustody?)
        # Did we accept custody for this bundle
        if (bundle.custodyAccepted?)
          # If an acceptance sr is also requested, don't send an custody acceptance sr
          sendCustodyAcceptanceSr(bundle) unless bundle.receptionSrr?
        end
      end
      
      self.state = :processed
    end
  
    def processDeletion(bundle)
      if (bundle.deletionSrr?)
        sendDeletionSrr(bundle)
      end
      
      self.state = :deleted
    end
    
    def sendCustodyAcceptanceSr(bundle)
        
      # generate reception SR
      bdsr = BundleStatusReport.new
      bdsr.reasonCode = BundleStatusReport::REASON_NO_ADDTL_INFO
      if (bundle.fragment?)
        bdsr.fragment = true
        bdsr.fragmentOffset = bundle.fragmentOffset
        bdsr.fragmentLength = bundle.aduLength
      end
  
      bdsr.custodyAccepted = true
      bdsr.custAcceptTime = (RdtnTime.now - Time.gm(2000)).to_i
      bdsr.creationTimestamp = bundle.creationTimestamp
      bdsr.creationTimestampSeq = bundle.creationTimestampSeq
      bdsr.eidLength = bundle.srcEid.to_s.length
      bdsr.srcEid = bundle.srcEid.to_s
      
      b = Bundling::Bundle.new(bdsr.to_s)
      if (bundle.reportToEid.to_s != "dtn:none")
        b.destEid = bundle.reportToEid
      else
        b.destEid = bundle.srcEid
      end
  
      b.administrative = true
      b.lifetime = bundle.lifetime
  
      rdebug("SND: custody acceptance status report to #{b.destEid}")
      @evDis.dispatch(:bundleToForward, b)
    end
    
    def sendDeletionSrr(bundle)
      # generate deletion SR
      bdsr = BundleStatusReport.new
      bdsr.reasonCode = BundleStatusReport::REASON_NO_ADDTL_INFO
      if (bundle.fragment?)
        bdsr.fragment = true
        bdsr.fragmentOffset = bundle.fragmentOffset
        bdsr.fragmentLength = bundle.aduLength
      end
  
      bdsr.bundleDeleted = true
      bdsr.deletionTime = (RdtnTime.now - Time.gm(2000)).to_i
      
      bdsr.creationTimestamp = bundle.creationTimestamp
      bdsr.creationTimestampSeq = bundle.creationTimestampSeq
      bdsr.eidLength = bundle.srcEid.to_s.length
      bdsr.srcEid = bundle.srcEid.to_s
  
      b = Bundling::Bundle.new(bdsr.to_s)
      if (bundle.reportToEid.to_s != "dtn:none")
        b.destEid = bundle.reportToEid
      else
        b.destEid = bundle.srcEid
      end
  
      b.administrative = true
      b.lifetime = bundle.lifetime
  
      rdebug("SND: bundle deletion status report to #{b.destEid}")
  
      @evDis.dispatch(:bundleToForward, b)
    end
    
    def sendReceptionSrr(bundle)
        
      # generate reception SR
      bdsr = BundleStatusReport.new
      bdsr.reasonCode = BundleStatusReport::REASON_NO_ADDTL_INFO
      if (bundle.fragment?)
        bdsr.fragment = true
        bdsr.fragmentOffset = bundle.fragmentOffset
        bdsr.fragmentLength = bundle.aduLength
      end
  
      bdsr.bundleReceived = true
      bdsr.receiptTime = (RdtnTime.now - Time.gm(2000)).to_i
      
      # Notify as well if custody was accepted
      if (bundle.requestCustody? && bundle.custodyAccepted?)
        bdsr.custodyAccepted = true
        bdsr.custAcceptTime = (RdtnTime.now - Time.gm(2000)).to_i
      end
      
      bdsr.creationTimestamp = bundle.creationTimestamp
      bdsr.creationTimestampSeq = bundle.creationTimestampSeq
      bdsr.eidLength = bundle.srcEid.to_s.length
      bdsr.srcEid = bundle.srcEid.to_s
  
      b = Bundling::Bundle.new(bdsr.to_s)
      if (bundle.reportToEid.to_s != "dtn:none")
        b.destEid = bundle.reportToEid
      else
        b.destEid = bundle.srcEid
      end
  
      b.administrative = true
      b.lifetime = bundle.lifetime
  
      rdebug("SND: bundle reception status report to #{b.destEid}")
  
      @evDis.dispatch(:bundleToForward, b)
    end
  
    def sendForwardingSrr(bundle)
      h = @evDis.subscribe(:bundleForwarded) do |bndl, link, action|
        
        # generate forwarding SR
        bdsr = BundleStatusReport.new
        bdsr.reasonCode = BundleStatusReport::REASON_NO_ADDTL_INFO
        if (bundle.fragment?)
          bdsr.fragment = true
          bdsr.fragmentOffset = bundle.fragmentOffset
          bdsr.fragmentLength = bundle.aduLength
        end
  
        bdsr.bundleForwarded = true
        bdsr.forwardingTime = (RdtnTime.now - Time.gm(2000)).to_i
        bdsr.creationTimestamp = bundle.creationTimestamp
        bdsr.creationTimestampSeq = bundle.creationTimestampSeq
        bdsr.eidLength = bundle.srcEid.to_s.length
        bdsr.srcEid = bundle.srcEid.to_s
  
        b = Bundling::Bundle.new(bdsr.to_s)
        if (bundle.reportToEid.to_s != "dtn:none")
          b.destEid = bundle.reportToEid
        else
          b.destEid = bundle.srcEid
        end
  
        b.administrative = true
        b.lifetime = bundle.lifetime
  
        rdebug("SND: bundle forwarding status report to #{b.destEid}")
  
        # prevent nasty loops
        @evDis.unsubscribe(:bundleForwarded, h)
  
        @evDis.dispatch(:bundleToForward, b)
      end
    end
    
    def sendDeliverySrr(bundle)
      h = @evDis.subscribe(:bundleForwarded) do |bndl, link, action|
        # was the bundle delivered to an app?
        if ((link.kind_of? AppIF::AppProxy) && (bundle.bundleId == bndl.bundleId))
          # generate delivery SR
  
          bdsr = BundleStatusReport.new
          bdsr.reasonCode = BundleStatusReport::REASON_NO_ADDTL_INFO
          if (bundle.fragment?)
            bdsr.fragment = true
            bdsr.fragmentOffset = bundle.fragmentOffset
            bdsr.fragmentLength = bundle.aduLength
          end
  
          bdsr.bundleDelivered = true
          bdsr.deliveryTime = (RdtnTime.now - Time.gm(2000)).to_i
          bdsr.creationTimestamp = bundle.creationTimestamp
          bdsr.creationTimestampSeq = bundle.creationTimestampSeq
          bdsr.eidLength = bundle.srcEid.to_s.length
          bdsr.srcEid = bundle.srcEid.to_s
  
          b = Bundling::Bundle.new(bdsr.to_s)
          if (bundle.reportToEid.to_s != "dtn:none")
            b.destEid = bundle.reportToEid
          else
            b.destEid = bundle.srcEid
          end
          
          b.administrative = true
          b.lifetime = bundle.lifetime
  
          rdebug("SND: bundle delivery status report to #{b.destEid}")
  
          # prevent nasty loops
          @evDis.unsubscribe(:bundleForwarded, h)
  
          @evDis.dispatch(:bundleToForward, b)
        end
      end
    end
  
    def handleAdminRecord(bundle)
      administrativeRecord = AdministrativeRecord.parseBundle(bundle)
      # there are several cases we need to handle here
      
      if (administrativeRecord.bundleStatusReport?)
        # A "bundle reception status report" is a bundle status report with 
        # the "reporting node received bundle" flag set to 1.
        if (administrativeRecord.bundleReceived?)
          rdebug("RCV: bundle reception status report from #{bundle.srcEid}")
          
        end
        
        # A "custody acceptance status report" is a bundle status report
        # with the "reporting node accepted custody of bundle" flag set to 1.
        if (administrativeRecord.custodyAccepted?)
          rdebug("RCV: custody acceptance status report from #{bundle.srcEid}")
          bundle = @config.store.getBundle(administrativeRecord.bundleId)
          bundle.removeCustodyTimer
        end
        
        # A "bundle forwarding status report" is a bundle status report with
        # the "reporting node forwarded the bundle" flag set to 1.
        if (administrativeRecord.bundleForwarded?)
          rdebug("RCV: bundle forwarding status report from #{bundle.srcEid}")
        end
        
        # A "bundle delivery status report" is a bundle status report with
        # the "reporting node delivered the bundle" flag set to 1.
        if (administrativeRecord.bundleDelivered?)
          rdebug("RCV: bundle delivery status report from #{bundle.srcEid}")
        end
        
        # A "bundle deletion status report" is a bundle status report with
        # the "reporting node deleted the bundle" flag set to 1.
        if (administrativeRecord.bundleDeleted?)
          rdebug("RCV: bundle deletion status report from #{bundle.srcEid}")
        end
        
        if (administrativeRecord.ackedByApp?)
          rdebug("RCV: acked by app from #{bundle.srcEid}")
        end
        
        # rfc 5050 6.1.1 transmitted to the report-to endpoint TODO
      elsif (administrativeRecord.custodySignal?)
        rdebug("RCV: a custody signal arrived from #{bundle.srcEid}")
        # The "current custodian" of a bundle is the endpoint identified by
        # the current custodian endpoint ID in the bundle's primary block.
  
        # A "Succeeded" custody signal is a custody signal with the "custody
        # transfer succeeded" flag set to 1.
        if (administrativeRecord.transferSucceeded?)
          rdebug("RCV: transfer succeeded from #{bundle.srcEid}")
          bundle = @config.store.getBundle(administrativeRecord.bundleId)
          bundle.removeCustodyTimer
          # see rfc 5050 Section 5.11
        end
  
        # A "Failed" custody signal is a custody signal with the "custody
        # transfer succeeded" flag set to zero.
        if (!administrativeRecord.transferSucceeded?)
          rdebug("RCV: transfer failed from #{bundle.srcEid}")
          # see rfc 5050 Section 5.12
        end
      end  
    end
  end
  
  class Forwarder < TaskHandler

    def processBundle(bundle)
      @evDis.subscribe(:bundleForwarded) do |bndl, link, action|
	self.state = :processed if bundle.bundleId == bndl.bundleId
      end
      @evDis.dispatch(:bundleToForward, bundle)
    end

    def processDeletion(bundle)
      self.state = :deleted
    end

  end
  
end # module Bundling

class WorkflowTaskReg

  include Singleton

  attr_accessor :tasks

  def initialize
    @tasks = []
  end

  def regTask(runlevel, klass)

    @tasks.push([runlevel, klass]) unless @tasks.find {|rl, k| rl == runlevel}
  end

  def makeTasks(config, evDis, bundle)
    @tasks = @tasks.sort_by {|task| task[0]}
    @tasks.map {|rl, klass| klass.new(config, evDis, bundle)}
  end

end

def regWFTask(runlevel, klass)
  WorkflowTaskReg.instance.regTask(runlevel, klass)
end

regWFTask(10, Bundling::StoreHandler)
regWFTask(20, Bundling::ReassemblyHandler)
regWFTask(30, Bundling::CustodyHandler)
regWFTask(40, Bundling::AdminRecHandler)
regWFTask(50, Bundling::Forwarder)
