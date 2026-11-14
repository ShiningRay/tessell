# TessellPNG / TessellGolden — PNG 输出与 golden-image 回归（issue #9）
#
# 零依赖 PNG 读写：zlib 使用 stored（无压缩）块，任何标准 PNG 解码器可读；
# 读取端仅支持本工具写出的格式（color type 6 RGBA、非隔行、stored zlib），
# 读到压缩块时报错并提示用本工具重生成——不假装支持任意 PNG。
# TSRAW（"TSRAW <w> <h> RGBA\n" + top-down RGBA）与本格式互相转换。

module TessellPNG
  CRC_TABLE = begin
    t = Array(UInt32).new(256, 0_u32)
    256.times do |n|
      c = n.to_u32
      8.times do
        c = (c & 1_u32) != 0 ? (0xedb88320_u32 ^ (c >> 1)) : (c >> 1)
      end
      t[n] = c
    end
    t
  end

  def self.crc32(data : Bytes, seed : UInt32 = 0xffffffff_u32) : UInt32
    c = seed
    data.each do |b|
      c = CRC_TABLE[(c ^ b) & 0xff] ^ (c >> 8)
    end
    c ^ 0xffffffff_u32
  end

  private def self.adler32(data : Bytes) : UInt32
    a = 1_u32
    b = 0_u32
    data.each do |byte|
      a = (a + byte) % 65521
      b = (b + a) % 65521
    end
    (b << 16) | a
  end

  private def self.chunk(io : IO, type : String, payload : Bytes) : Nil
    io.write_bytes(payload.size.to_u32, IO::ByteFormat::BigEndian)
    io.write(type.to_slice)
    io.write(payload)
    crc_data = Bytes.new(type.bytesize + payload.size)
    type.to_slice.copy_to(crc_data)
    payload.copy_to(crc_data + type.bytesize)
    io.write_bytes(crc32(crc_data), IO::ByteFormat::BigEndian)
  end

  private def self.zlib_stored(raw : Bytes) : Bytes
    out_buf = IO::Memory.new
    out_buf.write_byte(0x78_u8) # CMF/FLG：deflate 32K，最速校验
    out_buf.write_byte(0x01_u8)
    pos = 0
    while pos < raw.size
      n = Math.min(65535, raw.size - pos)
      last = pos + n >= raw.size
      out_buf.write_byte(last ? 0x01_u8 : 0x00_u8) # BFINAL|BTYPE=stored
      out_buf.write_bytes(n.to_u16, IO::ByteFormat::LittleEndian)
      out_buf.write_bytes((65535 - n).to_u16, IO::ByteFormat::LittleEndian)
      out_buf.write(raw[pos, n])
      pos += n
    end
    out_buf.write_bytes(adler32(raw), IO::ByteFormat::BigEndian)
    out_buf.to_slice
  end

  # 写 RGBA（top-down）为 PNG（color type 6）。带 1 字节 filter=0 每行。
  def self.write(path : String, width : Int32, height : Int32, rgba : Bytes) : Nil
    raise ArgumentError.new("rgba size mismatch") if rgba.size != width * height * 4
    Dir.mkdir_p(File.dirname(path)) unless Dir.exists?(File.dirname(path))
    raw = Bytes.new(height * (1 + width * 4))
    row = width * 4
    y = 0
    while y < height
      raw[y * (1 + row)] = 0_u8
      src = rgba.to_unsafe + y * row
      dst = raw.to_unsafe + y * (1 + row) + 1
      dst.copy_from(src, row)
      y += 1
    end
    File.open(path, "wb") do |io|
      io.write("\x89PNG\r\n\x1a\n".to_slice)
      ihdr = IO::Memory.new(13)
      ihdr.write_bytes(width.to_u32, IO::ByteFormat::BigEndian)
      ihdr.write_bytes(height.to_u32, IO::ByteFormat::BigEndian)
      ihdr.write_byte(8_u8)  # bit depth
      ihdr.write_byte(6_u8)  # color type RGBA
      ihdr.write_byte(0_u8)  # compression
      ihdr.write_byte(0_u8)  # filter
      ihdr.write_byte(0_u8)  # interlace
      chunk(io, "IHDR", ihdr.to_slice)
      chunk(io, "IDAT", zlib_stored(raw))
      chunk(io, "IEND", Bytes.new(0))
    end
  end

  # 读取本工具写出的 PNG（color type 6、非隔行、stored zlib）→ top-down RGBA。
  def self.read_rgba(path : String) : {Int32, Int32, Bytes}
    data = File.read(path).to_slice
    raise ArgumentError.new("not a PNG: #{path}") unless data[0, 8] == "\x89PNG\r\n\x1a\n".to_slice
    pos = 8
    width = 0
    height = 0
    idat = IO::Memory.new
    color_type = -1
    bit_depth = -1
    interlace = -1
    while pos + 8 <= data.bytesize
      l0 = data[pos]; l1 = data[pos + 1]; l2 = data[pos + 2]; l3 = data[pos + 3]
      chunk_len = (l0.to_u32 << 24) | (l1.to_u32 << 16) | (l2.to_u32 << 8) | l3.to_u32
      ctype = String.new(data[pos + 4, 4])
      payload = data[pos + 8, chunk_len]
      if ctype == "IHDR"
        w0 = payload[0].to_u32; w1 = payload[1].to_u32; w2 = payload[2].to_u32; w3 = payload[3].to_u32
        h0 = payload[4].to_u32; h1 = payload[5].to_u32; h2 = payload[6].to_u32; h3 = payload[7].to_u32
        width = ((w0 << 24) | (w1 << 16) | (w2 << 8) | w3).to_i
        height = ((h0 << 24) | (h1 << 16) | (h2 << 8) | h3).to_i
        bit_depth = payload[8]
        color_type = payload[9].to_i
        interlace = payload[12]
      elsif ctype == "IDAT"
        idat.write(payload)
      elsif ctype == "IEND"
        break
      end
      pos += 12 + chunk_len
    end
    raise ArgumentError.new("unsupported PNG: bit_depth=#{bit_depth} color=#{color_type} interlace=#{interlace} (writer outputs 8/6/0)") unless bit_depth == 8 && color_type == 6 && interlace == 0
    raw = inflate_stored(idat.to_slice)
    stride = 1 + width * 4
    raise ArgumentError.new("IDAT size mismatch") if raw.size != height * stride
    rgba = Bytes.new(width * height * 4)
    y = 0
    while y < height
      row_start = y * stride
      raise ArgumentError.new("row filter #{raw[row_start]} not supported") if raw[row_start] != 0
      src = raw.to_unsafe + row_start + 1
      dst = rgba.to_unsafe + y * width * 4
      dst.copy_from(src, width * 4)
      y += 1
    end
    {width, height, rgba}
  end

  private def self.inflate_stored(z : Bytes) : Bytes
    raise ArgumentError.new("bad zlib header") if z.size < 6 || (z[0] & 0x0f) != 8
    out = IO::Memory.new
    pos = 3 # zlib 头 2 字节 + BFINAL/BTYPE 1 字节
    payload_end = z.size - 4 # 去掉 adler32
    while pos + 4 <= payload_end
      n = z[pos].to_i | (z[pos + 1].to_i << 8)
      nlen = z[pos + 2].to_i | (z[pos + 3].to_i << 8)
      raise ArgumentError.new("compressed (non-stored) zlib block; regenerate with TessellPNG.write") if n != 65535 - nlen
      raise ArgumentError.new("truncated stored block") if pos + 4 + n > payload_end
      out.write(z[pos + 4, n]) if n > 0
      break if n == 0
      # 下一块：n 起点前还有 1 字节 BFINAL/BTYPE
      pos += 4 + n + 1
    end
    out.to_slice
  end

  # Netpbm P6（PPM，RGB 3B/px，top-down）→ RGBA bytes（含尺寸）。
  def self.from_ppm(path : String) : {Int32, Int32, Bytes}
    File.open(path, "rb") do |io|
      magic = io.read_line.strip
      raise ArgumentError.new("not P6 PPM: #{magic.inspect}") unless magic == "P6"
      line = ""
      width = 0
      height = 0
      # 跳过注释与空白，取宽高两行
      while line = io.read_line
        break unless line.empty? || line.starts_with?("#")
      end
      dims = line.split
      width = dims[0].to_i
      height = dims[1].to_i
      maxval_line = io.read_line
      raise ArgumentError.new("unsupported PPM maxval") unless maxval_line.strip == "255"
      rgb = Bytes.new(width * height * 3)
      io.read_fully(rgb)
      rgba = Bytes.new(width * height * 4)
      i = 0
      j = 0
      while i < rgba.size
        rgba[i] = rgb[j]
        rgba[i + 1] = rgb[j + 1]
        rgba[i + 2] = rgb[j + 2]
        rgba[i + 3] = 255_u8
        i += 4
        j += 3
      end
      {width, height, rgba}
    end
  end

  # TSRAW → RGBA bytes（含尺寸）。
  def self.from_tsraw(path : String) : {Int32, Int32, Bytes}
    File.open(path, "rb") do |io|
      header = io.read_line
      raise ArgumentError.new("not TSRAW: #{header.inspect}") unless header.starts_with?("TSRAW ")
      parts = header.split
      width = parts[1].to_i
      height = parts[2].to_i
      buf = Bytes.new(width * height * 4)
      io.read_fully(buf)
      {width, height, buf}
    end
  end
end

module TessellGolden
  struct Result
    getter diff_pixels : Int32
    getter max_channel_diff : Int32
    getter width : Int32
    getter height : Int32

    def initialize(@diff_pixels : Int32, @max_channel_diff : Int32,
                   @width : Int32, @height : Int32)
    end

    def pass?(max_diff_pixels : Int32) : Bool
      @diff_pixels <= max_diff_pixels
    end
  end

  # 比较 baseline 与 current（PNG 或 TSRAW）。diff 图：差异像素标红、其余压暗。
  def self.compare(baseline : String, current : String, diff_path : String? = nil) : Result
    bw, bh, base = load(baseline)
    cw, ch, cur = load(current)
    unless bw == cw && bh == ch
      raise ArgumentError.new("size mismatch: baseline #{bw}x#{bh} vs current #{cw}x#{ch}")
    end
    n = bw * bh * 4
    diff_pixels = 0
    max_diff = 0
    diff_rgba = Bytes.new(n)
    i = 0
    px = 0
    while i < n
      d0 = (base[i].to_i - cur[i].to_i).abs
      d1 = (base[i + 1].to_i - cur[i + 1].to_i).abs
      d2 = (base[i + 2].to_i - cur[i + 2].to_i).abs
      d3 = (base[i + 3].to_i - cur[i + 3].to_i).abs
      d = Math.max(Math.max(d0, d1), Math.max(d2, d3))
      if d > 0
        diff_pixels += 1
        max_diff = d if d > max_diff
        diff_rgba[i] = 220_u8
        diff_rgba[i + 1] = 32_u8
        diff_rgba[i + 2] = 32_u8
        diff_rgba[i + 3] = 255_u8
      else
        g = (base[i].to_i * 77 + base[i + 1].to_i * 151 + base[i + 2].to_i * 28) >> 8
        v = (g >> 1).to_u8
        diff_rgba[i] = v
        diff_rgba[i + 1] = v
        diff_rgba[i + 2] = v
        diff_rgba[i + 3] = 255_u8
      end
      i += 4
      px += 1
    end
    if dp = diff_path
      TessellPNG.write(dp, bw, bh, diff_rgba)
    end
    Result.new(diff_pixels, max_diff, bw, bh)
  end

  private def self.load(path : String) : {Int32, Int32, Bytes}
    if path.ends_with?(".png")
      TessellPNG.read_rgba(path)
    elsif path.ends_with?(".tsraw")
      TessellPNG.from_tsraw(path)
    elsif path.ends_with?(".ppm") || path.ends_with?(".pnm")
      TessellPNG.from_ppm(path)
    else
      raise ArgumentError.new("unsupported image format: #{path}（.png / .tsraw / .ppm）")
    end
  end
end
