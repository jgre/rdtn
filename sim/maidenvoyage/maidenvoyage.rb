$:.unshift File.join(File.dirname(__FILE__), '..')
$:.unshift File.join(File.dirname(__FILE__), '..', 'stats')

require 'rubygems'
require 'test/unit'
require 'shoulda'
require 'core'
require 'networkmodel'

module Sim

  module MaidenVoyage

    def self.included(hostclass)
      hostclass.extend(ClassMethods)
    end

    module ClassMethods
      def prepare(&blk)
        Thoughtbot::Shoulda.current_context.setup do
          blk.bind(self).call
          event_log = sim.run
          @network_model = NetworkModel.new(event_log)
        end
      end

      def network(name)
        dir = File.join(File.dirname(__FILE__), '../../test/network_fixtures')
        Thoughtbot::Shoulda.current_context.setup do
          g = Sim::Graph.new
          g.instance_eval(File.read(File.join(dir, name.to_s + '.rb')))
          sim.events = g.events
          sim.createNodes(g.nodes.length)
        end
      end
    end

    def sim
      @sim ||= Sim::Core.new
    end

    attr_reader :network_model, :traffic_model

  end

end

module Test
  module Unit
    class TestCase
      include Sim::MaidenVoyage
    end
  end
end
