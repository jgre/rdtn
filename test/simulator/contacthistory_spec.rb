$:.unshift File.join(File.dirname(__FILE__), '../../sim/stats')

require 'contacthistory'

describe ContactHistory do

  before(:each) do
    @ch = ContactHistory.new([1, 2])
    @ch.contactStart(10)
  end

  it 'should extract the node ids from the ContactHistory id' do
    @ch.node1.should == 1
    @ch.node2.should == 2
  end

  it 'should create new contacts and add them to the contact list' do
    cont = @ch.contacts.last
    cont.node1.should == 1
    cont.node2.should == 2
    cont.startTime.should == 10
    cont.should be_open
  end

  it 'should close the last contact' do
    @ch.contactEnd(15)
    cont = @ch.contacts.last
    cont.should_not be_open
  end

  it 'should count the contacts' do
    @ch.numberOfContacts.should == 1
  end

  it 'should sum the durations of the contacts' do
    @ch.contactEnd(10)
    100.times do |i|
      @ch.contactStart(11 + i*2)
      @ch.contactEnd(13 + i*2)
      
      @ch.totalContactDuration.should == (i+1)*2
      @ch.contactDurations.should == [0] + [2] * (i+1)
    end
  end

end
