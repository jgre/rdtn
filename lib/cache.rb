require 'configuration'

class Cache

  def initialize(config, evDis)
    @config = config
    @evDis  = evDis
    @cache  = {}
    @config.registerComponent :cache, self
  end

  def [](uri)
    @cache[uri]
  end

  def addContent(uri, content)
    @cache[uri] = content
  end

  def delete(uri)
    @cache.delete(uri)
  end
  
end
