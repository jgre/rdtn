#!/usr/bin/env ruby
$:.unshift File.join(File.dirname(__FILE__), '../external/aws-s3/lib')

require 'aws/s3'

key, file = ARGV


AMAZON_ACCESS_KEY_ID     = ENV['AMAZON_ACCESS_KEY_ID']
AMAZON_SECRET_ACCESS_KEY = ENV['AMAZON_SECRET_ACCESS_KEY']
BUCKET   = 'jgre-rdtnsim-results'
AWS::S3::Base.establish_connection!(:access_key_id => AMAZON_ACCESS_KEY_ID, :secret_access_key => AMAZON_SECRET_ACCESS_KEY)
AWS::S3::Bucket.create('jgre-rdtnsim-results')

puts "Storing #{key} -> #{file}"

AWS::S3::S3Object.store key, open(file), BUCKET
