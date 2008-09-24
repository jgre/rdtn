$: << File.join(File.dirname(__FILE__), '..', 'lib')

require 'test/unit'
require 'rubygems'
require 'shoulda'
require 'epidemicrouter'
require 'daemon'

module TestEpidemic
  class MockLink < Link
    attr_accessor :remoteEid, :bundles

    def initialize(config, evDis, eid)
      super(config, evDis)
      @bundles   = []
      @remoteEid = eid
      @evDis.dispatch(:linkOpen, self)
    end

    def sendBundle(bundle)
      @bundles.push(bundle)
    end

    def close
    end

    def received?(bundle)
      @bundles.any? {|b| b.to_s == bundle.to_s}
    end

  end
end

class TestEpidemicRouter < Test::Unit::TestCase

  def setup
    @daemon = RdtnDaemon::Daemon.new("dtn://receiver.dtn/")
    @store  = @daemon.config.store
    @daemon.router(:epidemic)
  end
  
  context 'When bundles are stored, the EpidemicRouter' do

    setup do
      @bundles = (0..10).map do |i|
        Bundling::Bundle.new("test#{i}", 'dtn://someoneelse')
      end
      @bundles.each {|b| @store.storeBundle(b)}
    end

    should 'send all bundles to new contacts' do
      eid  = "dtn://peer.dtn/"
      link = TestEpidemic::MockLink.new(@daemon.config, @daemon.evDis, eid)
      @bundles.each {|b| assert link.received?(b)}
    end

  end

  context 'When contacts are established, the EpidemicRouter' do

    setup do
      @links = (0..10).map do |i|
        eid  = "dtn://peer#{i}.dtn/"
        l = TestEpidemic::MockLink.new(@daemon.config, @daemon.evDis, eid)
      end
    end

    should 'send incoming bundles to all existing links' do
      bundle = Bundling::Bundle.new('test', 'dtn://someoneelse.dtn/')
      @daemon.sendBundle(bundle)

      @links.each {|link| assert link.received?(bundle)}
    end

  end

  context 'With local registrations, the EpidemicRouter' do

    setup do
      @rec = nil
      @daemon.register {|b| @rec = b}
    end

    should 'deliver bundles to local registrations' do
      bundle = Bundling::Bundle.new('test', 'dtn://receiver.dtn/')
      @daemon.sendBundle(bundle)
      assert @rec
      assert_equal bundle, @rec
    end
    
    should 'not deliver bundle to the wrong local registrations' do
      bundle = Bundling::Bundle.new('test', 'dtn://someoneelse.dtn/')
      @daemon.sendBundle(bundle)
      assert_nil @rec
    end

    should 'continue flooding, when the bundle has a multicast destination' do
      bundle = Bundling::Bundle.new('test', 'dtn://receiver.dtn/', nil,
                                   :multicast => true)
      @daemon.sendBundle(bundle)

      l = TestEpidemic::MockLink.new(@daemon.config,@daemon.evDis,'dtn://peer')
      assert l.received?(bundle)
    end

    should 'stop flooding when a singleton endpoint has been reached' do
      bundle = Bundling::Bundle.new('test', 'dtn://receiver.dtn/')
      @daemon.sendBundle(bundle)

      l = TestEpidemic::MockLink.new(@daemon.config,@daemon.evDis,'dtn://peer')
      assert !l.received?(bundle)
    end

    should 'deliver stored bundles when local registration are added' do
      bundle = Bundling::Bundle.new('test', 'dtn://someoneelse.dtn/')
      @daemon.sendBundle(bundle)

      assert_nil @rec
      @daemon.register('dtn://someoneelse.dtn/') {|b| @rec = b}
      assert @rec
      assert_equal bundle, @rec
    end

    should 'not flood stored bundles to new local registrations' do
      bundle = Bundling::Bundle.new('test', 'dtn://someoneelse.dtn/')
      @daemon.sendBundle(bundle)

      assert_nil @rec
      @daemon.register('dtn://thewrongplace.dtn/') {|b| @rec = b}
      assert_nil @rec
    end

  end

  context 'Vaccination bundles' do

    setup do
      @bundle = Bundling::Bundle.new('test', 'dtn://dest', 'dtn://source')
      @vacc   = Vaccination.new(@bundle).vaccinationBundle
    end

    should 'be addressed to the source of the original bundle' do
      assert_equal @bundle.srcEid, @vacc.destEid
    end

    should 'encode the identification of the original bundle in the payload' do
      id = "#{@bundle.srcEid}-#{@bundle.creationTimestamp}-#{@bundle.creationTimestampSeq}-#{@bundle.fragmentOffset}"
      assert_equal id, @vacc.payload
    end

    should 'have a metadata-block that identifies them as vaccination' do
      md = @vacc.findBlock(MetadataBlock)
      assert md

      assert_equal :contentType, md.ontologySymbol
      assert_equal Vaccination::ContentType, md.metadata
    end

    should 'be recognized' do
      assert @vacc.isVaccination?
      assert !@bundle.isVaccination?
    end

    should 'be parsed' do
      v = Vaccination.new(@vacc)
      assert_equal @bundle.bundleId, v.bundleId
    end

  end

  context 'When vaccination is enabled, the EpidemicRouter' do

    setup do
      @daemon.router(:epidemic, :vaccination => true)
      @daemon.register {}
      @vacc = nil
      @daemon.evDis.subscribe(:bundleParsed) {|b| @vacc = b if b.isVaccination?}
    end

    should 'create vaccination bundles when a local registration is the only destination' do
      bundle = Bundling::Bundle.new('test', 'dtn://receiver.dtn/')
      @daemon.sendBundle(bundle)
      assert @vacc
      assert_equal bundle.bundleId, Vaccination.new(@vacc).bundleId
    end

    should 'not create vaccination bundles for multicast bundles' do
      bundle = Bundling::Bundle.new('test', 'dtn://receiver.dtn/', nil,
                                   :multicast => true)
      @daemon.sendBundle(bundle)
      assert_nil @vacc
    end

    should 'not create vaccination bundles on transit bundles' do
      bundle = Bundling::Bundle.new('test', 'dtn://someoneelse.dtn/', nil,
                                   :multicast => true)
      @daemon.sendBundle(bundle)
      assert_nil @vacc
    end

    should 'delete bundles from storage when vaccinations are received' do
      bundle = Bundling::Bundle.new('test', 'dtn://someoneelse.dtn/')
      @store.storeBundle(bundle)

      assert @store.find {|b| b.bundleId == bundle.bundleId}

      @daemon.sendBundle(Vaccination.new(bundle).vaccinationBundle)

      assert_nil @store.find {|b| b.bundleId == bundle.bundleId}
    end

  end

end
