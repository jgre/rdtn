## timer.rb --- timer implementations for the event loop
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

class EventLoop
  def every (interval, options={}, &body)
    options[:event_loop] ||= self
    PeriodicTimer.new(interval, options, &body).start
  end

  def after (interval, options={}, &body)
    options[:event_loop] ||= self
    SporadicTimer.new(interval, options, &body).start
  end

  def repeat (&body)
    every(0, &body)
  end

  def later (&body)
    after(0, &body)
  end
end

class EventLoop::Timer
  include SignalEmitter

  DEFAULT_TOLERANCE = 0.001

  define_opposite_readers :stopped? => :running?
  define_readers :interval, :tolerance, :event_loop
  define_signal :alarm

  def initialize (interval, options={}, &alarm_handler)
    EventLoop::Utilities.validate_keyword_arguments options.keys,
      [:tolerance, :event_loop]

    @running = false
    @start_time = nil

    @interval = interval
    @event_loop = options[:event_loop] || EventLoop.current
    @alarm_handler = alarm_handler and
      replace_alarm_handler(&@alarm_handler)

    if options[:tolerance]
      @tolerance = options[:tolerance].to_f
    elsif DEFAULT_TOLERANCE < @interval
      @tolerance = DEFAULT_TOLERANCE
    else
      @tolerance = 0.0
    end
  end

  def start_time ; @start_time or
      fail "the timer has not been started" end
  def end_time ; start_time + @interval end
  def time_left ; end_time - Time.now end
  def ready? ; time_left <= @tolerance end

  def interval= (new_interval)
    old_interval = @interval
    @interval = new_interval
    if running? and new_interval < old_interval
      @event_loop.check_timer(self)
    end
  end

  def end_time= (new_end_time)
    self.interval = new_end_time - start_time end
  def time_left= (new_time_left)
    self.end_time = Time.now + new_time_left end

  def replace_alarm_handler (&block)
    remove_signal_handler(:alarm, @alarm_handler) if @alarm_handler
    add_signal_handler(:alarm, &block)
    @alarm_handler = block
  end

  def restart (&block)
    running? or raise "the timer is not running"
    replace_alarm_handler(&block) if block_given?
    returning self do
      @start_time = Time.now
    end
  end

  def start (&block)
    replace_alarm_handler(&block) if block_given?
    returning self do
      @start_time = Time.now
      @event_loop.monitor_timer(self)
      @running = true
    end
  end

  def stop
    returning self do
      @event_loop.ignore_timer(self)
      @running = false
    end
  end

  class << self
    define_hard_alias :regular_new => :new

    def new (*a, &b)
      warn "event-loop: As of event-loop 0.3, `EventLoop::Timer.new' " +
        "is deprecated in favor of `EventLoop#every' and " +
        "`EventLoop#after'; see the documentation for more information."
      new!(*a, &b)
    end

    def new! (options={}, &body)
      if options.kind_of? Numeric
        interval = options
        options = {}
      elsif options.include? :interval
        interval = options[:interval].to_f
        options.delete(:interval)
      else
        interval = 0.0
      end
      
      EventLoop::Utilities.validate_keyword_arguments options.keys,
        [:interval, :tolerance, :start?, :event_loop]

      if options.include? :start?
        start = options.delete(:start?)
      else
        start = block_given?
      end
      
      timer = EventLoop::PeriodicTimer.new(interval, options)
      timer.on_alarm(&body) if block_given?
      timer.start if start
      return timer
    end
  end
end

class EventLoop::PeriodicTimer < EventLoop::Timer
  class << self
    define_soft_alias :new => :regular_new end
  def sound_alarm
    signal :alarm ; restart if running? end
end

class EventLoop::SporadicTimer < EventLoop::Timer
  class << self
    define_soft_alias :new => :regular_new end
  def sound_alarm
    stop ; signal :alarm end
end

class Numeric
  def nanoseconds ; self / 1_000_000_000.0 end
  def microseconds ; self / 1_000_000.0 end
  def milliseconds ; self / 1_000.0 end
  def seconds ; self end
  def minutes ; self * 60.seconds end
  def hours ; self * 60.minutes end
  def days ; self * 24.hours end
  def weeks ; self * 7.days end
  def years ; self * 365.24.days end

  define_hard_aliases \
    :nanosecond => :nanoseconds,
    :microsecond => :microseconds,
    :millisecond => :milliseconds,
    :second => :seconds,
    :minute => :minutes,
    :hour => :hours,
    :day => :days,
    :week => :weeks,
    :year => :years

  define_hard_aliases \
    :ns => :nanoseconds,
    :ms => :milliseconds

  def half ; self / 2.0 end
  def quarter ; self / 4.0 end

  def from_now (&block)
    EventLoop.after(self, &block)
  end

  def from_now_and_repeat (&block)
    EventLoop.every(self, &block)
  end
end

class Integer
  # It turns out whole numbers of years are
  # always whole numbers of seconds.
  def years ; super.to_i end
  define_hard_alias :year => :years
end

def Time.measure
  t0 = now ; yield ; now - t0
end

if __FILE__ == $0
  require "test/unit"

  class TimerTest < Test::Unit::TestCase
    def setup
      EventLoop.current = EventLoop.new
      @timer = EventLoop::Timer.new!(:interval => 1.ms)
    end

    def test_monitor_unstarted_timer
      assert_raise RuntimeError do
        EventLoop.monitor_timer(@timer)
        EventLoop.run
      end
    end

    def test_start_monitoring_timer_while_running
      EventLoop.later { 1.ms.from_now { EventLoop.quit } }
      1.second.from_now { EventLoop.quit }
      assert Time.measure { EventLoop.run } < 1.half.second
    end

    def test_start_monitoring_timer_while_running_deprecated
      @timer.start { EventLoop::Timer.new!(1.ms) { EventLoop.quit } }
      EventLoop::Timer.new!(1.second) { EventLoop.quit }
      assert Time.measure { EventLoop.run } < 1.half.second
    end

    def test_timer_tolerance
      timer = EventLoop::SporadicTimer.new(10.milliseconds) do
        puts "[#{timer.time_left * 1000} milliseconds left on alarm]"
        EventLoop.quit end
      8.times do
        dt = Time.measure { timer.start ; EventLoop.run }
        assert(dt > timer.interval - timer.tolerance)
      end
    end
  end

  class SporadicTimerTest < Test::Unit::TestCase
    def setup
      EventLoop.current = EventLoop.new
    end

    def test_sporadicity
      counter = 0
      1.nanosecond.from_now { counter += 1 }
      5.times { EventLoop.iterate(10.milliseconds) }
      assert counter == 1
    end
  end

  class PeriodicTimerTest < Test::Unit::TestCase
    def setup
      EventLoop.current = EventLoop.new
    end
    
    def test_periodicity
      counter = 0
      EventLoop.every(1.nanosecond) { counter += 1 }
      5.times { EventLoop.iterate(10.milliseconds) }
      assert counter == 5
    end
  end
end

## timer.rb ends here.
