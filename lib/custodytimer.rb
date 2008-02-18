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
    
    @h = @evDis.subscribe(:bundleForwarded) do |bndl, link|
      if(bndl.bundleId == @bundle.bundleId) then
        @timer += Thread.new do
            sleep(@interval)
            puts "should retransmit bundle #{@bundle} to #{link.remoteEid}"# retransmit bundle
        end
      end
    end
  end
  
  def stop
    rdebug(self, "Stopping CustodyTimer")
    @evDis.unsubscribe(:bundleForwarded, @h)
    @timer.each do |timer|
      if (timer.alive?) then  
        timer.kill
      end
    end
  end
end
