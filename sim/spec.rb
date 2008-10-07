require 'combinationhash'

module Sim

  class DummyObject
    def method_missing(name, *args)
      self
    end

    def to_s
      ''
    end
  end

  class Specification

    attr_accessor :cur_variant, :vars

    def initialize(var_idx = nil)
      @dry_run     = false
      @template    = {} # a hash of lists with all possible values
      @vars        = [] # a list of hashes with each combination of values
      @cur_variant = nil
      @var_idx     = var_idx
    end

    def name
      "#{self.class}-#@var_idx-#{Time.now.strftime('%Y%m%d-%H%M%S')}"
    end

    def dry_run
      @dry_run = true
      execute(DummyObject.new)
      @vars    = Sim.hash_combinations(@template)
      @dry_run = false
    end

    def variants(id, *vars)
      if @dry_run
        @template[id] = vars
      else
        var = @cur_variant ? @cur_variant[id] : vars.first
        var.is_a?(Proc) ? var.call : var
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
