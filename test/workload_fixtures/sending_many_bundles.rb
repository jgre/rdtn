data  = 'a' * 5000
at 1 do |time|
  10.times {node(1).sendDataTo data, 'dtn://kasuari2/'}
  time < 120
end
