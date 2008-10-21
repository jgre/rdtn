$:.unshift File.join(File.dirname(__FILE__), '..')
$:.unshift File.join(File.dirname(__FILE__), '..', 'stats')

require 'rubygems'
require 'test/unit'
require 'shoulda'
require 'core'
require 'networkmodel'
require 'trafficmodel'

module Sim

  module MaidenVoyage

    def self.included(hostclass)
      hostclass.extend(ClassMethods)
    end

    module ClassMethods

      def simulation_context(name, &blk)
        if Thoughtbot::Shoulda.current_context
          Thoughtbot::Shoulda.current_context.context(name, &blk)
        else
          context = Sim::MaidenVoyage::Context.new(name, self, &blk)
          context.build
        end
      end

    end

    class << self
      attr_accessor :sim, :network_model, :traffic_model

      def method_missing(name, *args, &block)
        if name.to_s[-1].chr == '='
          attr_name = name.to_s[0..-2]
          instance_variable_set("@#{attr_name}", *args)
        else
          instance_variable_get("@#{name}")
        end
      end
    end

    def sim
      MaidenVoyage.sim
    end

    def network_model
      MaidenVoyage.network_model
    end

    def traffic_model
      MaidenVoyage.traffic_model
    end

    def method_missing(*args, &block)
      MaidenVoyage.send(*args, &block)
    end

    class Context < Thoughtbot::Shoulda::Context

      attr_accessor :prepare_blocks, :network, :workload
      attr_reader   :sim, :network_model, :traffic_model, :sim_run

      def initialize(name, parent, &blk)
        self.prepare_blocks = []
        self.network        = nil
        self.workload       = nil
        @sim_run            = false
        @sim                = nil
        super
      end

      def prepare(&blk)
        self.prepare_blocks << blk
      end

      def network(name)
        self.network = name
      end

      def workload(name)
        self.workload = name
      end

      def run_simulation(binding)
        MaidenVoyage.sim = sim = Sim::Core.new

        if @network
          dir = File.join(File.dirname(__FILE__), '../../test/network_fixtures')
          g = Sim::Graph.new
          g.instance_eval(File.read(File.join(dir, @network.to_s + '.rb')))
          sim.events = g.events
        end

        if @workload
          dir = File.join(File.dirname(__FILE__),'../../test/workload_fixtures')
          sim.instance_eval(File.read(File.join(dir, @workload.to_s + '.rb')))
        end

        prepare_blocks.each do |prep_blk|
          prep_blk.bind(binding).call
        end

        events, tm   = sim.run
        @sim_run     = true
        MaidenVoyage.network_model = NetworkModel.new(events)
        MaidenVoyage.traffic_model = tm
      end

      def create_test_from_should_hash(should)
        test_name = ["test:", full_name, "should", "#{should[:name]}. "].flatten.join(' ').to_sym

        if test_unit_class.instance_methods.include?(test_name.to_s)
          warn "  * WARNING: '#{test_name}' is already defined"
        end
 
        context = self
        test_unit_class.send(:define_method, test_name) do
          begin
            context.run_simulation(self) unless context.sim_run

            context.run_parent_setup_blocks(self)
            should[:before].bind(self).call if should[:before]
            context.run_current_setup_blocks(self)
            should[:block].bind(self).call
          ensure
            context.run_all_teardown_blocks(self)
          end
        end
      end

    end

  end

end

module Test
  module Unit
    class TestCase
      include Sim::MaidenVoyage
    end
  end
end
