$:.unshift File.join(File.dirname(__FILE__), "..")
$:.unshift File.join(File.dirname(__FILE__))


class SummaryReport

  def initialize(model)
    @model = model
  end

  def printGlobalInformation(file)
    file.puts("#{@model.numberOfContacts} contacts")
    file.puts("#{@model.uniqueContacts} contacts between unique pairs of nodes")
    file.puts("#{@model.averageContactDuration} avarage contact duration")
    file.puts("#{@model.numberOfBundles} bundles created")
    file.puts("#{@model.numberOfSubscribedBundles} bundles subscribed")
    file.puts("#{@model.numberOfDeliveredBundles} bundles delivered (#{(@model.numberOfDeliveredBundles.to_f / @model.numberOfSubscribedBundles) * 100}%)")
    file.puts("#{@model.numberOfReplicas} replicas")
    file.puts("#{@model.replicasPerBundle} replicas per bundle")
    file.puts("#{@model.numberOfTransmissions} bundle transmissions")
    file.puts("#{@model.transmissionsPerBundle} transmissions per bundle")
    file.puts("#{@model.averageDelay} seconds avarage delay")
    file.puts("#{@model.numberOfControlBundles} subscription bundles (#{@model.controlOverhead} bytes)")
    file.puts
    file.puts("#{@model.totalClusteringCoefficient} clustering coefficient")
    file.puts("#{@model.averageDegree} average degree")
    file.puts("#{@model.averageTheoreticalHopCount} average theoretical hop count")
  end

  def printContacts(dirName)
    @model.contacts.each_value do |contHist|
      open(File.join(dirName, "contact#{contHist.id}.stat"), "w") do |file|
        contHist.print(file)
        file.puts
        file.puts
      end
    end
  end

  def printGraphviz(dirName)
    open(File.join(dirName,"contactgraph.dot"),"w") do |f|
      f.puts("graph contactgraph {")
      @model.contacts.each_value do |contHist|
        f.puts("#{contHist.nodeId1} -- #{contHist.nodeId2}")
      end
      f.puts("}")
    end
    system("dot -Tpng " + File.join(dirName,"contactgraph.dot") + "> " + File.join(dirName,"contactgraph.png"))

    @model.bundles.each do |bundleId, bundle|
      bundleName = "bundle#{bundle.dest}_#{bundleId}".sub("-", "_")
      open(File.join(dirName,"#{bundleName}.stat"),"w") do |f|
        f.puts(bundle.to_s)
        bundle.print(f)
        f.puts
      end
      open(File.join(dirName,"#{bundleName}.dot"),"w") do |f|
        f.puts("digraph #{bundleName} {")
        @contacts.each_value do |contHist|
          contHist.printGraphviz(f, bundleId)
        end
        f.puts("}")
      end
      system("dot -Tpng " + File.join(dirName,"#{bundleName}.dot") + "> " + File.join(dirName,"#{bundleName}.png"))
    end
  end

end

class PathReport

  def initialize(model)
    @model = model
  end

  def printPathReport(file)
    @model.bundles.values.each do |bundle|
      file.puts("#{bundle}, created #{bundle.created}")
      distVec, path = dijkstra(@model, bundle.src, bundle.created)
      bundle.subscribers.each do |subs|
	file.puts("Delivered to #{subs} after #{bundle.deliveryDelay(subs)} sec (ideally: #{distVec[subs]} sec: [#{path[subs].join(', ')}])")
      end
      file.puts
    end
  end

end

class NetworkAnalysisReport

  def initialize(model)
    @model = model
  end

  def printNetworkAnalysis(file, range, step)
    file.puts("Calculated #{@model.numberOfTheoreticalPaths} paths")
    file.puts("Average path length: #{@model.averageTheoreticalHopCount} hops")
    file.puts("Average delay: #{@model.averageTheoreticalDelay} sec")
  end

end

