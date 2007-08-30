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

require "rdtnevent"
require "clientlib"
require "eidscheme"
require "genparser"
require "queue"
require "clientregcl"

class Subscription
  attr_accessor :uri,
    		:link,
    		:local,
    		:creationTimestamp,     # This is not the creation time of the 
					# bundle.
		:expires

  include GenParser

  def initialize(uri, link, local = true, 
		 creationTimestamp = Time.now, expires = Time.now + 86400)
    @uri = EID.new(uri.to_s)
    @link = link
    @local = local
    @creationTimestamp = creationTimestamp
    @expires = expires
  end

  def ===(sub2)
    Regexp.new(@uri.to_s) === sub2.uri.to_s
  end

  def Subscription.parse(io)
    ret = Subscription.new("", nil)
    ret.defField(:uriLength, :decode => GenParser::SdnvDecoder,
		 :block => lambda {|len| ret.defField(:uri, :length => len)})
    ret.defField(:uri, :handler => :uri=)
    ret.defField(:timestamp, :decode => GenParser::SdnvDecoder, 
		 :handler => :creationTimestamp=)
    ret.defField(:expires, :decode => GenParser::SdnvDecoder, 
		 :handler => :expires=)
    ret.parse(io)
    ret.local = false
    return ret
  end

  def creationTimestamp=(ts)
    @creationTimestamp = Time.gm(2000) + ts
  end

  def expires=(ts)
    @expires = Time.gm(2000) + ts
  end

  def serialize(io)
    io.write(Sdnv.encode(@uri.to_s.length))
    io.write(@uri)
    io.write(Sdnv.encode(wireCreationTimestamp))
    io.write(Sdnv.encode(wireExpires))
  end

  private

  def wireCreationTimestamp
    (@creationTimestamp - Time.gm(2000)).to_i
  end

  def wireExpires
    (@expires - Time.gm(2000)).to_i
  end

end

class SubscriptionHandler

  EidPattern = "dtn:subscribe/.*"

  def initialize(client = nil, checkInterval = 300)
    client = RdtnClient.new if not client
    @client = client
    @client.register(EidPattern) {|bundle| processBundle(bundle) }
    @subscriptions = []
    @subClients = []
    @subscribeBundleId = nil

    EventDispatcher.instance.subscribe(:linkCreated){|link| sendSubscribe(link)}
    Thread.new(checkInterval) do |interval|
      Thread.current.abort_on_exception = true
      sleep(interval)
      check
    end

  end

  def subscribe(uri, subClient = nil, creationTimestamp = Time.now, 
		expires = Time.now + 86400, &handler)
    subClient = RdtnClient.new(@client.host, @client.port) if not subClient
    subClient.register(uri, &handler)
    @subClients.push(subClient)
    doSubscribe(Subscription.new(uri, nil, true, creationTimestamp, expires))
  end

  def subscribedUris
    @subscriptions.map {|sub| sub.uri.to_s}
  end

  def generateSubscriptionBundle
    io = RdtnStringIO.new
    @subscriptions.each {|sub| sub.serialize(io)}
    io.rewind
    bundle = Bundling::Bundle.new(io.read, "dtn:subscribe/")
    @subscribeBundleId = bundle.bundleId
    return bundle
  end

  private

  def processBundle(bundle)
    io = RdtnStringIO.new(bundle.payload)
    while not io.eof?
      sub = Subscription.parse(io)
      sub.link = bundle.incomingLink
      doSubscribe(sub)
    end
  end

  def check
    @subscriptions.delete_if {|sub| sub.expires < Time.now}
  end

  def doSubscribe(subscription)
    if @subscriptions.grep(subscription).empty?
      @subscriptions.push(subscription)
      @client.addRoute(subscription.uri, subscription.link) if subscription.link
      sendSubscribe(nil)
    end
  end

  def sendSubscribe(link)
    return nil if link.kind_of?(AppIF::AppProxy)
    @client.deleteBundle(@subscribeBundleId) if @subscribeBundleId
    @client.addRoute(EidPattern, link.name)  if link

    bundle = generateSubscriptionBundle

    @client.sendBundle(bundle)
  end

end
