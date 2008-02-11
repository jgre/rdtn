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

class Edge
  attr_accessor :node1, :node2

  def initialize(n1, n2, tStart, tEnd)
    @node1  = n1
    @node2  = n2
    @tStart = tStart
    @tEnd   = tEnd
  end

  def cost(time)
    if time < @tStart
      @tStart - time
    elsif time <= @tEnd
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

  def edge(n1, n2, tStart, tEnd)
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

def dijkstra(graph, src, startTime)
  dists = {}
  paths = Hash.new {|hash, key| hash[key] = []}
  dists[src] = 0
  paths[src] = [src]
  q = graph.nodes.clone
  until q.empty?
    closest = minindex = minDist = nil
    q.each_with_index do |node, i|
      if dists[node] and (not minDist or dists[node] < minDist)
	minDist  = dists[node]
	closest  = node
	minindex = i
      end
    end
    return [dists, paths] unless closest
    q.delete_at(minindex)
    graph.edges(closest).each do |edge|
      other = closest == edge.node1 ? edge.node2 : edge.node1
      next unless q.include?(other) and edge.cost(startTime+minDist)
      unless dists[other] and dists[other]<=minDist+edge.cost(startTime+minDist)
	dists[other] = minDist + edge.cost(startTime+minDist)
	paths[other] = paths[closest] + [other]
      end
    end
  end
  [dists, paths]
end

