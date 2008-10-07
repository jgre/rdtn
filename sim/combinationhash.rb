module Sim

  def Sim::hash_combinations(hash)
    iterate = lambda do |keys|
      key, *rest = keys
      unless key and (val = hash[key]).is_a?(Enumerable)
        hash[key] = [val]
      end
      if key
        hash[key].inject([]) do |ret,val|
          ret+iterate[rest].map {|h| h.merge({key=>val})}
        end
      else
        [{}]
      end
    end

    iterate[hash.keys]
  end

end
