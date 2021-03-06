require 'rdtnevent'
require 'monitor'
require 'configuration'
require 'clientlib'

class CustodyTimer
  
  attr_accessor :interval
  
  def initialize(bundle, evDis, interval = 10)
    @evDis  = evDis 
    @timer = []
    @bundle = bundle
    @interval = interval
    @bundle.setCustodyTimer(self)
    
    @h = @evDis.subscribe(:bundleForwarded) do |bndl, link, action|
      if(bndl.bundleId == @bundle.bundleId) then
        @timer += Thread.new do
            sleep(@interval)
	    @bundle.forwardLog.updateEntry(action, :transmissionError,
					   link.remoteEid, link)
	    @evDis.dispatch(:transmissionError, @bundle, link)
        end
      end
    end
  end
  
  def stop
    rdebug("Stopping CustodyTimer")
    @evDis.unsubscribe(:bundleForwarded, @h)
    @timer.each do |timer|
      if (timer.alive?) then  
        timer.kill
      end
    end
  end
end
