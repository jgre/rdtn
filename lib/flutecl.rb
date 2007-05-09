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
#
# $Id$

# FLUTE convergence layer

require "optparse"
require "event-loop"

require "rdtnlog"
require "rdtnerror"
require "rdtnconfig"
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

    def initialize(papagenoDir="papageno_outgoing")
      super()
      self.open("flute#{self.object_id}", "-d #{papagenoDir}")
    end

    def open(name, options)
      @ppgDir = File.expand_path("papageno_outgoing") # default directory

      opts = OptionParser.new do |opts|
	opts.on("-d", "--directory DIR", "Papageno outgoing directory") do |dir|
	  @ppgDir = File.expand_path(dir)
	end
	opts.on("-s", "--flute-send EXECUTABLE", "Path to the flute-send executable") do |exec|
	  @ppgProg = File.expand_path(exec)
	end
	#opts.on("-a", "--address ADDR", "Address for channel 0") do |addr| 
	#  @ppgAddr = addr
        #end
	#opts.on("-p", "--port PORT", "Port for channel 0") do |port| 
	#  @ppgPort = port
        #end

      end

      opts.parse!(options.split)

      RdtnLogger.instance.debug("Flute link writes data for Papageno to #{@ppgDir}")

      if defined? @ppgProg
	# Spawn a papageno process
	if fork.nil?
	  # TODO let the parameters be given in options
	  exec("#{@ppgProg} -L -a 224.1.2.3 #{@ppgDir}")
	end
      end

    end

    def close()
      EventDispatcher.instance().dispatch(:linkClosed, self)
    end

    # Puts two files into the outgoing directory:
    #  - the bundle in a file named <id>.bundle
    #  - the metadata in a file named <id>.meta
    def sendBundle(bundle)
      id = "#{bundle.object_id}"
      # Create a lock file
      File.open(@ppgDir + "/" + "#{id}.meta.lock", "w") {}
      File.open(@ppgDir + "/"+ "#{id}.meta", "w") do |file|
        file << "URI: uni-dtn://#{bundle.srcEid.to_s}/#{bundle.creationTimestamp}/#{bundle.creationTimestampSeq}/#{bundle.fragmentOffset}\r\n"
        file << "COS: #{bundle.cosFlags}\r\n"
        file << "Destination-EID: #{bundle.destEid.to_s}\r\n"
        file << "Router-EID: #{RDTNConfig.instance.localEid}\r\n"
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

    def initialize(name, options)
      @ppgDir = File.expand_path("papageno_incoming") # default directory
      @pollInterval = 10 # seconds

      opts = OptionParser.new do |opts|
	opts.on("-d", "--directory DIR", "Papageno incoming directory") do |dir|
	  @ppgDir = File.expand_path(dir)
	end

	opts.on("-i", "--interval INT", "Poll interval in seconds") do |inter|
	  @pollInterval = inter.to_i
	end
	opts.on("-s", "--flute-send EXECUTABLE", "Path to the flute-send executable") do |exec|
	  @ppgProg = File.expand_path(exec)
	end
      end

      opts.parse!(options.split)

      RdtnLogger.instance.debug("Flute interface polling for data from Papageno every #{@pollInterval} seconds in #{@ppgDir}")

      @timer = @pollInterval.seconds.from_now_and_repeat {self.poll}

      if defined? @ppgProg
	# Spawn a papageno process
	if fork.nil?
	  Dir.chdir(@ppgDir)
	  puts "Starting papageno in #{Dir.pwd}"
	  # TODO let the parameters be given in options
	  exec("#{@ppgProg} -a 224.1.2.3 #{@ppgDir}")
	end
      end
    end

    def poll()
      Dir.foreach(@ppgDir) do |fn|
	completeFn = @ppgDir + "/" + fn
	if File.directory?(completeFn)
	  next
	end
	File.open(completeFn) do |file|
	  bundle = StringIO.new(file.read)
	  EventDispatcher.instance().dispatch(:bundleData, bundle, true, nil)
	end
	File.delete(completeFn)
      end
    end

    def close()
      @timer.stop
    end

  end


end # module FluteCL

regCL(:flute, FluteCL::FluteInterface, FluteCL::FluteLink)
