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

require 'test/unit'
require 'configuration'
 

class TestConfig < Test::Unit::TestCase

  def test_rubyHash_instead_optString 
    options = RdtnConfig::Reader::hash_to_optString()
    assert_equal("", options)

    options = RdtnConfig::Reader::hash_to_optString({:port => 8888})
    assert_equal("-p 8888", options)

    options = RdtnConfig::Reader::hash_to_optString({:host => "localhost"})
    assert_equal("-h localhost", options)

    options = RdtnConfig::Reader::hash_to_optString({:port => 8888,
					   :host => "localhost"})
    assert_equal("-p 8888 -h localhost", options)

    assert_raise(ArgumentError){
      options = RdtnConfig::Reader::hash_to_optString({:unknown => 8888})
    }
  end

  def test_interface
    assert_raise(RuntimeError){
      RdtnConfig::Reader.new.interface(:noaction, :cl, "name")
    }
    assert_raise(RuntimeError){
      RdtnConfig::Reader.new.interface(:noaction, :cl, "name", {:port => "low"})
    }
  end

end #TestConfig
