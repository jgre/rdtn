## io.rb --- convenience features for IO objects
# Copyright (C) 2005, 2006  Daniel Brockman

# This program is free software; you can redistribute it
# and/or modify it under the terms of the GNU General Public
# License as published by the Free Software Foundation;
# either version 2 of the License, or (at your option) any
# later version.

# This file is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty
# of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See the GNU General Public License for more details.

# You should have received a copy of the GNU General Public
# License along with this program; if not, write to the Free
# Software Foundation, 51 Franklin Street, Fifth Floor,
# Boston, MA 02110-1301, USA.

require "event-loop"
require "fcntl"

class Symbol
  def io_state?
    EventLoop::IO_STATES.include? self
  end
end

module EventLoop::Watchable
  include SignalEmitter

  define_signals :readable, :writable, :exceptional

  def monitor_events (*events)
    EventLoop.monitor_io(self, *events) end
  def ignore_events (*events)
    EventLoop.ignore_io(self, *events) end

  define_soft_aliases \
    :monitor_event => :monitor_events,
    :ignore_event  => :ignore_events

  def close ; super
    ignore_events end
  def close_read ; super
    ignore_event :readable end
  def close_write ; super
    ignore_event :writable end

  module Automatic
    include EventLoop::Watchable

    def add_signal_handler (name, &handler) super
      monitor_event(name) if name.io_state?
    end

    def remove_signal_handler (name, handler) super
      if @signal_handlers[name].empty?
        ignore_event(name) if name.io_state?
      end
    end
  end
end

class IO
  def on_readable &block
    extend EventLoop::Watchable::Automatic
    on_readable(&block)
  end

  def on_writable &block
    extend EventLoop::Watchable::Automatic
    on_writable(&block)
  end

  def on_exceptional &block
    extend EventLoop::Watchable::Automatic
    on_exceptional(&block)
  end

  def will_block?
    require "fcntl"
    fcntl(Fcntl::F_GETFL, 0) & Fcntl::O_NONBLOCK == 0
  end

  def will_block= (wants_blocking)
    require "fcntl"
    flags = fcntl(Fcntl::F_GETFL, 0)
    if wants_blocking
      flags &= ~Fcntl::O_NONBLOCK
    else
      flags |= Fcntl::O_NONBLOCK
    end
    fcntl(Fcntl::F_SETFL, flags)
  end
end

## io.rb ends here.
