# Screenshot helper for GL examples (task-145).
# Captures current frame after SwapBuffers and writes TSRAW.
# Format: "TSRAW <w> <h> RGBA\n" + w*h*4 bytes, top-down RGBA.

module TessellShot
  GL_PACK_ALIGNMENT = 0x0D05_u32
  GL_RGBA           = 0x1908_u32
  GL_UNSIGNED_BYTE  = 0x1401_u32
  GL_READ_BUFFER    = 0x0C02_u32
  GL_FRONT          = 0x0404_u32

  lib GL
    fun glFinish : Void
    fun glPixelStorei(pname : UInt32, param : Int32) : Void
    fun glReadPixels(x : Int32, y : Int32, width : Int32, height : Int32,
                     format : UInt32, type : UInt32, pixels : Void*) : Void
    fun glReadBuffer(mode : UInt32) : Void
  end

  def self.save(path : String, width : Int32, height : Int32) : Nil
    return if path.empty? || width <= 0 || height <= 0
    dir = File.dirname(path)
    Dir.mkdir_p(dir) unless Dir.exists?(dir)
    size = width * height * 4
    buf = Bytes.new(size)
    GL.glFinish
    GL.glReadBuffer(GL_FRONT)
    GL.glPixelStorei(GL_PACK_ALIGNMENT, 1)
    GL.glReadPixels(0, 0, width, height, GL_RGBA, GL_UNSIGNED_BYTE, buf.to_unsafe.as(Void*))
    flipped = Bytes.new(size)
    row_bytes = width * 4
    y = 0
    while y < height
      src = (height - 1 - y) * row_bytes
      dst = y * row_bytes
      (flipped.to_unsafe + dst).copy_from(buf.to_unsafe + src, row_bytes)
      y += 1
    end
    File.open(path, "wb") do |io|
      io.print "TSRAW #{width} #{height} RGBA\n"
      io.write(flipped)
    end
  end
end
