module Memoize

  def remember(name, &block)
    memory = {}

    meth = instance_method(name)

    define_method(name) do |*args|
      id = args + [self]
      if memory.has_key?(id)
        memory[id]
      else
        memory[id] = meth.bind(self).call(*args)
      end
    end
  end

end
