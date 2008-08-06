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

  def numberOfContacts
    @contacts.length
  end

  def totalContactDuration
    @contacts.inject(0) {|sum, cont| sum + cont.duration }
  end

end
