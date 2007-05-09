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
#
# $Id: fileup.py 8 2006-12-22 20:00:21Z jgre $

$:.push("../lib")

require "test/unit"
require "rdtnlog"

class TestLogger < Test::Unit::TestCase


  def test_log1
    log=RdtnLogger.instance()
    log.level=Logger::DEBUG
    log.debug("testing RdtnLogger")

    foo=RdtnLogger.instance()
    foo.level=Logger::DEBUG
    foo.debug("testing RdtnLogger")

    assert(log.object_id==foo.object_id)
    
  end

end
