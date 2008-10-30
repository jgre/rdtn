nodemap = {}

def map_node(nodemap, node)
  nodemap[node] ||= nodemap.length
end

while line = gets do
  if /@\d+(\.\d+)? (\w+) <-> (\w+) (up|down)/ =~ line
    puts line.sub(/\w+ <-> \w+/, "#{map_node(nodemap, $2)} <-> #{map_node(nodemap, $3)}")
  end
end
