[6, 8, 10, 12, 13].each {|n| node(n).register('dtn:group1') {}}

at 120 do |time|
  node(1).sendBundle Bundling::Bundle.new('test', 'dtn:group1', nil, 
                                          :multicast => true)
  time < 3600
end
