## event-loop.rb --- high-level IO multiplexer
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

require "event-loop/better-definers"
require "event-loop/signal-system"

class EventLoop ; end

require "event-loop/io"

class EventLoop
  module Utilities
    def self.validate_keyword_arguments (actual, allowed)
      (unknown_keys = actual - allowed).empty? or
        fail "unrecognized keyword argument" +
          "#{"s" if unknown_keys.size > 1}: " +
          unknown_keys.map { |x| "`#{x}'" }.join(", ")
    end
  end
end

class EventLoop
  include SignalEmitter

  IO_STATES = [:readable, :writable, :exceptional]

  class << self
    def default ; @default ||= new end
    def default= x ; @default = x end

    def current
      Thread.current["event-loop::current"] || default end
    def current= x
      Thread.current["event-loop::current"] = x end

    def with_current (new)
      # Be sure to return the value of the block.
      if current == new
        yield
      else
        begin
          old = self.current
          self.current = new
          yield
        ensure
          current == new or warn "uncontained change " +
            "to `EventLoop.current' within dynamic " +
            "extent of `EventLoop.with_current'"
          self.current = old
        end
      end
    end

    def method_missing (name, *args, &block)
      if current.respond_to? name
        current.__send__(name, *args, &block)
      else
        super
      end
    end
  end

  define_signals :before_sleep, :after_sleep

  def initialize
    @running = false
    @awake = false
    @wakeup_time = nil
    @timers = []

    @io_arrays = [[], [], []]
    @ios = Hash.new do |h, k| raise ArgumentError,
      "invalid IO event: #{k}", caller(2) end
    IO_STATES.each_with_index { |x, i| @ios[x] = @io_arrays[i] }

    @notify_src, @notify_snk = IO.pipe

    @notify_src.will_block = false
    @notify_snk.will_block = false

    # For bootstrapping reasons, we can't let the stub
    # implementation of IO#on_readable set this up.
    monitor_io(@notify_src, :readable)
    @notify_src.extend(Watchable)
    # Each time a byte is sent through the notification pipe
    # we need to read it, or IO.select will keep returning.
    @notify_src.on_readable do
      begin
        @notify_src.sysread(256)
      rescue Errno::EAGAIN
        # The pipe wasn't readable after all.
      end
    end
  end

  define_opposite_accessors \
    :stopped? => :running?,
    :asleep? => :awake?

  # This is an old name for the property.
  define_hard_alias :sleeping? => :asleep?

  def run
    if block_given?
      thread = Thread.new { run }
      yield ; quit ; thread.join
    else
      running!
      iterate while running?
    end
  ensure
    quit
  end

  def iterate (user_timeout=nil)
    t1, t2 = user_timeout, max_timeout
    timeout = t1 && t2 ? [t1, t2].min : t1 || t2
    select(timeout).zip(IO_STATES) do |ios, state|
      ios.each { |x| x.signal(state) } if ios
    end
  end

 private

  def select (timeout)
    @wakeup_time = timeout ? Time.now + timeout : nil
    # puts "waiting: #{timeout} seconds"
    signal :before_sleep ; asleep!
    IO.select(*@io_arrays + [timeout]) || []
  ensure
    awake! ; signal :after_sleep
    @timers.each { |x| x.sound_alarm if x.ready? }
  end

 public

  def quit ; stopped! ; wake_up ; self end

  def monitoring_io? (io, event)
    @ios[event].include? io end
  def monitoring_timer? (timer)
    @timers.include? timer end

  def monitor_io (io, *events)
    for event in events do
      unless monitoring_io?(io, event)
        @ios[event] << io ; wake_up
      end
    end
  end

  def monitor_timer (timer)
    @timers << timer unless monitoring_timer? timer
    check_timer(timer)
  end

  def check_timer (timer)
    wake_up if running? and asleep? and
      timer.end_time < @wakeup_time
  end

  def ignore_io (io, *events)
    events = IO_STATES if events.empty?
    for event in events do
      wake_up if @ios[event].delete(io)
    end
  end

  def ignore_timer (timer)
    # Don't need to wake up for this.
    @timers.delete(timer)
  end

  def max_timeout
    return nil if @timers.empty?
    [@timers.collect { |x| x.time_left }.min, 0].max
  end

  def wake_up
    returning self do
      @notify_snk.write('.') if asleep?
    end
  end
end

## event-loop.rb ends here.
