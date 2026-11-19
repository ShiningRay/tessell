# 跨平台测试字体解析（issue #61 X0）。
#
# 优先级：TESSELL_TEST_FONT（按类别 TESSELL_TEST_FONT / TESSELL_TEST_CJK /
# TESSELL_TEST_EMOJI）→ 平台标准候选 → nil。
# 返回 nil 时调用方用**顶层** pending "SKIP: 原因" 跳过该平台特有项——
# 不用 nested pending（Crystal 1.22 不允许嵌套 pending，直接 error）。
# 不把系统字体复制进仓库；CI 按平台安装对应字体（见 .github/workflows）。

module TestFonts
  # 常规拉丁字体（度量/光栅/shaping 主字体）
  LATIN_CANDIDATES = {% if flag?(:windows) %}
    ["C:/Windows/Fonts/arial.ttf", "C:/Windows/Fonts/segoeui.ttf",
     "C:/Windows/Fonts/calibri.ttf", "C:/Windows/Fonts/msyh.ttc"]
  {% elsif flag?(:darwin) %}
    ["/System/Library/Fonts/Supplemental/Arial.ttf",
     "/System/Library/Fonts/Helvetica.ttc"]
  {% else %}
    ["/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
     "/usr/share/fonts/truetype/noto/NotoSans-Regular.ttf",
     "/usr/share/fonts/ttf-dejavu/DejaVuSans.ttf"]
  {% end %}

  # CJK 字体（中文字形/多字面集合用例）
  CJK_CANDIDATES = {% if flag?(:windows) %}
    ["C:/Windows/Fonts/msyh.ttc", "C:/Windows/Fonts/simsun.ttc"]
  {% elsif flag?(:darwin) %}
    ["/System/Library/Fonts/PingFang.ttc",
     "/System/Library/Fonts/Hiragino Sans GB.ttc",
     "/System/Library/Fonts/Supplemental/Arial Unicode.ttf"]
  {% else %}
    ["/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc",
     "/usr/share/fonts/truetype/noto/NotoSansCJK-Regular.ttc",
     "/usr/share/fonts/truetype/wqy/wqy-zenhei.ttc"]
  {% end %}

  # COLR 彩色 emoji（Windows Segoe UI Emoji 是已验证样例；
  # macOS sbix / Linux CBDT 不走 COLR 路径，明确返回 nil 不冒充）
  EMOJI_CANDIDATES = {% if flag?(:windows) %}
    ["C:/Windows/Fonts/seguiemj.ttf"]
  {% else %}
    [] of String
  {% end %}

  # regular + bold 字体对（font_face spec）
  REGULAR_BOLD_PAIRS = {% if flag?(:windows) %}
    [{"C:/Windows/Fonts/arial.ttf", "C:/Windows/Fonts/arialbd.ttf"},
     {"C:/Windows/Fonts/segoeui.ttf", "C:/Windows/Fonts/segoeuib.ttf"}]
  {% elsif flag?(:darwin) %}
    [{"/System/Library/Fonts/Supplemental/Arial.ttf",
      "/System/Library/Fonts/Supplemental/Arial Bold.ttf"}]
  {% else %}
    [{"/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
      "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"}]
  {% end %}

  def self.first_existing(candidates : Array(String), env_key : String) : String?
    if override = ENV[env_key]?
      return override if File.exists?(override)
    end
    candidates.find { |path| File.exists?(path) }
  end

  def self.latin : String?
    first_existing(LATIN_CANDIDATES, "TESSELL_TEST_FONT")
  end

  def self.cjk : String?
    first_existing(CJK_CANDIDATES, "TESSELL_TEST_CJK")
  end

  def self.emoji_colr : String?
    first_existing(EMOJI_CANDIDATES, "TESSELL_TEST_EMOJI")
  end

  def self.regular_bold : Tuple(String, String)?
    if override = ENV["TESSELL_TEST_FONT"]?
      return {override, override} if File.exists?(override)
    end
    REGULAR_BOLD_PAIRS.find { |(r, b)| File.exists?(r) && File.exists?(b) }
  end
end
