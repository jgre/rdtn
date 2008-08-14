$:.unshift File.join(File.dirname(__FILE__), '../../sim/stats')

require 'rubygems'
require 'test/unit'
require 'shoulda'
require 'statbundle'

class StatBundleTest < Test::Unit::TestCase

  context 'A StatBundle' do

    setup do
      @dest   = "dtn://dest/tag"
      @src    = "dtn://src/tag"
      @bid    = 12345
      @size   = 1024
      @bundle = StatBundle.new(@dest, @src, @bid, @size)
    end

  end

end
