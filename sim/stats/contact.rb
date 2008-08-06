$:.unshift File.join(File.dirname(__FILE__), '..')
$:.unshift File.join(File.dirname(__FILE__))

class Contact

  attr_accessor :startTime, :endTime
  attr_reader   :node1, :node2

  def initialize(node1, node2, startTime)
    @node1     = node1
    @node2     = node2
    @startTime = startTime
  end

  def endContact(time)
    @endTime = time
  end

  def open?
    @startTime and @endTime.nil?
  end

  def duration
    return 0 if @startTime.nil? or open?
    @endTime - @startTime
  end

  def to_s
    "#{@node1} -> #{@node2}: #{@startTime} - #{@endTime}"
  end

  def cost(time)
    if time < @startTime
      @startTime - time
    elsif @endTime.nil? or time <= @endTime
      0
    else
      nil
    end
  end

end
