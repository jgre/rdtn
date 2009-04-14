require 'configuration'

class Cache

  def initialize(config, evDis)
    @config = config
    @evDis  = evDis
    @cache  = {}
    @config.registerComponent :cache, self
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

  def currentRevision(uri)
    sorted_revs = @cache[uri].sort_by(&:first).last.first if @cache.key? uri
  end

  def addContent(uri, content, revision)
    #puts "(#{@config.localEid}: #{RdtnTime.now.sec}) caching #{uri}: #{revision}"
    (@cache[uri] ||= {})[revision]  = content
  end

  def delete(uri)
    @cache.delete(uri)
  end
  
end
