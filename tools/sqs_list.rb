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

msg_count.to_i.times do
  q.receive_messages.each do |msg|
    puts msg.inspect
    message_id = msg["Message"][0]["MessageId"][0]
    body       = CGI.unescape(msg["Message"][0]["Body"][0])
    puts "Message #{message_id}"
    puts body
    puts
  end
end
