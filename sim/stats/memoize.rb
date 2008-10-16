module Memoize

  def remember(name, &block)
    memory = {}

    define_method(name, &block)
    meth = instance_method(name)

    define_method(name) do |*args|
      if memory.has_key?(args)
        memory[args]
      else
        memory[args] = meth.bind(self).call(*args)
      end
    end
  end

end
