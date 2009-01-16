require 'router'
require 'bundle'
require 'rdtntime'

class EpidemicRouter < Router

  def initialize(config, evDis, options = {})
    super(config, evDis)
    @contMgr     = @config.contactManager
    @vaccination = options[:vaccination]

    @evToForward = @evDis.subscribe(:bundleToForward) do |b|
      if b.isVaccination? and store = @config.store
        vacc = Vaccination.new(b)
        store.deleteBundle(vacc.bundleId)
      end
      enqueue(b, @contMgr.links.find_all {|l| !l.is_a?(AppIF::AppProxy)},
                :replicate)
    end

    @evAvailable = @evDis.subscribe(:routeAvailable) do |rentry|
      if store = @config.store and !rentry.link.is_a?(AppIF::AppProxy)
        store.each {|b| enqueue(b, [rentry.link], :replicate)}
      end
    end
  end

  def stop
    super
    @evDis.unsubscribe(:routeAvailable, @evAvailable)
    @evDis.unsubscribe(:bundleToForward, @evToForward)
  end

  def localDelivery(bundle, links)
    super
    if @vaccination && bundle.destinationIsSingleton? && !bundle.isVaccination?
      @config.localSender.sendBundle(Vaccination.new(bundle).vaccinationBundle)
    end
  end

end

regRouter(:epidemic, EpidemicRouter)

class Vaccination

  ContentType = 'application/x-dtn-vaccination'

  attr_accessor :bundleId

  def initialize(bundle)
    if bundle.isVaccination?
      @bundleId = bundle.payload.hash
    else
      @origBundle = bundle
      @bundleId   = bundle.bundleId
    end
  end

  def vaccinationBundle
    id = "#{@origBundle.srcEid}-#{@origBundle.creationTimestamp}-#{@origBundle.creationTimestampSeq}-#{@origBundle.fragmentOffset}"
    vacc = Bundling::Bundle.new(id, @origBundle.srcEid)
    vacc.lifetime = @origBundle.expires - RdtnTime.now.to_i
    vacc.addBlock(MetadataBlock.new(vacc, ContentType, :contentType))
    vacc
  end
end

module Bundling
  class Bundle
    def isVaccination?
      (md = findBlock(MetadataBlock) and md.ontologySymbol == :contentType and
       md.metadata == Vaccination::ContentType)
    end
  end
end
