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
$:.unshift File.join(File.dirname(__FILE__), "..", "lib")

require "test/unit"
require "bundleworkflow"

class TestWorkflow < Test::Unit::TestCase

  def setup
    @evDis  = EventDispatcher.new
    @config = RdtnConfig::Settings.new(@evDis)
    @bundle = Bundling::Bundle.new("test", "dtn:receiver")
    @config.store = @store = Storage.new(@evDis, nil, "store")
  end

  def teardown
    @store.clear
    begin
      File.delete("store")
    rescue
    end
  end

  #def test_marshal
  #  wf = Bundling::BundleWorkflow.new(@config, @evDis, @bundle)
  #  fwBundle = nil
  #  bothEvents = false
  #  @evDis.subscribe(:bundleToForward) do |bundle|
  #    if fwBundle
  #      assert_equal(fwBundle, bundle)
  #      bothEvents = true
  #    else
  #      fwBundle = bundle
  #    end
  #  end
  #  wf.processBundle
  #  b2 = @store.getBundle(@bundle.bundleId)
  #  assert_equal(@bundle, b2)
  #  assert(fwBundle)

  #  str = Marshal.dump(wf)
  #  wf2 = Marshal.load(str)

  #  wf2.processBundle
  #  assert(bothEvents)
  #end

  def test_process
  end

  def test_delete
  end

end
