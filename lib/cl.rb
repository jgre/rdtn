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

require 'singleton'
require "rerun_thread"
require "thread"

# Interface class for incoming connections
# Interface objects can generate new Links
class Interface
  attr_accessor :name
  include RerunThread

  def listenerThread(*args, &block)
    @listenerThread = spawnThread(*args, &block)
  end

  def close
    if defined? @listenerThread and @listenerThread
      @listenerThread.kill
    end
  end

end


# Link class for uni- and bi-directional links
# each link has a specific type (the convergence layer type).
# 


class Link
  include RerunThread

  MIN_READ_BUFFER=1048576

  attr_reader :bytesToRead
  attr_accessor :name
  # The policy determines when a link is opened and when it gets closed by the
  # contact manager. There are three possible values:
  # :alwaysOn (default)
  # :opporotinistic (the link is opened because of an external event)
  # :onDemand (link link is only open, when it sends data)
  attr_accessor :policy

  @@linkCount = 0

  def initialize
    @@linkCount += 1
    @name = "Link#{@@linkCount}"
    @policy = :alwaysOn
    @bytesToRead = MIN_READ_BUFFER
    @senderThreads = Queue.new
    @receiverThreads = Queue.new
    EventDispatcher.instance().dispatch(:linkCreated, self)
  end

  def to_s
    return @name
  end

  # When reading data we rather err to the side of greater numbers, as reading
  # stops anyway, when there is no data left. And we always want to be ready
  # to read something, as we cannot be sure what the other side is up to.
  def bytesToRead=(bytes)
    if bytes and bytes > MIN_READ_BUFFER
      @bytesToRead = bytes
    end
  end

  # Returns true, if this link is actively performing a taks.
  # The default implementation checks, if there are any sender threads running.
  def busy?
    return @senderThread.any? {|thr| thr.alive?}
  end

  # Close the link. If +wait+ is not +nil+, the method waits for the given
  # number of seconds before killing busy threads.
  def close(wait = nil)
    until @senderThreads.empty?
      thr = @senderThreads.pop
      res = thr.join(wait) if wait
      if not res
	thr.kill
	wait = nil
      end
    end
    until @receiverThreads.empty?
      thr = @receiverThreads.pop
      Thread.kill(thr) if thr != Thread.current
    end
    EventDispatcher.instance().dispatch(:linkClosed, self)
  end

  protected

  def senderThread(*args, &block)
    ret = spawnThread(*args, &block)
    @senderThreads.push(ret)
    return ret
  end

  def receiverThread(*args, &block)
    ret = spawnThread(*args, &block)
    @receiverThreads.push(ret)
    return ret
  end


end


class CLReg
  attr_accessor :cl

  def initialize
    @cl={}
  end

  include Singleton

  def reg(name, interface, link)
    @cl[name] = [interface, link]    
  end

  def getName(klass)
    @cl.each {|name, lst| return name if klass == lst[0] or klass == lst[1] }
  end

end

def regCL(name, interface, link)
  c=CLReg.instance()
  c.reg(name, interface, link)
end
