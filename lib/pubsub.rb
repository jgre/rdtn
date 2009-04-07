require 'daemon'
require 'bundle'
require 'ccnblock'

module PubSub

  def self.publish(daemon, uri, data, options = {})
    bundle = Bundling::Bundle.new data
    bundle.addBlock CCNBlock.new(bundle, uri, :publish)
    daemon.sendBundle bundle
  end

  def self.delete(daemon, uri)
    bundle = Bundling::Bundle.new
    bundle.addBlock CCNBlock.new(bundle, uri, :delete)
    daemon.sendBundle bundle    
  end

  #def self.post(daemon, uri, data, options = {})
  #end
  
  def self.subscribe(daemon, uri, options = {}, &handler)
    # The state about local subscriptions is kept in a hash that is
    # registered as a component
    unless daemon.config.component(:localSubs)
      daemon.config.registerComponent :localSubs, {}
      daemon.register {|bundle| deliver(daemon, bundle)}
    end
    
    daemon.config.localSubs[uri] = handler

    sub_bundle = Bundling::Bundle.new nil, "dtn:internet-gw/"
    sub_bundle.addBlock CCNBlock.new(sub_bundle, uri, :subscribe)
    daemon.sendBundle sub_bundle
  end

  def self.unsubscribe(daemon, uri)
    daemon.config.localSubs.delete(uri)
  end

  def self.deliver(daemon, bundle)
    if ccn_blk = bundle.findBlock(CCNBlock)
      localSubs = daemon.config.localSubs
      localSubs[ccn_blk.uri][bundle.payload] if localSubs.key? ccn_blk.uri
    end
  end
  
end # module
