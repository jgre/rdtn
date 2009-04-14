class StatSubscription

  def initialize
    @intervals = []
  end

  def subscribe(time)
    @intervals << [time, nil]
  end

  def unsubscribe(time)
    @intervals.last[1] = time
  end

  def overlap?(startTime, endTime)
    @intervals.any? {|t0, te| (te.nil? || startTime <= te) && (endTime.nil? || endTime >= t0)}
  end
    
end
