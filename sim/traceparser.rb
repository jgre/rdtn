module Sim

  def self.eventDumpCurrent?(fname)
    dumpfile = fname.to_s + ".rdtnsim"
    File.exist? fname and File.exist? dumpfile and (File.mtime(dumpfile) > File.mtime(fname))
  end

  def self.traceParser(options = {})
    fname = options[:tracefile]
    dumpfile = fname + ".rdtnsim"
    if eventDumpCurrent? fname
      open(dumpfile) {|f| Marshal.load(f)}
    else
      type      = options[:type]
      pluginDir = File.join(File.dirname(__FILE__), 'plugins/trace-parsers')
      require File.join(pluginDir, type.to_s.downcase + '.rb')
      parser    = Module.const_get(type).new(options)

      events = parser.events

      open(dumpfile, "w") {|f| Marshal.dump(events, f)} if fname
      events
    end
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
