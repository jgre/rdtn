$:.unshift File.join(File.dirname(__FILE__), '../../sim')

require 'test/unit'
require 'rubygems'
require 'shoulda'
require 'combinationhash'
require 'yaml'

class TestCombinationHash < Test::Unit::TestCase

  def setup
    @hash = {
      :trace         => ['DieselNet', 'MIT', 'RWP'],
      :receiverCount => [1, 2, 3],
      :sendRate      => [4, 5, 6]
    }
    @res = Sim.hash_combinations(@hash)
  end

  should 'calculate a list of hashes with all possible value combinations' do
    assert_equal 27, @res.length
  end

  should 'assign one element from each key to the same key in each result hash' do
    @res.each do |h|
      h.each {|key, val| assert @hash[key].include?(val)}
    end
  end

  should 'assign each element from the input to the same number of outputs' do
    elements = @hash.values.flatten.compact
    elements.each do |el|
      occurences = @res.find_all {|h| h.any? {|k,v| v == el}}
      assert_equal 9, occurences.length
    end
  end

  should 'return a list with an empty hash, when given an empty hash' do
    assert_equal [{}], Sim.hash_combinations({})
  end

  should 'ignore entries that are not enumerable' do
    ret = Sim.hash_combinations({:a => [1], :b => 2})
    assert_equal [{:a => 1, :b => 2}], ret
  end

  should 'generate alternatives for hashes with one entry' do
    ret = Sim.hash_combinations({:a => [1,2,3]})
    assert_equal [{:a => 1}, {:a => 2}, {:a => 3}], ret
  end

end
