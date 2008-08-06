$:.unshift File.join(File.dirname(__FILE__), '../../sim/stats')

require 'contact'

describe Contact do

  before(:each) do
    @contact = Contact.new(1, 2, 987)
  end

  it 'should store two node ids and two timestamps' do
    @contact.node1.should == 1
    @contact.node2.should == 2
    @contact.startTime.should == 987
  end

  it 'should initialize endTime with nil' do
    @contact.endTime.should be_nil
  end

  it 'should store endTime when set' do
    @contact.endTime = 1000
    @contact.endTime.should == 1000
  end

  it 'should be open when the startTime is set and the endTime is nil' do
    @contact.should be_open
  end

  it 'should NOT be open when the startTime is nil' do
    cont = Contact.new(1, 2, nil)
    cont.should_not be_open
  end

  it 'should NOT be open when the endTime is set' do
    @contact.endTime = 1000
    @contact.should_not be_open
  end

  it 'should have a duration of 0 when it is open' do
    @contact.duration.should be_zero
  end

  it 'should have a duration of 0 when startTime is nil' do
    cont = Contact.new(1, 2, nil)
    cont.duration.should be_zero
  end

  it 'should have a duration equal to the difference of start and end time' do
    @contact.endTime = 1000
    @contact.duration.should == 1000 - 987
  end

  it 'should have 0 costs if endTime is nil and startTime is in the past' do
    @contact.cost(1000).should be_zero
  end

  it 'should have 0 costs if startTime is past and endTime is in the future' do
    @contact.endTime = 1000
    @contact.cost(999).should be_zero
  end

  it 'should have infinite costs if the endTime is in the past' do
    @contact.endTime = 1000
    @contact.cost(1001).should be_nil
  end

  it 'should have costs equal to the delay if startTime is in the future' do
    @contact.cost(980).should == 7
  end

end
