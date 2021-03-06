# encoding: ascii-8bit
require 'spec_helper'

describe Unpacker do
  let :unpacker do
    Unpacker.new
  end

  let :packer do
    Packer.new
  end

  # TODO initialize

  it 'read_array_header succeeds' do
    unpacker.feed("\x91")
    unpacker.read_array_header.should == 1
  end

  it 'read_array_header fails' do
    unpacker.feed("\x81")
    lambda {
      unpacker.read_array_header
    }.should raise_error(MessagePack::TypeError)
  end

  it 'read_map_header succeeds' do
    unpacker.feed("\x81")
    unpacker.read_map_header.should == 1
  end

  it 'read_map_header fails' do
    unpacker.feed("\x91")
    lambda {
      unpacker.read_map_header
    }.should raise_error(MessagePack::TypeError)
  end

  it 'skip_nil succeeds' do
    unpacker.feed("\xc0")
    unpacker.skip_nil.should == true
  end

  it 'skip_nil fails' do
    unpacker.feed("\x90")
    unpacker.skip_nil.should == false
  end

  it 'skip skips objects' do
    packer.write(1)
    packer.write(2)
    packer.write(3)
    packer.write(4)
    packer.write(5)

    unpacker = Unpacker.new(packer.buffer)

    unpacker.read.should == 1
    unpacker.skip
    unpacker.read.should == 3
    unpacker.skip
    unpacker.read.should == 5
  end

  it 'read raises EOFError' do
    lambda {
      unpacker.read
    }.should raise_error(EOFError)
  end

  it 'skip raises EOFError' do
    lambda {
      unpacker.skip
    }.should raise_error(EOFError)
  end

  it 'skip_nil raises EOFError' do
    lambda {
      unpacker.skip_nil
    }.should raise_error(EOFError)
  end

  it 'unpacks symbols of varying lengths' do
    small_symbol = :z
    medium_symbol = ('y' * (2**8)).to_sym
    large_symbol = ('x' * (2**16)).to_sym
    
    symbols = [small_symbol, medium_symbol, large_symbol]
    symbols.each { |sym| unpacker.feed(sym.to_msgpack) }
    
    unpacked_symbols = []
    unpacker.each do |sym|
      unpacked_symbols << sym
    end
    unpacked_symbols.should == symbols
  end

  let :sample_object do
    [1024, {["a","b"]=>["c","d"]}, ["e","f"], "d", 70000, 4.12, 1.5, 1.5, 1.5, {:i => :j}, Time.now]
  end

  it 'feed and each continue internal state' do
    raw = sample_object.to_msgpack.to_s * 4
    objects = []

    raw.split(//).each do |b|
      unpacker.feed(b)
      unpacker.each {|c|
        objects << c
      }
    end

    objects.should == [sample_object] * 4
  end

  it 'feed_each continues internal state' do
    raw = sample_object.to_msgpack.to_s * 4
    objects = []

    raw.split(//).each do |b|
      unpacker.feed_each(b) {|c|
        objects << c
      }
    end

    objects.should == [sample_object] * 4
  end

  it 'reset clears internal buffer' do
    # 1-element array
    unpacker.feed("\x91")
    unpacker.reset
    unpacker.feed("\x01")

    unpacker.each.map {|x| x }.should == [1]
  end

  it 'reset clears internal state' do
    # 1-element array
    unpacker.feed("\x91")
    unpacker.each.map {|x| x }.should == []

    unpacker.reset

    unpacker.feed("\x01")
    unpacker.each.map {|x| x }.should == [1]
  end

  it 'buffer' do
    o1 = unpacker.buffer.object_id
    unpacker.buffer << 'frsyuki'
    unpacker.buffer.to_s.should == 'frsyuki'
    unpacker.buffer.object_id.should == o1
  end

  it 'frozen short strings' do
    raw = sample_object.to_msgpack.to_s.force_encoding('UTF-8')
    lambda {
      unpacker.feed_each(raw.freeze) { }
    }.should_not raise_error
  end

  it 'frozen long strings' do
    raw = (sample_object.to_msgpack.to_s * 10240).force_encoding('UTF-8')
    lambda {
      unpacker.feed_each(raw.freeze) { }
    }.should_not raise_error
  end

  it 'read raises level stack too deep error' do
    512.times { packer.write_array_header(1) }
    packer.write(nil)

    unpacker = Unpacker.new(packer.buffer)
    lambda {
      unpacker.read
    }.should raise_error(MessagePack::StackError)
  end

  it 'skip raises level stack too deep error' do
    512.times { packer.write_array_header(1) }
    packer.write(nil)

    unpacker = Unpacker.new(packer.buffer)
    lambda {
      unpacker.skip
    }.should raise_error(MessagePack::StackError)
  end

  it 'read raises invalid byte error' do
    unpacker.feed("\xc1")
    lambda {
      unpacker.read
    }.should raise_error(MessagePack::MalformedFormatError)
  end

  it 'skip raises invalid byte error' do
    unpacker.feed("\xc1")
    lambda {
      unpacker.skip
    }.should raise_error(MessagePack::MalformedFormatError)
  end

  it "gc mark" do
    raw = sample_object.to_msgpack.to_s * 4

    n = 0
    raw.split(//).each do |b|
      GC.start
      unpacker.feed_each(b) {|o|
        GC.start
        o.should == sample_object
        n += 1
      }
      GC.start
    end

    n.should == 4
  end

  it "buffer" do
    orig = "a"*32*1024*4
    raw = orig.to_msgpack.to_s

    n = 655
    times = raw.size / n
    times += 1 unless raw.size % n == 0

    off = 0
    parsed = false

    times.times do
      parsed.should == false

      seg = raw[off, n]
      off += seg.length

      unpacker.feed_each(seg) {|obj|
        parsed.should == false
        obj.should == orig
        parsed = true
      }
    end

    parsed.should == true
  end

  it "msgpack str 8 type" do
    MessagePack.unpack([0xd9, 0x00].pack('C*')).should == ""
    MessagePack.unpack([0xd9, 0x01].pack('C*') + 'a').should == "a"
    MessagePack.unpack([0xd9, 0x02].pack('C*') + 'aa').should == "aa"
  end

  it "msgpack str 16 type" do
    MessagePack.unpack([0xda, 0x00, 0x00].pack('C*')).should == ""
    MessagePack.unpack([0xda, 0x00, 0x01].pack('C*') + 'a').should == "a"
    MessagePack.unpack([0xda, 0x00, 0x02].pack('C*') + 'aa').should == "aa"
  end

  it "msgpack str 32 type" do
    MessagePack.unpack([0xdb, 0x00, 0x00, 0x00, 0x00].pack('C*')).should == ""
    MessagePack.unpack([0xdb, 0x00, 0x00, 0x00, 0x01].pack('C*') + 'a').should == "a"
    MessagePack.unpack([0xdb, 0x00, 0x00, 0x00, 0x02].pack('C*') + 'aa').should == "aa"
  end

  it "msgpack bin 8 type" do
    MessagePack.unpack([0xc4, 0x00].pack('C*')).should == ""
    MessagePack.unpack([0xc4, 0x01].pack('C*') + 'a').should == "a"
    MessagePack.unpack([0xc4, 0x02].pack('C*') + 'aa').should == "aa"
  end

  it "msgpack bin 16 type" do
    MessagePack.unpack([0xc5, 0x00, 0x00].pack('C*')).should == ""
    MessagePack.unpack([0xc5, 0x00, 0x01].pack('C*') + 'a').should == "a"
    MessagePack.unpack([0xc5, 0x00, 0x02].pack('C*') + 'aa').should == "aa"
  end

  it "msgpack bin 32 type" do
    MessagePack.unpack([0xc6, 0x00, 0x00, 0x00, 0x00].pack('C*')).should == ""
    MessagePack.unpack([0xc6, 0x00, 0x00, 0x00, 0x01].pack('C*') + 'a').should == "a"
    MessagePack.unpack([0xc6, 0x00, 0x00, 0x00, 0x02].pack('C*') + 'aa').should == "aa"
  end
end

