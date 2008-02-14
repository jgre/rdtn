require 'rdtnevent'
require 'monitor'
require 'configuration'
require 'clientlib'

class CustodyTimer
  
  attr_accessor :interval
  
  @monitor = nil
  
  def startTimer
    @timer = Thread.new do
      while (@running) do
        sleep(@interval)
        @monitor.synchronize do
          cBundles = @store.getBundlesMatching {|b| b.custodyAccepted? == true}
          cBundles.each { |b| rdebug(self, "CT resending #{b.bundleId} has custody? #{b.custodyAccepted?}")}
          cBundles.each { |b| puts b } # TODO retransmit bundle here
        end
      end
    end
  end
  
  def initialize(config, evDis)
    @config = config
    @evDis  = evDis
    
    @timer = nil
    @running = true
    
    @monitor = Monitor.new
    @store = @config.store
    @interval = 10
    startTimer
  end
  
  def remove(bundleId)
    rdebug(self, "Removing #{bundleId} from CustodyTimer")
    @monitor.synchronize do
      bundle = @store.getBundleMatching {|b| b.bundleId == bundleId}
      bundle.custodyAccepted = false
    end
  end
  
  def stop
    # stop the timer
    rdebug(self, "Stopping CustodyTimer")
    @running = false
    @timer.join
  end
end
