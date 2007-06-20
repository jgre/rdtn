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

require "singleton"
require "event-loop"
require "event-loop/timer"

class EventDispatcher
  include Singleton
  include SignalEmitter

  def initialize
    @subscribers = Hash.new()
  end

  # Register a handler for an event. The block handler is called when the
  # event with the ID envetId is dispatched. Returns the the Proc object for the
  # block.

  def subscribe(eventId, &handler)
    if not @subscribers[eventId]: @subscribers[eventId] = [] end
    @subscribers[eventId] << handler
  end

  # Remove the subscription to an event. The handler is a Proc object (e.g. the
  # one returned by subscribe.

  def unsubscribe(eventId, handler)
    @subscribers.delete_if {|id, h| id == eventId and h == handler}
  end

  # Remove every subscription for wich block returns true.

  def unsubscribeIf(&block)
    @subscribers.delete_if(&block)
  end

  # Remove all subscriptions.

  def clear
    @subscribers.clear
  end

  def dispatch(eventId, *args)
    EventLoop.later { dispatchEvent(eventId, *args) }
  end

  private
  def dispatchEvent(eventId, *args)
    if @subscribers[eventId]
      @subscribers[eventId].each { |handler| handler.call(*args) }
    end
  end


end
