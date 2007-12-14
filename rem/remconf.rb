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

module Rem

  REM_PORT = 10000

  class Config

    attr_accessor :nnodes, :duration, :granularity, :realTime,
      :host, :port, 
      :configPath, :rdtnPath,
      :time, :timeAddr, :timePort,
      :contactDistance

    include Singleton

    def initialize
      @nnodes = 10
      @duration = 600
      @granularity = 0.1
      @realTime = false
      @host = 'localhost'
      @port = REM_PORT
      @configPath = File.join(File.dirname(__FILE__), 'rdtn.conf')
      @rdtnPath   = File.join(File.dirname(__FILE__), '..', 'apps', 'random',
			      'randomsender')
      @time = Time.now
      @timeAddr = '224.224.224.2'
      @timePort = 12346
      @contactDistance = 250
    end

    def self.load(filename)
      instance.instance_eval(File.read(filename), filename)
    end

    #def nnodes(n)
    #  puts "NNodes="
    #  @nnodes = n
    #end

    def traceParser(name, options = {:tracefile => File.join(File.dirname(__FILE__), 'scen'), :eventdump => File.join(File.dirname(__FILE__), 'eventdump')})
      TraceParserReg.instance.tps[name].new(options)
    end

  end

  class TraceParserReg

    attr_accessor :tps

    def initialize
      @tps = {}
    end

    include Singleton

    def reg(name, klass)
      @tps[name] = klass
    end
  end

  def regTraceParser(name, klass)
    TraceParserReg.instance.reg(name, klass)
  end

end # module
