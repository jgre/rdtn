require 'configuration'

class Cache

  attr_accessor :limit, :replacementPolicy
  attr_reader   :size

  def initialize(config, evDis)
    @config = config
    @evDis  = evDis
    @cache  = {}
    @metadata = {}
    @config.registerComponent :cache, self
    @size = 0
    @replacementPolicy = :lru
    @stats = {}
  end

  def [](uri)
    content(uri)
  end

  def content(uri, revision = nil)
    if @cache.key? uri
      revision = currentRevision(uri) if revision.nil?
      @cache[uri][revision]
    end
  end

  def metadata(uri, revision = nil)
    if @metadata.key? uri
      revision = currentRevision(uri) if revision.nil?
      @metadata[uri][revision]
    end
  end

  def currentRevision(uri)
    sorted_revs = @cache[uri].sort_by(&:first).last.first if @cache.key? uri
  end

  def addContent(uri, content, revision, metadata = {})
    return if @limit and content.bytesize > @limit

    compact if @limit and ((@size + content.bytesize) > @limit)

    while @limit and ((@size + content.bytesize) > @limit)
      deleteByPolicy!
    end

    (@cache[uri] ||= {})[revision]    = content
    (@metadata[uri] ||= {})[revision] = metadata
    @size += content.bytesize
    @evDis.dispatch(:contentCached, uri, revision, content)
    if lifetime = metadata[:lifetime]
      RdtnTime.schedule(lifetime) {delete uri if revision == currentRevision(uri); false}
    end
  end

  def contentUsed(uri)
    (@stats[uri] ||= []) << RdtnTime.now
  end

  def delete(uri)
    #puts "(#{@config.localEid}) deleting #{uri} #{currentRevision(uri)}"
    @evDis.dispatch(:contentUncached, uri, currentRevision(uri), content(uri))
    @size -= content(uri).bytesize
    @cache.delete(uri)
    @metadata.delete(uri)
  end

  def deleteByPolicy!
    # puts "Deleting by policy #@size"
    del = self.send(@replacementPolicy) || @cache.keys.first
    delete del
  end

  def popularity
    @cache.keys.sort_by {|uri| @stats[uri].nil? ? 0 : @stats[uri].length}.first
  end

  def lru
    @cache.keys.sort_by {|uri| @stats[uri].nil? ? 0 : @stats[uri].last.to_i}.first
  end

  def compact
    @cache.values.each do |revisions|
      old_revs = revisions.keys.sort[0..-2]
      old_revs.each do |rev|
        @size -= revisions[rev].bytesize
        revisions.delete(rev)
      end
    end
  end
  
end
