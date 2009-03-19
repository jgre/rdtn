$:.unshift File.join(File.dirname(__FILE__), '../../sim/stats')

require 'networkmodel'

describe NetworkModel do

  before(:each) do
    @events = Sim::EventQueue.new
    @events.addEvent(1, 1, 2, :simConnection)
    @events.addEvent(2, 2, 3, :simConnection)
    @events.addEvent(3, 2, 3, :simDisconnection)
    @events.addEvent(4, 1, 2, :simDisconnection)

    @net = NetworkModel.new(@events)
  end

  it 'should contain the nodes from the event queue' do
    @net.nodes.sort.should == [1, 2, 3]
  end

  it 'should calculate the degree of nodes' do
    @net.degree(1).should == 1
    @net.degree(2).should == 2
    @events.addEvent(5, 2, 3, :simConnection)
    @net = NetworkModel.new(@events)
    @net.degree(2).should == 3
  end

  it 'should calculate the neighbors per node' do
    @net.neighbors(1).length.should == 1
    @net.neighbors(2).length.should == 2
    @events.addEvent(5, 2, 3, :simConnection)
    @net = NetworkModel.new(@events)
    @net.neighbors(2).length.should == 2
  end

  it 'should calculate the number of contacts' do
    @net.numberOfContacts.should == 2
  end

  it 'should calculate the total contact duration' do
    @net.totalContactDuration.should == 4
    @net.contactDurations.inject{|sum, dur| sum + dur}.should == 4
  end

  it 'should calculate the average contact duration' do
    @net.averageContactDuration.should == 2
  end

  it 'should count unique contacts' do
    @net.uniqueContacts.should == 2
  end

  it 'should calculate the total theoretical hop count' do
    @net.totalTheoreticalHopCount.should == 8
  end

  it 'should calculate the number of theoretical paths' do
    @net.numberOfTheoreticalPaths.should == 6
  end

  it 'should calculate the total theoretical delay' do
    @net.totalTheoreticalDelay.should == 10
  end

  it 'should calculate the average theoretical hop count' do
    @net.averageTheoreticalHopCount.should == 8.0 / 6.0
  end

  it 'should calculate the average theoretical delay' do
    @net.averageTheoreticalDelay.should == 10.0 / 6.0
  end

  xit 'should calculate the clustering coefficient for each node' do
    @net.clusteringCoefficient(1).should == 1
    @net.clusteringCoefficient(2).should == 1
    @net.clusteringCoefficient(3).should == 1
  end

  xit 'should calculate the total clustering coefficient for each node' do
    @net.totalClusteringCoefficient.should == 1
  end

  it 'should calculate the average degree' do
    @net.averageDegree.should == 4.0 / 3.0
  end

  it 'should return the length of the simulation' do
    @net.duration.should == 4
  end

end
