class Array
  def mean
    inject(0){|sum, x| sum+x} / length.to_f
  end

  def stdev
    Math.sqrt(inject(0) {|sum, x| sum + (x-mean)**2} / (length-1))
  end

  def sterror
    stdev / Math.sqrt(length.to_f)
  end
end
