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

require "clientapi"
require "routetab"

class RequestInfo
  attr_accessor :requestType,
    		:sender
  def initialize(type, sender)
    @requestType = type
    @sender = sender
  end
end

class PatternReg

  Patterns = [
    [/^rdtn:bundles\/?([\w-]+)?\/(\w+)?\/?$/, :resolveBundleMethod],
    [/^rdtn:routetab\/$/, :resolveRouteTab],
    [/^rdtn:events\/(\w+)\/$/, :resolveEvent]
  ]

  def PatternReg.resolve(uri, request, store, args={})
    Patterns.each do |pattern, meth|
      md = pattern.match(uri)
      return self.send(meth, uri, request, store, md, args) if md
    end
    return STATUS, {:uri => uri, :status => 404, :message => "Not Found"}
  end

  private
  def PatternReg.resolveBundleMethod(uri, request, store, matchData, args)
    case request.requestType
    when QUERY
      bundle = nil
      if not matchData[1]
	raise MissingParameter, "Bundle Id" if not args.has_key?(:destEid)
	# FIXME return multiple bundles
	bundle = store.getBundlesMatchingDest(args[:destEid])[0] 
      else
	bundle = store.getBundle(matchData[1].to_i)
      end
      if not bundle
	return STATUS, {:uri => uri, :status => 404, :message => "Not Found"}
      elsif matchData[2]
	return RESOLVE, {:uri => uri, :bundleMeth => bundle.send(matchData[2])}
      else
	return RESOLVE, {:uri => uri, :bundle => bundle}
      end

    when POST
      # For now we only support to POST new bundles
      bundle = args[:bundle]
      if bundle.srcEid.to_s == "dtn:none"
	if defined? request.sender.registration and 
	   request.sender.registration          and 
	   request.sender.registration.to_s != "dtn:none"
	  bundle.srcEid = request.sender.registration
	else
	  bundle.srcEid = RdtnConfig::Settings.instance.localEid
	end
      end
      bundle.incomingLink = request.sender
      EventDispatcher.instance.dispatch(:bundleParsed, bundle)
      return STATUS, {:uri => uri, :status => 200, :message => "OK"}

    when DELETE
      if not matchData[1]
	raise MissingParameter, "Bundle Id"
      end
      store.deleteBundle(matchData[1].to_i)
      return STATUS, {:uri => uri, :status => 200, :message => "OK"}

    else
      raise NotImplemented
    end
  end

  def PatternReg.resolveRouteTab(uri, request, store, matchData, args)
    target = args[:target]
    if not target
      raise MissingParameter, "Destiniation EID"
    elsif target.to_s =~ /([[:alnum:]]+):([[:print:]]+)/
      target = EID.new(target)
    else
      # If the target is only a partial eid, prepend the eid of the router.
      target = RdtnConfig::Settings.instance.localEid.join(target)
    end

    link = args[:link] ? args[:link] : request.sender

    case request.requestType
    when POST
      if defined? link.registration and link == request.sender
	link.registration = target 
      end
      EventDispatcher.instance.dispatch(:routeAvailable, 
					RoutingEntry.new(target, link))
      return  STATUS, {:uri => uri, :status => 200, :message => "OK"}

    when DELETE
      EventDispatcher.instance.dispatch(:routeLost, link, target)
      return  STATUS, {:uri => uri, :status => 200, :message => "OK"}

    else
      raise NotImplemented
    end
  end

  def PatternReg.resolveEvent(uri, request, store, matchData, args)
    eventId = matchData[1]
    case request.requestType
    when POST
      EventDispatcher.instance.subscribe(eventId.to_sym) do |*args|
	request.sender.sendEvent(uri, *args)
      end
      return  STATUS, {:uri => uri, :status => 200, :message => "OK"}
    else
      raise NotImplemented
    end
  end

end
