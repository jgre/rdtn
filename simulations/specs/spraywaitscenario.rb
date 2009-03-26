require 'spraywaitrouter'

class SprayWaitScenario < Sim::Specification

  def execute(sim)
    sim.trace(:type => 'MITParser', :tracefile => "RWP-1-1000_ConnectivityDtnsim2Report.txt")
    limit = variants(:limit, 10, 50, 100)
    sim.nodes.router(:spraywait, :initial_copycount => limit)
    # sim.nodes.router(variants(:router,
    #                               [:spraywait, :initial_copycount => 10],
    #                               [:spraywait, :initial_copycount => 50],
    #                               [:spraywait, :initial_copycount => 100],
    #                               [:epidemic]))
                              
    sim.nodes.linkCapacity = (11 * 10**6 / 8).to_i
    sim.nodes.storage_limit = 1024**2*variants(:storage_limit, 10, 50, 256)

    data  = 'a' * 1024

    sim.nodes.each {|id, n| n.register {}}
    sim.at(1800) do |time|
      sender = rand(999)
      rec    = rand(999)
      rec += 1 if sender == rec
      sim.node("n#{sender + 1}").sendDataTo data, "dtn://kasuarin#{rec + 1}/", nil, :lifetime => 3600 * 6
      true
    end
  end

  def preprocess(variant, network, traffic)
    {:numberOfContacts          => network.numberOfContacts,
      :transmissions            => traffic.numberOfTransmissions,
      :transmissionsPerBundle   => traffic.transmissionsPerBundle,
      :contactDurations         => network.averageContactDuration,
      :numberOfBundles          => traffic.numberOfBundles,
      :numberOfExpectedBundles  => traffic.numberOfExpectedBundles,
      :numberOfDeliveredBundles => traffic.numberOfDeliveredBundles,
      :failedTransmissions      => traffic.numberOfTransmissionErrors,
      :delay                    => traffic.averageDelay,
      :maxTransmissionfPerBundle=> traffic.regularBundles.map(&:transmissions).max}
  end

  def analyze(preprocessed, dir)
    [:transmissionsPerBundle, :numberOfDeliveredBundles, :delay].each do |y|
      [:limit, :storage_limit].permutation(2).each do |x, enum|
        results = Analysis.aggregate preprocessed, :x_axis => x, :y_axis => y, :enumerate => [enum]
        Analysis.plot results, :x_axis => x, :y_axis => y, :dir => dir
      end
    end
    
  end
  
end
