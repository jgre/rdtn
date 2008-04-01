#  Copyright (C) 2008 Janico Greifenberg <jgre@jgre.org> and 
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

$:.unshift File.join(File.dirname(__FILE__), "..", "..", "lib")
$:.unshift File.join(File.dirname(__FILE__), "..", "..", "sim")

require "core"

dirName = File.join(Dir.getwd, 
		  "channel-experiment#{Time.now.strftime('%Y%m%d-%H%M%S')}")
sim = Sim::SimCore.new(dirName)
sim.parseOptions
sim.parseConfigFile
sim.createNodes

channels = (1..sim.config["nchannels"]).to_a.map {|i| "dtn://channel#{i}/"}
senders = {}
channels.each_with_index {|ch, i| senders[i+1] = ch}
receivers = {
  6  => ["dtn://channel1/", "dtn://channel2/"],
  7  => ["dtn://channel2/", "dtn://channel3/", "dtn://channel4/"],
  8  => ["dtn://channel4/", "dtn://channel5/", "dtn://channel1/"],
  9  => ["dtn://channel4/", "dtn://channel5/", "dtn://channel1/"],
  10 => ["dtn://channel5/", "dtn://channel1/"]
}

receivers.each do |node, channels|
  channels.each do |channel| 
    sim.nodes[node].config.subscriptionHandler.subscribe(channel)
  end
end

startTime = nil
#ret = sim.at(sim.config["bundleInterval"]) do |time|
#  puts "Sending at #{time}"
#  startTime = time unless startTime
#  senders.each do |id, channel| 
#    sim.nodes[id].createBundle(channel, 1024) if sim.nodes[id]
#  end
#  true
#end

#puts "Registered #{ret}"

sim.run
