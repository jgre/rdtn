$:.unshift File.join(File.dirname(__FILE__), '..')
$:.unshift File.join(File.dirname(__FILE__))

require 'contact'

class ContactHistory

  attr_reader :id, :node1, :node2, :contacts

  def initialize(id)
    @node1, @node2 = @id = id
    @contacts = []
  end

  def self.getId(node1, node2)
    [node1, node2].sort
  end

  def contactStart(time)
    if @contacts.last and @contacts.last.open?
      # Delete the unfinished contact as it only messes up our calculation
      @contacts.pop
    end
    @contacts.push(Contact.new(@node1, @node2, time))
  end

  def contactEnd(time)
    @contacts.last.endContact(time) if @contacts.last and @contacts.last.open?
  end

  def relevantContacts(warmup = 0)
    @contacts.find_all {|c| c.endTime.nil? || c.endTime >= warmup}
  end

  def numberOfContacts(warmup = 0)
    relevantContacts(warmup).length
  end

  def totalContactDuration(warmup = 0)
    relevantContacts(warmup).inject(0) {|sum, cont| sum + cont.duration(warmup)}
  end

  def contactDurations(warmup = 0)
    relevantContacts(warmup).inject([]) {|memo, cont| memo << cont.duration(warmup)}
  end

end
