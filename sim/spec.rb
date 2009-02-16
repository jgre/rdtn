require 'combinationhash'
require 'rubygems'
#require 'ruby2ruby'

module Sim

  class Specification

    attr_accessor :cur_variant, :vars, :selected, :var_idx

    def initialize(var_idx = nil)
      @dry_run     = false
      @template    = {} # a hash of lists with all possible values
      @vars        = [] # a list of hashes with each combination of values
      @cur_variant = nil
      @var_idx     = var_idx
      @selected    = {}
    end

    def name
      "#{self.class}-#@var_idx-#{Time.now.strftime('%Y%m%d-%H%M%S')}"
    end

    def dry_run
      @dry_run = true
      execute(Sim::Core.new)
      @vars    = Sim.hash_combinations(@template)
      @dry_run = false
    end

    def variants(id, *vars)
      if @dry_run
        @template[id] = (0..vars.length-1)
        var = vars.first
      else
        var = @cur_variant ? vars[@cur_variant[id]] : vars.first
      end
      case var
      when Proc
	@selected[id] = var.respond_to?(:to_ruby) ? var.to_ruby : ret
	var.call
      when Array
	@selected[id] = var # store both the value and the description for evaluations.
	var[0] # return the value of a [value, description] pair
      else
	@selected[id] = var
      end
    end

    def self.createVariants
      template = new
      template.dry_run
      idx = -1
      template.vars.map {|var| spec = new(idx+=1); spec.cur_variant = var; spec}
    end

    SPECDIR = File.join(File.dirname(__FILE__), '../simulations/specs')

    def self.loadSpec(spec)
      require File.join(SPECDIR, spec.to_s.downcase)
      Module.const_get(spec)
    end

  end

end
