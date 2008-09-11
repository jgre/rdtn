$:.unshift File.join(File.dirname(__FILE__), "..", "..", "..", "lib")
$:.unshift File.join(File.dirname(__FILE__), "..", "..")

require 'rdtnevent'
require 'eventqueue'

# 11MBit/s (IEEE802.11b) in bytes/s
RATE = (11 * 10**6 / 8).to_f

class DieselNetParser

  attr_reader :events

  def initialize(duration, granularity, options)
    @duration    = duration
    @granularity = granularity
    @events      = Sim::EventQueue.new
    open(options["tracefile"]) {|f| process(f)} if options.has_key?("tracefile")
  end

  private

  def process(file)
    puts "Processing DieselNet data..."
    t0 = nil
    file.each do |line|
      if /(\d+) (\d+) (\d+) (\d+)/ =~ line
        node1 = $1.to_i
        node2 = $2.to_i
        time  = $3.to_i
        bytes = $4.to_i

        # Adjust the time to start with 0
        t0  ||= time
        time -= t0
        # The events must be added in chronological order, as disconnections of
        # earlier events may happen later than following connection events.
        @events.addEventSorted(time, node1, node2, :simConnection)

        # Calculate the end time based on the number of bytes transmitted,
        # assuming a constant data rate of 11MBit/s = 1375000 bytes/s
        end_time = time + (bytes / RATE).ceil
        @events.addEventSorted(end_time, node1, node2, :simDisconnection)
      end
    end
    puts "Processing done."
  end

end
