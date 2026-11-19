# Tessell::Text — FontStack 与系统字体发现（issue #7）
#
# 应用层字体栈：按优先级排列的多张 face（regular/bold/fallback），
# FontStack#pick(text) 用真实 cmap 覆盖（FtMeasurer#covers?）选出
# 覆盖整段文本的第一张脸。保留单 FtMeasurer 底层 API 不变。
#
# 宿主用法（atlas 共享，font_id 区分脸，批按页合批）：
#   atlas = GlyphAtlas.new
#   stack = FontStack.open([
#     {path: regular_path, ttc_index: 0, weight: FontStack::Weight::Regular},
#     {path: bold_path,    ttc_index: 0, weight: FontStack::Weight::Bold},
#   ])
#   stack.faces.each do |face|
#     rasterizers[face] = Rasterizer.new(face.measurer, atlas, face.font_id)
#     renderers[face]   = TextRenderer.new(atlas, rasterizers[face])
#   end
#   face = stack.pick(text)            # 未命中覆盖时返回 nil，应用自行回退
#   renderers[face].append_text_cached(...)
#
# Fallback 边界（诚实口径）：选脸粒度是**整段文本**，不是逐字形——
# 混排（如 emoji + 中文）需要应用按段拆分后分别 pick；逐字形混合
# shaping 不在本 API 范围。CJK/emoji 的自动发现先做文件名模式匹配；
# 集合内按 sfnt family 选 face 由 SystemFonts.find_face / FontStack.open
# 的 family 通道提供（issue #55）。

require "./ft_measurer"

module Tessell
  module Text
    class FontStack
      enum Weight
        Regular
        Bold
        Fallback
      end

      class Face
        getter measurer : FtMeasurer
        getter weight : Weight
        getter label : String
        getter font_id : Int32

        def initialize(@measurer : FtMeasurer, @weight : Weight, @label : String,
                       @font_id : Int32)
        end

        def covers?(text : String) : Bool
          @measurer.covers?(text)
        end
      end

      @faces : Array(Face)

      def initialize(@faces)
      end

      # 打开多张 face；font_id 按数组顺序分配（= atlas 的 font 维度）。
      def self.open(entries : Array({path: String, ttc_index: Int32,
                                     weight: Weight, label: String})) : FontStack
        faces = entries.map_with_index do |e, i|
          Face.new(FtMeasurer.open(e[:path], e[:ttc_index]), e[:weight],
            e[:label], i)
        end
        FontStack.new(faces)
      end

      # family 通道（issue #55）：entry 带 family 时在该文件的 face 集合内
      # 按 sfnt family 解析 ttc_index（nameID 16 优先）；解析失败保留显式
      # ttc_index 并一次性 warning。显式 ttc_index 通道不变。
      def self.open(entries : Array({path: String, ttc_index: Int32,
                                     weight: Weight, label: String,
                                     family: String?})) : FontStack
        faces = entries.map_with_index do |e, i|
          idx = e[:ttc_index]
          if fam = e[:family]
            idx = SystemFonts.match_family_index(e[:path], fam) || begin
              SystemFonts.warn_family_fallback(e[:path], fam)
              idx
            end
          end
          Face.new(FtMeasurer.open(e[:path], idx), e[:weight], e[:label], i)
        end
        FontStack.new(faces)
      end

      getter faces : Array(Face)

      def face_count : Int32
        @faces.size
      end

      # 覆盖整段文本的第一张脸（按优先级）；无覆盖返回 nil。
      def pick(text : String) : Face?
        @faces.find { |f| f.covers?(text) }
      end

      # 按字重选脸（issue #29）：先找覆盖文本且字重匹配的 face；没有匹配
      # 字重的覆盖脸时退回第一个覆盖脸（缺 bold 时不至于拿到错宽度的脸）。
      def pick(text : String, weight : Weight) : Face?
        @faces.find { |f| f.weight == weight && f.covers?(text) } ||
          @faces.find { |f| f.covers?(text) }
      end

      # 选脸并测量：优先级第一的覆盖脸的度量（逻辑入口）。
      def measure(text : String, size : Float32) : Size
        if face = pick(text)
          face.measurer.measure(text, face.font_id, size, Float32::INFINITY)
        else
          Size.new(0.0_f32, 0.0_f32)
        end
      end

      def close : Nil
        @faces.each { |f| f.measurer.close }
      end
    end

    # 系统字体发现（issue #7）：标准目录扫描 + 文件名模式匹配。
    # 文件名筛选之后，集合内按 sfnt family 选 face 由 find_face /
    # match_family_index 提供（issue #55）；候选仍需应用/FontStack
    # 用 covers? 做真实覆盖验证。
    module SystemFonts
      EXTENSIONS = [".ttf", ".otf", ".ttc"]

      # family 未命中退回 index 0 的一次性告警（不静默；进程内只提示一次）。
      @@family_fallback_warned = false

      def self.warn_family_fallback(path : String, family : String) : Nil
        return if @@family_fallback_warned
        @@family_fallback_warned = true
        STDERR.puts "SystemFonts: family \"#{family}\" 未命中任何 face，退回 ttc_index 0（#{path}）"
      end

      # 单文件 face 集合内按 family 匹配 index（大小写不敏感精确匹配）；
      # 未命中返回 nil。读 sfnt name 表（nameID 16 优先）。
      def self.match_family_index(path : String, family : String) : Int32?
        fam = family.downcase
        n = FtMeasurer.num_faces_of(path)
        i = 0
        while i < n
          if (f = FtMeasurer.face_family(path, i)) && f.downcase == fam
            return i
          end
          i += 1
        end
        nil
      end

      # 各平台标准字体目录（存在才返回）。
      def self.search_dirs : Array(String)
        dirs = [] of String
        {% if flag?(:darwin) %}
          dirs << "/System/Library/Fonts"
          dirs << "/System/Library/Fonts/Supplemental"
          dirs << "/Library/Fonts"
          dirs << "#{ENV["HOME"]}/Library/Fonts" if ENV["HOME"]?
        {% elsif flag?(:windows) %}
          windir = ENV["WINDIR"]? || "C:\\Windows"
          dirs << "#{windir}\\Fonts"
        {% else %}
          dirs << "/usr/share/fonts"
          dirs << "/usr/local/share/fonts"
          dirs << "#{ENV["HOME"]}/.local/share/fonts" if ENV["HOME"]?
        {% end %}
        dirs.select { |d| Dir.exists?(d) }
      end

      # 递归列出候选字体文件。
      def self.candidates : Array(String)
        found = [] of String
        search_dirs.each do |dir|
          walk(dir, found)
        end
        found
      end

      # 第一个文件名包含任一 pattern（大小写不敏感）的字体文件。
      # 例：SystemFonts.find(["msyh", "pingfang", "noto sans cjk"])
      def self.find(patterns : Array(String)) : String?
        lowered = patterns.map(&.downcase)
        candidates.find do |path|
          name = File.basename(path).downcase
          EXTENSIONS.any? { |ext| name.ends_with?(ext) } &&
            lowered.any? { |p| name.includes?(p) }
        end
      end

      # 文件名筛候选 + 集合内按 family 选 face（issue #55）。
      # 返回 {path, ttc_index}；family 为 nil 时等价 find(...) 的 index 0。
      # family 未命中任何 face 时退回第一个候选 index 0 并一次性 warning。
      def self.find_face(patterns : Array(String),
                         family : String? = nil) : {path: String, ttc_index: Int32}?
        lowered = patterns.map(&.downcase)
        hits = candidates.select do |path|
          name = File.basename(path).downcase
          EXTENSIONS.any? { |ext| name.ends_with?(ext) } &&
            lowered.any? { |p| name.includes?(p) }
        end
        return nil if hits.empty?
        first = hits.first
        return {path: first, ttc_index: 0} if family.nil?

        hits.each do |path|
          if idx = match_family_index(path, family)
            return {path: path, ttc_index: idx}
          end
        end
        warn_family_fallback(first, family)
        {path: first, ttc_index: 0}
      end

      private def self.walk(dir : String, sink : Array(String)) : Nil
        Dir.each_child(dir) do |child|
          full = File.join(dir, child)
          if Dir.exists?(full)
            walk(full, sink)
          elsif File.file?(full)
            name = child.downcase
            sink << full if EXTENSIONS.any? { |ext| name.ends_with?(ext) }
          end
        end
      end
    end
  end
end
