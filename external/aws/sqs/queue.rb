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
    class Queue  
      attr_reader :name

      def initialize(name, sqs_client)
	@name, @sqs_client = name, sqs_client
      end

      # Send a message to your queue
      def send_message(body)
	params = {}
	params['MessageBody'] = body
	result = @sqs_client.make_request('SendMessage', self.name, params)
	unless result.include?('Error')
	  return result['SendMessageResult'][0]['MessageId'][0].to_s
	else
	  raise Exception, "Amazon SQS Error Code :" + result['Error'][0]['Code'][0] + "\n" + result['Error'][0]['Message'][0]
	end
      end

      # Get a message(s) from your queue
      def receive_messages(max_number_of_messages = -1, visibility_timeout = -1)
	params = {}
	params['MaxNumberOfMessages'] = max_number_of_messages.to_s if max_number_of_messages > -1
	params['VisibilityTimeout'] = visibility_timeout.to_s if visibility_timeout > -1
	result = @sqs_client.make_request('ReceiveMessage', self.name, params)
	unless result.include?('Error')
	  return result['ReceiveMessageResult']
	else
	  raise Exception, "Amazon SQS Error Code :" + result['Error'][0]['Code'][0] + "\n" + result['Error'][0]['Message'][0]
	end
      end

      # Delete a message
      def delete_message(receipt_handle)
	params = {}
	params['ReceiptHandle'] = receipt_handle
	result = @sqs_client.make_request('DeleteMessage', self.name, params)
	unless result.include?('Error')
	  return true
	else
	  raise Exception, "Amazon SQS Error Code :" + result['Error'][0]['Code'][0] + "\n" + result['Error'][0]['Message'][0]
	end
      end

      # Get a queue attribute
      def get_queue_attributes(attribute)
	params = {}
	params['AttributeName'] = attribute
	result = @sqs_client.make_request('GetQueueAttributes', self.name, params)
	unless result.include?('Error')
	  return result['GetQueueAttributesResult'][0]['Attribute'][0]["Value"][0]
	else
	  raise Exception, "Amazon SQS Error Code :" + result['Error'][0]['Code'][0] + "\n" + result['Error'][0]['Message'][0]
	end
      end

    end
  end
end
