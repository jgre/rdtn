class Array
  def mean
    return 0 if empty?
    inject(0){|sum, x| sum+x} / length.to_f
  end

  def stdev
    return 0 if empty?
    Math.sqrt(inject(0) {|sum, x| sum + (x-mean)**2} / (length-1))
  end

  def sterror
    return 0 if empty?
    stdev / Math.sqrt(length.to_f)
  end
end
