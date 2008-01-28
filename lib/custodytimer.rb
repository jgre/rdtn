require 'rdtnevent'
require 'monitor'
require 'singleton'
require 'configuration'
require 'clientlib'

class CustodyTimer
  
  include Singleton
  
  @monitor = nil
  
  def registerEvents
    @timer = EventDispatcher.instance.subscribe(:timerTick) do
      @monitor.synchronize do
        cBundles = @store.getBundlesMatching {|b| b.custodyAccepted? == true}
        cBundles.each { |b| rdebug(self, "CT resending #{b.bundleId} has custody? #{b.custodyAccepted?}")}
        cBundles.each { |b| EventDispatcher.instance.dispatch(:bundleToForward, b)}
      end
    end
  end
  
  def initialize
    @custodyBundles = []
    @timer = nil
    @monitor = Monitor.new
    @store = RdtnConfig::Settings.instance.store
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
    EventDispatcher.instance.unsubscribe(:timerTick, @timer)
  end
end