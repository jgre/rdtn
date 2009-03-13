#!/usr/bin/env ruby
$:.unshift File.join(File.dirname(__FILE__), '../external/aws')

require 'sqs'
require 'sqs/client'
require 'sqs/queue'

AMAZON_ACCESS_KEY_ID     = ENV['AMAZON_ACCESS_KEY_ID']
AMAZON_SECRET_ACCESS_KEY = ENV['AMAZON_SECRET_ACCESS_KEY']
ENDPOINT = 'http://queue.amazonaws.com'
QUEUE    = 'jgre-rdtnsimspecs'

client   = AWS::SQS::Client.new(AMAZON_ACCESS_KEY_ID, AMAZON_SECRET_ACCESS_KEY,
				:endpoint => ENDPOINT)
q        = AWS::SQS::Queue.new(QUEUE, client)

msg_count = q.get_queue_attributes("ApproximateNumberOfMessages")
puts "Approximate Number of Messages: #{msg_count}"

loop do
  msg  = q.receive_messages(1)
  break if msg.empty? || msg[0].empty?
  body = CGI.unescape(msg[0]["Message"][0]["Body"][0])
  receipt_handle = msg[0]["Message"][0]["ReceiptHandle"][0]
  q.delete_message receipt_handle
  puts body.inspect
end

# msg_count.to_i.times do
#   q.receive_messages.each do |msg|
#     puts msg.inspect
#     message_id = msg["Message"][0]["MessageId"][0]
#     body       = CGI.unescape(msg["Message"][0]["Body"][0])
#     puts "Message #{message_id}"
#     puts body
#     puts
#   end
# end
