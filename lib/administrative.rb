require "bundle"
require "sdnv"

class AdministrativeRecord
  
  BUNDLE_STATUS_REPORT = 0x10
  CUSTODY_SIGNAL = 0x20
  
  attr_accessor :recordTypeFlags, :creationTimestamp, :creationTimestampSeq,
  :eidLength, :srcEid

  # This class method receives the payload of a bundle whose
  # administrative flag is set and returns a filled object
  # of the appropriate class
  def AdministrativeRecord.parseBundle(bundle)
    # read the first byte of the payload to figure out type & flags
    typeAndFlags = bundle.payload[0]    
    
    # Create a new object of the desired class
    if ((typeAndFlags & BUNDLE_STATUS_REPORT) != 0)
      ar = BundleStatusReport.new
    elsif ((typeAndFlags & CUSTODY_SIGNAL) != 0)
      ar = CustodySignal.new
    else 
      rerror(self, "This administrative record type is not implemented")
    end
    
    # fill the rest of the object with the remaining payload
    ar.parseBundle(bundle)
    
    return ar
  end
  
  def initialize
    @recordTypeFlags = 0
  end
  
  def bundleStatusReport?
    (@recordTypeFlags & BUNDLE_STATUS_REPORT) != 0
  end
  
  def custodySignal?
    (@recordTypeFlags & CUSTODY_SIGNAL) != 0
  end
  
  def fragment=(set)
    @recordTypeFlags = set ? @recordTypeFlags | 0x1 : @recordTypeFlags & ~0x1
  end
  
  def fragment?
    (@recordTypeFlags & 0x1) != 0
  end
  
  # To serialize the flags into an 8bit value, append them to an empty string
  # (they get added as a single char)
  def to_s
    data = ""
    data << @recordTypeFlags
  end
  
  def bundleId
    "#{@srcEid}-#{@creationTimestamp}-#{@creationTimestampSeq}-#{@fragmentOffset}".hash
  end
  
end

class BundleStatusReport < AdministrativeRecord
  
  # reason code flags
  REASON_NO_ADDTL_INFO = 0x00
  REASON_LIFETIME_EXPIRED = 0x01
  REASON_FORWARDED_UNIDIR_LINK = 0x02
  REASON_TRANSMISSION_CANCELLED = 0x03
  REASON_DEPLETED_STORAGE = 0x04
  REASON_ENDPOINT_ID_UNINTELLIGIBLE = 0x05
  REASON_NO_ROUTE_TO_DEST = 0x06
  REASON_NO_TIMELY_CONTACT = 0x07
  REASON_BLOCK_UNINTELLIGIBLE = 0x08
  REASON_SECURITY_FAILED = 0x09
  
  attr_accessor :statusFlags, :reasonCode, :fragmentOffset, :fragmentLength,
                :receiptTime, :custAcceptTime, :forwardingTime, :deliveryTime,
                :deletionTime
  def initialize
    super
    
    # initialization of variables
    @recordTypeFlags = @recordTypeFlags | BUNDLE_STATUS_REPORT
    @statusFlags = 0
    @reasonCode = 0
    @fragmentOffset = nil
    @fragmentLength = nil
    @receiptTime = 0
    @custAcceptTime = 0
    @forwardingTime = 0
    @deliveryTime = 0
    @deletionTime = 0
    @creationTimestamp = 0
    @creationTimestampSeq = 0
    @eidLength = 0
    @srcEid = 0
  end
  
  def self.applicationAck(bundle)
    # generate reception SR
    bdsr = BundleStatusReport.new
    bdsr.reasonCode = BundleStatusReport::REASON_NO_ADDTL_INFO
    if (bundle.fragment?)
      bdsr.fragment = true
      bdsr.fragmentOffset = bundle.fragmentOffset
      bdsr.fragmentLength = bundle.aduLength
    end

    bdsr.ackedByApp = true
    bdsr.creationTimestamp = bundle.creationTimestamp
    bdsr.creationTimestampSeq = bundle.creationTimestampSeq
    bdsr.eidLength = bundle.srcEid.to_s.length
    bdsr.srcEid = bundle.srcEid.to_s

    b = Bundling::Bundle.new(bdsr.to_s)
    if (bundle.reportToEid.to_s != "dtn:none")
      b.destEid = bundle.reportToEid
    else
      b.destEid = bundle.srcEid
    end

    b.administrative = true
    b.lifetime = bundle.lifetime
    b
  end
  
  # To serialize the flags into an 8bit value, append them to an empty string
  # (they get added as a single char)
  def to_s
    data = ""
    data << @recordTypeFlags
    data << @statusFlags
    data << @reasonCode
    
    # if bundle fragment bit is set in status flags
    if (fragment?)
      data << Sdnv.encode(@fragmentOffset)
      data << Sdnv.encode(@fragmentLength)
    end
  
    # if bundle-received bit is set  
    if (bundleReceived?)
      data << Sdnv.encode(@receiptTime)
    end
    
    # if custody accepted bit is set
    if (custodyAccepted?)
      data << Sdnv.encode(@custAcceptTime)
    end
    
    # if bundle forwarded bit is set
    if (bundleForwarded?)
      data << Sdnv.encode(@forwardingTime)
    end
    
    # if bundle delivered bit is set
    if (bundleDelivered?)
      data << Sdnv.encode(@deliveryTime)
    end
    
    #if bundle deleted bit is set
    if (bundleDeleted?)
      data << Sdnv.encode(@deletionTime)
    end
      
    data << Sdnv.encode(@creationTimestamp)
    data << Sdnv.encode(@creationTimestampSeq)
    
    data << Sdnv.encode(@eidLength)
    data << @srcEid
  end
  
  def parseBundle(bundle)
    @recordTypeFlags = bundle.payload[0]
    @statusFlags = bundle.payload[1]
    @reasonCode = bundle.payload[2]
    
    plPos = 3 # the other data begins here
    # if bundle fragment bit is set in status flags
    if (fragment?)
      temp = Sdnv.decode(bundle.payload[plPos..bundle.payload.length])
      @fragmentOffset = temp[0]
      plPos += temp[1]
      
      temp = Sdnv.decode(bundle.payload[plPos..bundle.payload.length])
      @fragmentLength = temp[0]
      plPos += temp[1]
    end
  
    # if bundle-received bit is set  
    if (bundleReceived?)
      temp = Sdnv.decode(bundle.payload[plPos..bundle.payload.length])
      @receiptTime = temp[0]
      plPos += temp[1]
    end
    
    # if custody accepted bit is set
    if (custodyAccepted?)
      temp = Sdnv.decode(bundle.payload[plPos..bundle.payload.length])
      @custAcceptTime = temp[0]
      plPos += temp[1]
    end
    
    # if bundle forwarded bit is set
    if (bundleForwarded?)
      temp = Sdnv.decode(bundle.payload[plPos..bundle.payload.length])
      @forwardingTime = temp[0]
      plPos += temp[1]
    end
    
    # if bundle delivered bit is set
    if (bundleDelivered?)
      temp = Sdnv.decode(bundle.payload[plPos..bundle.payload.length])
      @deliveryTime = temp[0]
      plPos += temp[1]
    end
    
    #if bundle deleted bit is set
    if (bundleDeleted?)
      temp = Sdnv.decode(bundle.payload[plPos..bundle.payload.length])
      @deletionTime = temp[0]
      plPos += temp[1]
    end
    
    temp = Sdnv.decode(bundle.payload[plPos..bundle.payload.length])
    @creationTimestamp = temp[0]
    plPos += temp[1]
    
    temp = Sdnv.decode(bundle.payload[plPos..bundle.payload.length])
    @creationTimestampSeq = temp[0]
    plPos += temp[1]
    
    temp = Sdnv.decode(bundle.payload[plPos..bundle.payload.length])
    @eidLength = temp[0]
    plPos += temp[1]
    
    @srcEid = bundle.payload[plPos..(plPos + @eidLength)]
  end
  
  def bundleReceived=(set)
    @statusFlags = set ? @statusFlags | 0x1 : @statusFlags & ~0x1
  end
  
  def bundleReceived?
    (@statusFlags & 0x1) != 0
  end
  
  def custodyAccepted=(set)
    @statusFlags = set ? @statusFlags | 0x2 : @statusFlags & ~0x2
  end
  
  def custodyAccepted?
    (@statusFlags & 0x2) != 0
  end
  
  def bundleForwarded=(set)
    @statusFlags = set ? @statusFlags | 0x4 : @statusFlags & ~0x4
  end
  
  def bundleForwarded?
    (@statusFlags & 0x4) != 0
  end
  
  def bundleDelivered=(set)
    @statusFlags = set ? @statusFlags | 0x8 : @statusFlags & ~0x8
  end
  
  def bundleDelivered?
    (@statusFlags & 0x8) != 0
  end
  
  def bundleDeleted=(set)
    @statusFlags = set ? @statusFlags | 0x10 : @statusFlags & ~0x10
  end
  
  def bundleDeleted?
    (@statusFlags & 0x10) != 0
  end
  
  # not in rfc 5050 (nov 07), but in dtn 2.5.0
  def ackedByApp=(set)
    @statusFlags = set ? @statusFlags | 0x20 : @statusFlags & ~0x20
  end
  
  def ackedByApp?
    (@statusFlags & 0x20) != 0
  end
  
  def reasonToString(reasonFlags)
    case reasonFlags
    when REASON_NO_ADDTL_INFO
      "no additional information"
    when REASON_LIFETIME_EXPIRED
      "lifetime expired"
    when REASON_FORWARDED_UNIDIR_LINK
      "forwarded over unidirectional link"
    when REASON_TRANSMISSION_CANCELLED
      "transmission cancelled"
    when REASON_DEPLETED_STORAGE
      "depleted storage"
    when REASON_ENDPOINT_ID_UNINTELLIGIBLE
      "endpoint id unintelligible"
    when REASON_NO_ROUTE_TO_DEST
      "no known route to destination"
    when REASON_NO_TIMELY_CONTACT
      "no timely contact"
    when REASON_BLOCK_UNINTELLIGIBLE
      "block unintelligible"
    when REASON_SECURITY_FAILED
      "security failed"
    else
      "(unknown reason)"
    end
  end
end

class CustodySignal < AdministrativeRecord
  
  CUSTODY_NO_ADDTL_INFO = 0x00
  CUSTODY_REDUNDANT_RECEPTION = 0x03
  CUSTODY_DEPLETED_STORAGE = 0x04
  CUSTODY_ENDPOINT_ID_UNINTELLIGIBLE = 0x05
  CUSTODY_NO_ROUTE_TO_DEST = 0x06
  CUSTODY_NO_TIMELY_CONTACT = 0x07
  CUSTODY_BLOCK_UNINTELLIGIBLE = 0x08
  
  attr_accessor :status, :fragmentOffset, :fragmentLength, :signalTime
  
  def initialize
    super            
    
    @recordTypeFlags = @recordTypeFlags | CUSTODY_SIGNAL
    @status = 0
    @fragmentOffset = nil
    @fragmentLength = nil
    @signalTime = (Time.now - Time.gm(2000)).to_i
    @creationTimestamp = 0
    @creationTimestampSeq = 0
    @eidLength = 0
    @srcEid = 0
  end
  
  # To serialize the flags into an 8bit value, append them to an empty string
  # (they get added as a single char)
  def to_s
    data = ""
    data << @recordTypeFlags
    data << @status
    
    # if bundle fragment bit is set in status flags
    if (fragment?)
      data << Sdnv.encode(@fragmentOffset)
      data << Sdnv.encode(@fragmentLength)
    end
    
    data << Sdnv.encode(@signalTime)
    
    data << Sdnv.encode(@creationTimestamp)
    data << Sdnv.encode(@creationTimestampSeq)
    
    data << Sdnv.encode(@eidLength)
    data << @srcEid
  end
  
  def parseBundle(bundle)
    @recordTypeFlags = bundle.payload[0]
    @status = bundle.payload[1]
    
    plPos = 2 # the other data begins here
    
    # if bundle fragment bit is set in status flags
    if (fragment?)
      
      temp = Sdnv.decode(bundle.payload[plPos..bundle.payload.length])
      @fragmentOffset = temp[0]
      plPos += temp[1]
      
      temp = Sdnv.decode(bundle.payload[plPos..bundle.payload.length])
      @fragmentLength = temp[0]
      plPos += temp[1]
    end

    temp = Sdnv.decode(bundle.payload[plPos..bundle.payload.length])
    @signalTime = temp[0]
    plPos += temp[1]
        
    temp = Sdnv.decode(bundle.payload[plPos..bundle.payload.length])
    @creationTimestamp = temp[0]
    plPos += temp[1]
    
    temp = Sdnv.decode(bundle.payload[plPos..bundle.payload.length])
    @creationTimestampSeq = temp[0]
    plPos += temp[1]
    
    temp = Sdnv.decode(bundle.payload[plPos..bundle.payload.length])
    @eidLength = temp[0]
    plPos += temp[1]
    
    @srcEid = bundle.payload[plPos..(plPos + @eidLength)]
  end
  
  def transferSucceeded=(set)
    @status = set ? @status | 0x80 : @status & ~0x80
  end
  
  def transferSucceeded?
    (@status & 0x80) != 0
  end
  
  def reason
    (reasonFlags & 0b0111_1111)
  end
  
  def status=(s)
    @status = (@status & 0b1000_0000) + s
  end
  
  def reasonToString(reasonFlags)
    case (reasonFlags & 0b0111_1111)
    when CUSTODY_NO_ADDTL_INFO
      "no additional information"
    when CUSTODY_REDUNDANT_RECEPTION
      "redundant reception"
    when CUSTODY_DEPLETED_STORAGE
      "depleted storage"
    when CUSTODY_ENDPOINT_ID_UNINTELLIGIBLE
      "eid unintelligible"
    when CUSTODY_NO_ROUTE_TO_DEST
      "no route to dest"
    when CUSTODY_NO_TIMELY_CONTACT
      "no timely contact"
    when CUSTODY_BLOCK_UNINTELLIGIBLE
      "block unintelligible"
    else
      "(unknown reason #{reasonFlags})"
    end
  end
end
