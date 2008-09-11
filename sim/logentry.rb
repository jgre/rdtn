module Sim

  class LogEntry

    attr_accessor :time, :eventId, :nodeId1, :nodeId2

    def initialize(time, eventId, nodeId1, nodeId2 = nil, options = {})
      @time = time
      @eventId = eventId
      @nodeId1 = nodeId1
      @nodeId2 = nodeId2

      options.each do |key, val| 
        instance_variable_set('@' + key.to_s, val)
        self.class.class_eval {attr_accessor key}
      end
    end

  end

end
