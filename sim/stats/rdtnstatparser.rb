class RdtnStatParser

  def initialize(dir, model)
    @model = model
    @dir   = dir
  end

  def eachSubdir
    Dir.foreach(@dir) do |fn|
      filename = File.join(@dir, fn)
      unless filename=="." or filename==".." or not /kasuari(\d+)$/ =~ filename
	node = $1.to_i
	yield(filename, node)
      end
    end
  end

  def parse
    startTimes = []
    eachSubdir do |filename, node|
      open(File.join(filename, "time.stat")) {|f| startTimes.push(f.read.to_i)}
      if File.exist?(File.join(filename, "subscribe.stat"))
	open(File.join(filename, "subscribe.stat")) do |f| 
	  parseSubscribeStat(node, f)
	end
      end
    end
    # Subtract the first start time from all time outputs
    # to make them more readable
    @deltaTime = startTimes.min
    puts "Delta Time #{@deltaTime}"

    eachSubdir do |filename, node|
      if File.exist?(File.join(filename, "contact.stat"))
	open(File.join(filename, "contact.stat")) {|f| parseContactStat(node,f)}
	if File.exist?(File.join(filename, "out.stat"))
	  open(File.join(filename, "out.stat")) {|f| parseIOStat(node,:out,f)}
	end
	if File.exist?(File.join(filename, "in.stat"))
	  open(File.join(filename, "in.stat"))  {|f| parseIOStat(node,:in,f)}
	end
      end
    end
  end

  private

  CONTPATTERN = /(\d+), (contact|closed), \w+, \w*, .*, \d*, dtn:\/\/[a-zA-Z]+(\d+)\//
  IOPattern = %r{(\d+), dtn://[a-zA-Z]+(\d+)/, dtn://[a-zA-Z]+(\d+)/, (-?\d+), (\d+), (true|false)(, dtn://[a-zA-Z]+(\d+)/)?$}
  SubscrPattern = %r{(\d+), dtn:subscribe/, dtn://[a-zA-Z]+(\d+)/, (-?\d+), (\d+), (true|false)(, dtn://[a-zA-Z]+(\d+)/)?$}

  def parseIOStat(fromNode, inout, file)
    file.each_line do |line|
      if IOPattern =~ line
	time        = $1.to_i - @deltaTime
	channel     = $2.to_i
	src         = $3.to_i
	bid         = $4
	size        = $5.to_i
	foreignNode = $8.to_i if $8
	bundle = StatBundle.new(channel, src, bid, size, @model.sinks[channel])
	@model.bundleEvent(fromNode, foreignNode, inout, bundle, time)

      elsif SubscrPattern =~ line
	time        = $1.to_i - @deltaTime
	src         = $2.to_i
	bid         = $3
	size        = $4.to_i
	foreignNode = $7.to_i if $7
	bundle = StatBundle.new(nil, src, bid, size, nil)
	@model.controlBundle(fromNode, foreignNode, inout, bundle, time)
      end
    end
  end

  def parseContactStat(fromNode, file)
    file.each_line do |line|
      if CONTPATTERN =~ line
	time   = $1.to_i - @deltaTime
	state  = $2
	foreignNode = $3.to_i
	evType = if state == 'contact'
		   :simConnection
		 elsif state == 'closed'
		   :simDisconnection
		 end
	@model.contactEvent(fromNode, foreignNode, fromNode, time, evType)
      end
    end
  end

  def parseSubscribeStat(fromNode, file)
    file.each_line do |line|
      if %r{^dtn://[a-zA-Z]+(\d+)/$} =~ line
	channel = $1.to_i
	@model.sink(channel, fromNode)
      end
    end
  end

end

