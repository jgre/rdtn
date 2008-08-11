module Sim

  def self.traceParser(duration, granularity, options)
    type      = options['type']
    pluginDir = File.join(File.dirname(__FILE__), 'plugins/trace-parsers')
    load File.join(pluginDir, type.downcase + '.rb')
    parser    = Module.const_get(type).new(duration, granularity, options)

    events = parser.events
    if fname = options["tracefile"]
      open(fname + ".rdtnsim", "w") {|f| Marshal.dump(events, f)}
    end
    events
  end

end

if $0 == __FILE__
  require 'optparse'

  duration = granularity = type = tracefile = nil
  opt = OptionParser.new
  opt.on("-d", "--duration DUR", "trace duration") {|d| duration = d}
  opt.on("-g", "--granularity GRAN", "timing granularity") {|g| granularity = g}
  opt.on("-t", "--type TYPE", "trace type") {|t| type = t}
  opt.on("-f", "--trace-file FILE", "trace file") {|f| tracefile = f}
  opt.parse!(ARGV)

  Sim::traceParser(duration, granularity, "type"      => type,
                                          "tracefile" => tracefile)
end
