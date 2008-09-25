#  Copyright (C) 2007 Janico Greifenberg <jgre@jgre.org> and 
#  Dirk Kutscher <dku@tzi.org>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

# FLUTE convergence layer

require "rdtnerror"
require "configuration"
require "cl"
require "sdnv"
require "queue"
require "rdtnevent"
require "eidscheme"
require "stringio"
require "genparser"

module FluteCL

  # Represents the sender part of the FLUTE CL
  # Send linkCreated, linkClosed events
  # Never sends bundleData
  class FluteLink < Link

    def initialize(config, evDis, papagenoDir="papageno_outgoing")
      super(config, evDis)
      self.open("flute#{self.object_id}", :directory => papagenoDir)
    end

    def open(name, options)
      self.name = name
      @ppgDir = File.expand_path("papageno_outgoing") # default directory
      bandwidth = 629760 # 492kbit/s
      @addr = "224.1.2.3"
      @fluteOpts = "-E -r 1.5 -i 1.0"

      if options.has_key?(:directory)
	@ppgDir = File.expand_path(options[:directory])
      end
      if options.has_key?(:fluteSend)
	@ppgProg = options[:fluteSend]
      end
      if options.has_key?(:bandwidth)
	bandwidth = options[:bandwidth]
      end
      if options.has_key?(:addr)
	@addr = options[:addr]
      end
      if options.has_key?(:fluteOpts)
	@fluteOpts = options[:fluteOpts]
      end

      rdebug("Flute link writes data for Papageno to #{@ppgDir}")

      if defined? @ppgProg
	# Spawn a papageno process
	@pid = fork do
	#if fork.nil?
	  # TODO let the parameters be given in options
	  exec("#{@ppgProg} #{@fluteOpts} -a #{@addr} -b #{bandwidth} #{@ppgDir}")
	end
      end
      @evDis.dispatch(:linkOpen, self)

    end

    def close()
      if defined? @pid and @pid and @pid != 0
	Process.kill("HUP", @pid)
      end
      @evDis.dispatch(:linkClosed, self)
    end

    # Puts two files into the outgoing directory:
    #  - the bundle in a file named <id>.bundle
    #  - the metadata in a file named <id>.meta
    def sendBundle(bundle)
      id = "#{bundle.object_id}"
      # Create a lock file
      File.open(File.join(@ppgDir, "#{id}.meta.lock"), "w") {}
      File.open(File.join(@ppgDir, "/"+ "#{id}.meta"), "w") do |file|
        file << "URI: uni-dtn://#{bundle.srcEid.to_s}/#{bundle.creationTimestamp}/#{bundle.creationTimestampSeq}/#{bundle.fragmentOffset}\r\n"
        file << "COS: 0\r\n"
        file << "Destination-EID: #{bundle.destEid.to_s}\r\n"
        file << "Router-EID: #{@config.localEid}\r\n"
      end
      #Delete lock file
      File.delete(@ppgDir + "/" + "#{id}.meta.lock")

      # Create a lock file
      File.open(@ppgDir + "/" + "#{id}.bundle.lock", "w") {}
      File.open(@ppgDir + "/" + "#{id}.bundle", "w") do |file|
	file << bundle.to_s
      end
      #Delete lock file
      File.delete(@ppgDir + "/" + "#{id}.bundle.lock")
    end

  end
  
  # Represents the receiver part of the FLUTE CL
  # Sends BundleData
  # Does not send linkCreated, linkClosed
  # Does not respond to sendBundle
  class FluteInterface < Interface

    def initialize(config, evDis, name, options)
      self.name = name
      @config = config
      @evDis = evDis
      @ppgDir = File.expand_path("papageno_incoming") # default directory
      @pollInterval = 10 # seconds
      @addr = "224.1.2.3"
      @fluteOpts = ""

      if options.has_key?(:directory)
	@ppgDir = File.expand_path(options[:directory])
      end
      if options.has_key?(:fluteSend)
	@ppgProg = options[:fluteSend]
      end
      if options.has_key?(:interval)
	@pollInterval = options[:interval]
      end
      if options.has_key?(:addr)
	@addr = options[:addr]
      end
      if options.has_key?(:fluteOpts)
	@fluteOpts = options[:fluteOpts]
      end

      rdebug("Flute interface polling for data from Papageno every #{@pollInterval} seconds in #{@ppgDir}")

      listenerThread(@pollInterval) do |interval|
	poll
	RdtnTime.rsleep(interval)
      end

      if defined? @ppgProg
	# Spawn a papageno process
	@pid = fork do
	#if fork.nil?
	  Dir.chdir(@ppgDir)
	  rinfo("Starting papageno in #{Dir.pwd}")
	  # TODO let the parameters be given in options
	  exec("#{@ppgProg} #{@fluteOpts} -a #{@addr} #{@ppgDir}")
	end
      end
    end

    def close(wait = nil)
      Process.kill("HUP", @pid) if @pid
      super()
    end

    private

    def poll
      return unless File.directory?(@ppgDir)
      Dir.foreach(@ppgDir) do |fn|
	completeFn = @ppgDir + "/" + fn
	if File.directory?(completeFn)
	  next
	end
	File.open(completeFn) do |file|
	  bundle = StringIO.new(file.read)
	  bundle.pos = 0
	  @evDis.dispatch(:bundleData, bundle, self)
	end
	File.delete(completeFn)
      end
    end

  end


end # module FluteCL

regCL(:flute, FluteCL::FluteInterface, FluteCL::FluteLink)
