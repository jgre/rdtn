# Copyright 2007 Amazon Technologies, Inc.  Licensed under the Apache License,
# Version 2.0 (the "License"); you may not use this file except in compliance
# with the License. You may obtain a copy of the License at:
#
# http://aws.amazon.com/apache2.0
#
# This file is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS
# OF ANY KIND, either express or implied.  See the License for the specific
# language governing permissions and limitations under the License.

module AWS
  module SQS
    # strings are UTF-8 encoded
    $KCODE = "u" unless RUBY_VERSION =~ /^1\.9/
  end

  module VERSION #:nodoc:
    MAJOR = 0
    MINOR = 1
    TINY  = 3

    STRING = [MAJOR, MINOR, TINY].join('.')
  end
end

