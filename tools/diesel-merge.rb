def diesel_date(str)
  if str =~ /(\d{1,2})(\d{2})(\d{4})/
    Time.gm($3, $1, $2)
  end
end

def map_node(nodemap, node)
  nodemap[node] ||= nodemap.length
end

dir = ARGV[0]
nodemap = {}

Dir.glob(File.join(dir, "[0-9]*")).sort.each do |fname|
  day = diesel_date(fname)
  open(fname) do |f|
    f.each_line do |line|
      if /^([\w:]+) ([\w:]+) (\d{2}):(\d{2}):(\d{2}) (\d+) (.*)/ =~ line
        node1 = map_node(nodemap, $1)
        node2 = map_node(nodemap, $2)
        date  = day + (3600*$3.to_i) + (60*$4.to_i) + ($5.to_i)
        puts "#{node1} #{node2} #{date.to_i} #{$6}"
      end
    end
  end
end
