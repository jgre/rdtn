$:.unshift File.join(File.dirname(__FILE__), "..")
$:.unshift File.join(File.dirname(__FILE__), "../../lib")
$:.unshift File.join(File.dirname(__FILE__))

require 'bundle'
require 'ccnblock'

class ContentItem

  attr_accessor :uri, :created

  def initialize(bundle, statBundle)
    ccn_blk    = bundle.findBlock(CCNBlock)
    @uri       = ccn_blk.uri

    @creations = {} # rev -> creation timestamp
    @revisions = {} # rev -> {node -> [times]}
  end

  def revisionCreated(revision, time)
    @creations[revision] = time unless @creations.key? revision
  end

  def incident(node, revision, time)
    @creations[revision] = time unless @creations.key? revision
    ((@revisions[revision] ||= {})[node] ||= []) << time
    @revisions[revision][node].uniq!
  end

  def delivered?(node, subscription = nil, options = {})
    revision = options[:revision]
    if revision.nil?
      times = @revisions.values.inject([]) do |memo, incidents|
        memo + (incidents[node] || [])
      end
    else
      times = (@revisions[revision] || {})[node] || []
    end
    if subscription.nil?
      !times.empty?
    else
      subscription.overlap?(times.min, nil) unless times.empty?
    end
  end

  def delay(node, subscription = nil)
    ret = @revisions.map do |rev, incidents|
      if delivered?(node, subscription, :revision => rev)
        incidents[node].min - @creations[rev] if incidents.key? node
      end
    end
    ret.nil? ? [] : ret.flatten
  end

  def revisions
    @revisions.keys
  end

  def transmissions
    @revisions.values.inject(0) do |sum, incidents|
      sum + incidents.inject(0) {|s, node_times| s + node_times[1].length}
    end
  end
  
end
