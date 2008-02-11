require 'rdtnevent'
require 'monitor'
require 'configuration'
require 'clientlib'

class CustodyTimer
  
  @monitor = nil
  
  def registerEvents
    @timer = @evDis.subscribe(:timerTick) do
      @monitor.synchronize do
        cBundles = @store.getBundlesMatching {|b| b.custodyAccepted? == true}
        cBundles.each { |b| rdebug(self, "CT resending #{b.bundleId} has custody? #{b.custodyAccepted?}")}
        cBundles.each { |b| @evDis.dispatch(:bundleToForward, b)}
      end
    end
  end
  
  def initialize(config, evDis)
    @config = config
    @evDis  = evDis
    @custodyBundles = []
    @timer = nil
    @monitor = Monitor.new
    @store = @config.store
    registerEvents
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
    @evDis.unsubscribe(:timerTick, @timer)
  end
end
