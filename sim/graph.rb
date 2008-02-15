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

module Sim

  class Edge
    attr_accessor :node1, :node2, :tStart, :tEnd

    def initialize(n1, n2, tStart, tEnd)
      @node1  = n1
      @node2  = n2
      @tStart = tStart
      @tEnd   = tEnd
    end

    def cost(time)
      if time < @tStart
	@tStart - time
      elsif @tEnd and time <= @tEnd
	0
      else
	nil
      end
    end

  end

  class Graph

    def initialize
      @nodes = []
      @edges = Hash.new {|hash, node| hash[node] = []}
    end

    def node(node)
      @nodes.push(node) unless @nodes.include?(node)
    end

    def edge(opts)
      # XXX evil use of ruby syntax so that we can write 
      #    graph.edge 1=>2
      # to create an edge between nodes 1 and 2
      tStart = opts[:start] || 0
      tEnd   = opts[:end]   || nil
      opts.delete(:start)
      opts.delete(:end)
      n1 = opts.keys[0]
      n2 = opts[opts.keys[0]]
      addEdge(n1, n2, tStart, tEnd)
    end

    def addEdge(n1, n2, tStart=0, tEnd=nil)
      node(n1)
      node(n2)
      edge =  Edge.new(n1, n2, tStart, tEnd)
      @edges[n1].push(edge)
    end

    def nodes
      @nodes
    end

    def edges(n)
      @edges[n]
    end

    def events
      maxTime = @edges.values.flatten.map {|edge| edge.tEnd || 0}.max
      events = EventQueue.new
      @edges.values.flatten.each do |edge|
	events.addEvent(edge.tStart, edge.node1, edge.node2, :simConnection)
	if edge.tEnd
	  events.addEvent(edge.tEnd, edge.node1, edge.node2, :simDisconnection)
	end
      end
      events.sort
    end

    def printGraphviz(file)
      file.puts("digraph test {")
      @edges.each_value do |edgeList|
	edgeList.each do |edge|
	  file.puts("#{edge.node1} -> #{edge.node2} [label=#{edge.cost(0)}]")
	end
      end
      file.puts("}")
    end

  end

end # module
