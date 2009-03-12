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

require 'rdtnevent'

module Sim

  class Event
    attr_accessor :time, :nodeId1, :nodeId2, :type, :left, :right, :parent, :balance
    #include Comparable

    def initialize(time, nodeId1, nodeId2, type)
      @time    = time
      @nodeId1 = nodeId1
      @nodeId2 = nodeId2
      @type    = type
      @left    = nil 
      @right   = nil 
      @parent  = nil
      @balance = 0
    end

    def link(a)
      (a == -1) ? @left : @right
    end

    def set_link(a, node)
      if a == -1
	@left = node
      else
	@right = node
      end
      node.parent = self if node
    end

    #def <=>(ev)
    #  @time <=> ev.time
    #end

    def inspect
      @time.to_s
    end

    def self.insert(root, ev)
      return ev if root.nil?

      # create a special HEAD node that keeps a reference to the root
      head = Event.new(nil, nil, nil, nil)
      head.right  = root
      root.parent = head

      cur       = root
      rebalance = root
      loop do
	if ev.time < cur.time
	  # move to the left subtree
	  if cur.left.nil?
	    cur.left  = ev
	    ev.parent = cur
	    break
	  end
	  cur    = cur.left
	else
	  # move to the right subtree
	  if cur.right.nil?
	    cur.right = ev
	    ev.parent = cur
	    break
	  end
	  cur    = cur.right
	end
	rebalance = cur if cur.balance != 0
      end

      # adjust balance factors
      a = (ev.time < rebalance.time) ? -1 : 1
      r = cur = rebalance.link(a)
      until cur == ev
	if ev.time < cur.time
	  cur.balance = -1
	  cur = cur.left
	else
	  cur.balance = 1
	  cur = cur.right
	end
      end

      # balancing act
      if rebalance.balance == 0
	# tree has gotten higher
	rebalance.balance = a
      elsif rebalance.balance == -a
	# tree has gotten more balanced
	rebalance.balance = 0
      elsif rebalance.balance == a
	subtree_root = rebalance.parent
	# tree has gotten out of balance
	if r.balance == a
	  # single rotation
	  cur = r
	  rebalance.set_link(a, r.link(-a))
	  r.set_link(-a, rebalance)
	  rebalance.balance = r.balance = 0
	elsif r.balance == -a
	  # double rotation
	  cur = r.link(-a)
	  r.set_link(-a, cur.link(a))
	  cur.set_link(a, r)
	  rebalance.set_link(a, cur.link(-a))
	  cur.set_link(-a, rebalance)
	  rebalance.balance, r.balance = case cur.balance
					 when a  then [-a, 0]
					 when 0  then [ 0, 0]
					 when -a then [ 0, a]
					 end
	  cur.balance = 0
	end

	# fix the rebalanced subtree to the rest of the tree
	cur.parent = subtree_root
	if rebalance == subtree_root.right
	  subtree_root.right = cur
	  cur.parent = subtree_root
	else 
	  subtree_root.left  = cur
	end
      end

      # return the root
      head.right
    end

    def dispatch(evDis)
      if @nodeId1 and @nodeId2
        evDis.dispatch(@type, @nodeId1, @nodeId2)
      else
        evDis.dispatch(@type, @time)
      end
    end

  end

  class EventQueue

    attr_accessor :events
    include Enumerable

    def initialize(time0 = 0)
      @events = nil # Linked List
      @time0  = 0  # All event before time0 will be ignored
      @cur_ev = 0  # The index of the current event
      @nodes  = {}
    end

    def each(&blk)
      def go_down(node)
	node.left.nil? ? node : go_down(node.left)
      end
      def go_right(node, from)
	if node.nil?
	  nil
	elsif from.nil?
	  go_down(node)
	elsif from == node.right
	  go_right(node.parent, node)
	elsif node == from
	  node.right.nil? ? go_right(node.parent, node) : go_down(node.right)
	else
	  node
	end
      end

      cur = go_right(@events, nil)
      until cur.nil?
	yield cur
	cur = go_right(cur, cur)
      end

      self
    end

    def length
      inject(0) {|memo, ev| memo + 1}
    end

    def addEventSorted(time, nodeId1, nodeId2, type)
      @nodes[nodeId1] = @nodes[nodeId2] = nil #we only use the keys for counting
      ev = Event.new(time, nodeId1, nodeId2, type)
      @events = Event.insert(@events, ev)

      self
    end

    alias addEvent addEventSorted

    def empty?
      @events.empty?
    end

    def sort
      self
    end

    def last
      cur = @events
      ret = cur
      until cur.nil?
	ret = cur
	cur = cur.right
      end
      ret
    end

    def nodeCount
      @nodes.length
    end

    def nodeNames
      @nodes.keys
    end

    def marshal_dump
      [@events, @time0, @nodes]
    end

    def marshal_load(lst)
      @events, @time0, @nodes = lst
    end

    def to_yaml_properties
      %w{ @events @time0 @nodes }
    end

  end

end # module
