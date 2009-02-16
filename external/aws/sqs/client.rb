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
    class Client
      require 'rubygems'
      require 'net/http'
      require 'openssl'
      require 'base64'
      require 'cgi'
      require 'time'
      require 'xmlsimple'

      attr_reader :endpoint

      # default options
      DEFAULT_SQS_OPTIONS = { :endpoint => "http://queue.amazonaws.com" }

      # Use hardcoded endpoint (default)
      # AWS::SQS::Client.new(X,X)
      # Specify endpoint
      # AWS::SQS::Client.new(X,X, :endpoint => 'http://queue.amazonaws.com')
      def initialize( aws_access_key_id, aws_secret_access_key, options = {} )
	@aws_access_key_id, @aws_secret_access_key = aws_access_key_id, aws_secret_access_key
	opts = DEFAULT_SQS_OPTIONS.merge(options)
	@endpoint = opts[:endpoint]
      end

      # Get an array of queues
      def list_queues()
	result = make_request('ListQueues')
	value = result['ListQueuesResult']
	puts result.to_s
	unless value.nil?
	  return value
	else
	  raise Exception, "Amazon SQS Error Code :" + result['Error'][0]['Code'][0] + "\n" + result['Error'][0]['Message'][0]
	end
      end

      # Create a new queue
      def create_queue(name)
	params = {}
	params['QueueName'] = name
	result = make_request('CreateQueue', queue = "", params)
	unless result.include?('Error')
	  return AWS::SQS::Queue.new(name, self)
	else
	  raise Exception, "Amazon SQS Error Code :" + result['Error'][0]['Code'][0] +
					 "\n" + result['Error'][0]['Message'][0]
	end
      end

      # Delete the specified queue
      #
      # Note: this will delete ALL messages in your queue, so use this function
      # with caution!
      def delete_queue(name)
	result = make_request('DeleteQueue', queue = name)
	unless result.include?('Error')
	  return true
	else
	  raise Exception, "Amazon SQS Error Code :" + result['Error'][0]['Code'][0] + "\n" + result['Error'][0]['Message'][0]
	end
      end

      # Send a query request and return a SimpleXML object
      def make_request(action, queue = "", params = {})
	# Add Actions
	params['Action'] = action
	params['Version'] = '2008-01-01'
	params['AWSAccessKeyId'] = @aws_access_key_id
	params['Expires']= (Time.now + 120).gmtime.iso8601
	params['SignatureVersion'] = '1'

	# Sign the string
	sorted_params = params.sort_by { |key,value| key.downcase }
	joined_params = sorted_params.collect { |key, value| key + value}
	string_to_sign = joined_params.join
	digest = OpenSSL::Digest::Digest.new('sha1')
	hmac = OpenSSL::HMAC.digest(digest, @aws_secret_access_key, string_to_sign)
	params['Signature'] = Base64.encode64(hmac).chomp

	# Construct request
	query = params.collect { |key, value| key + "=" + CGI.escape(value) }.join("&")

	# Set our query, keeping in mind that most (not all) actions require a
	# queue name in the URI
	if query["Action"] == "ListQueues" || query["Action"] == "CreateQueue"
	  query = "?" + query
	else
	  query = "/" + queue + "?" + query
	end

	# You should always retry a 5xx error, as some of these are expected
	retry_count = 0
	try_again = true
	uri = URI.parse(self.endpoint)
	http = Net::HTTP.new(uri.host, uri.port)
	request = Net::HTTP::Get.new(query)
	while try_again do
	  # Send Amazon SQS query to endpoint
	  response = http.start { |http|
	    http.request(request)
	  }
	  # Check if we should retry this request
	  if response == Net::HTTPServerError && retry_count <= 5
	    retry_count ++
	      sleep(retry_count / 4 * retry_count)
	  else
	    try_again = false
	    xml = response.body.to_s
	    return XmlSimple.xml_in(xml)
	  end
	end
      end
    end # Client
  end # SQS
end # AWS
