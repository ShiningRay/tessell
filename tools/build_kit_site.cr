# Tessell Kit 静态文档站生成器（K5）
#
# 只转换 docs/kit 下的 Markdown 子集，不引入 Web 运行时或静态站依赖。
# 用法：crystal run tools/build_kit_site.cr
# 输出：site/kit/*.html 与 site/index.html

require "html"
require "file_utils"
require "set"

module KitSite
  record Page, title : String, source : String, output : String

  PAGES = [
    Page.new("概览", "docs/kit/index.md", "index.html"),
    Page.new("Button", "docs/kit/components/button.md", "components/button.html"),
    Page.new("Checkbox", "docs/kit/components/checkbox.md", "components/checkbox.html"),
    Page.new("Text", "docs/kit/components/text.md", "components/text.html"),
    Page.new("Input", "docs/kit/components/input.md", "components/input.html"),
    Page.new("Select", "docs/kit/components/select.md", "components/select.html"),
    Page.new("Tooltip", "docs/kit/components/tooltip.md", "components/tooltip.html"),
    Page.new("Dialog", "docs/kit/components/dialog.md", "components/dialog.html"),
    Page.new("ScrollView", "docs/kit/components/scroll-view.md", "components/scroll-view.html"),
    Page.new("VirtualList", "docs/kit/components/virtual-list.md", "components/virtual-list.html"),
    Page.new("设计 token", "docs/kit/design-tokens.md", "design-tokens.html"),
    Page.new("组件契约", "docs/kit/component-contract.md", "component-contract.html"),
    Page.new("仓策略", "docs/kit/repository-strategy.md", "repository-strategy.html"),
    Page.new("计划", "docs/kit/plan.md", "plan.html"),
    Page.new("跨平台方案", "docs/cross-platform-plan.md", "cross-platform.html"),
    Page.new("执行记录", "docs/kit/execution.md", "execution.html"),
    Page.new("K6 复核", "docs/kit/K6-review.md", "k6-review.html"),
    Page.new("示例应用", "docs/kit/apps.md", "apps.html"),
  ]

  STYLE = <<-CSS
    :root { color-scheme: light dark; --fg:#1f2328; --muted:#6b7280; --bg:#f6f7f9; --card:#fff; --border:#d5d9e0; --accent:#2f6fed; }
    @media (prefers-color-scheme: dark) { :root { --fg:#e7eaf0; --muted:#9aa4b2; --bg:#171a1f; --card:#1e2228; --border:#3a414c; --accent:#78a2ff; } }
    * { box-sizing: border-box; }
    body { margin:0; font: 15px/1.6 -apple-system, BlinkMacSystemFont, "Segoe UI", "Hiragino Sans GB", "Microsoft YaHei", sans-serif; color:var(--fg); background:var(--bg); }
    a { color:var(--accent); text-decoration:none; }
    a:hover { text-decoration:underline; }
    .layout { display:grid; grid-template-columns: 240px minmax(0, 1fr); min-height:100vh; }
    nav { padding:24px 18px; border-right:1px solid var(--border); background:var(--card); position:sticky; top:0; height:100vh; overflow:auto; }
    nav h1 { font-size:16px; margin:0 0 16px; }
    nav a { display:block; padding:4px 8px; border-radius:6px; color:var(--fg); }
    nav a:hover { background:var(--bg); }
    main { padding:32px clamp(20px, 5vw, 64px); max-width:920px; }
    h1, h2, h3 { line-height:1.25; margin:1.4em 0 .5em; }
    h1 { font-size:30px; margin-top:0; }
    h2 { font-size:22px; border-bottom:1px solid var(--border); padding-bottom:6px; }
    p, li { color:var(--fg); }
    code { background:rgba(127,127,127,.12); padding:1px 5px; border-radius:4px; font-size:.92em; }
    pre { background:var(--card); border:1px solid var(--border); border-radius:8px; padding:14px; overflow:auto; }
    pre code { background:none; padding:0; }
    .tok-kw { color:#cf222e; font-weight:600; }
    .tok-type { color:#0550ae; }
    .tok-str { color:#0a3069; }
    .tok-com { color:#6e7781; font-style:italic; }
    .tok-num { color:#953800; }
    .tok-sym { color:#8250df; }
    .tok-anno { color:#116329; }
    .tok-op { color:#cf222e; }
    @media (prefers-color-scheme: dark) {
      .tok-kw { color:#ff7b72; }
      .tok-type { color:#79c0ff; }
      .tok-str { color:#a5d6ff; }
      .tok-com { color:#8b949e; }
      .tok-num { color:#ffa657; }
      .tok-sym { color:#d2a8ff; }
      .tok-anno { color:#7ee787; }
      .tok-op { color:#ff7b72; }
    }
    blockquote { margin:16px 0; padding:8px 16px; border-left:3px solid var(--accent); color:var(--muted); background:var(--card); }
    table { border-collapse:collapse; width:100%; margin:16px 0; background:var(--card); }
    th, td { border:1px solid var(--border); padding:8px 10px; text-align:left; vertical-align:top; }
    th { background:rgba(127,127,127,.08); }
    .meta { color:var(--muted); font-size:13px; margin-bottom:24px; }
    main img { max-width:100%; height:auto; border:1px solid var(--border); border-radius:8px; margin:12px 0; }
    @media (max-width: 760px) { .layout { grid-template-columns: 1fr; } nav { position:static; height:auto; border-right:none; border-bottom:1px solid var(--border); } }
  CSS

  def self.build : Nil
    FileUtils.rm_rf("site/kit")
    FileUtils.mkdir_p("site/kit/components")
    PAGES.each do |page|
      html = render_page(page)
      path = File.join("site/kit", page.output)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, html)
      puts "wrote #{path}"
    end
    File.write("site/index.html", landing)
    puts "wrote site/index.html"
  end

  private def self.render_page(page : Page) : String
    source = File.read(page.source)
    title = source.lines.find(&.starts_with?("# ")).try(&.lchop("# ").strip) || page.title
    body = markdown_to_html(source)
    nav = PAGES.map do |p|
      %(<a href="#{relative(page.output, p.output)}">#{HTML.escape(p.title)}</a>)
    end.join("\n")
    <<-HTML
<!doctype html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>#{HTML.escape(title)} — Tessell Kit</title>
<style>#{STYLE}</style>
</head>
<body>
<div class="layout">
<nav>
<h1>Tessell Kit</h1>
#{nav}
</nav>
<main>
<div class="meta">来源：#{HTML.escape(page.source)}</div>
#{body}
</main>
</div>
</body>
</html>
HTML
  end

  private def self.landing : String
    <<-HTML
<!doctype html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Tessell Kit 文档</title>
<style>#{STYLE}</style>
</head>
<body>
<div class="layout">
<nav><h1>Tessell Kit</h1><a href="kit/index.html">组件文档</a></nav>
<main>
<h1>Tessell Kit</h1>
<p>Tessell 的 retained-mode 自绘组件库，同仓可选入口 <code>require "tessell/kit"</code>。</p>
<p><a href="kit/index.html">进入组件文档 →</a> · <a href="kit/cross-platform.html">跨平台方案 →</a></p>
<p><img src="previews/gallery-light.png" alt="Tessell Kit gallery light" style="max-width:100%;border:1px solid var(--border);border-radius:8px"></p>
<p class="meta">本页由 <code>tools/build_kit_site.cr</code> 生成；组件运行时与文档站解耦。</p>
</main>
</div>
</body>
</html>
HTML
  end

  private def self.relative(from : String, to : String) : String
    from_dir = File.dirname(from)
    return to if from_dir == "."
    depth = from_dir.split("/").reject(&.empty?).size
    ("../" * depth) + to
  end

  private def self.markdown_to_html(source : String) : String
    out = String::Builder.new
    paragraph = [] of String
    list_open = false
    table_lines = [] of String
    code_open = false
    code_lang = ""
    code = String::Builder.new

    flush_paragraph = -> do
      unless paragraph.empty?
        out << "<p>" << inline(paragraph.join(" ")) << "</p>\n"
        paragraph.clear
      end
    end
    close_list = -> do
      if list_open
        out << "</ul>\n"
        list_open = false
      end
    end
    flush_table = -> do
      unless table_lines.empty?
        out << render_table(table_lines)
        table_lines.clear
      end
    end

    source.lines.each do |line|
      if line.starts_with?("```")
        if code_open
          out << render_code_block(code.to_s, code_lang)
          code = String::Builder.new
          code_open = false
          code_lang = ""
        else
          flush_paragraph.call
          close_list.call
          flush_table.call
          code_open = true
          code_lang = line[3, line.size - 3].strip.downcase
        end
        next
      end
      if code_open
        code << line << "\n"
        next
      end

      stripped = line.strip
      if stripped.empty?
        flush_paragraph.call
        close_list.call
        flush_table.call
        next
      end

      if stripped.starts_with?("|")
        flush_paragraph.call
        close_list.call
        table_lines << stripped
        next
      else
        flush_table.call
      end

      if stripped.starts_with?("#")
        flush_paragraph.call
        close_list.call
        level = 0
        while level < stripped.size && stripped[level] == '#'
          level += 1
        end
        text = stripped[level, stripped.size - level].strip
        slug = slugify(text)
        out << "<h#{level} id=\"#{slug}\">#{inline(text)}</h#{level}>\n"
      elsif stripped.starts_with?("- ")
        flush_paragraph.call
        unless list_open
          out << "<ul>\n"
          list_open = true
        end
        out << "<li>" << inline(stripped[2..]) << "</li>\n"
      elsif stripped.starts_with?("> ")
        flush_paragraph.call
        close_list.call
        out << "<blockquote>" << inline(stripped[2..]) << "</blockquote>\n"
      else
        close_list.call
        paragraph << stripped
      end
    end

    flush_paragraph.call
    close_list.call
    flush_table.call
    if code_open
      out << render_code_block(code.to_s, code_lang)
    end
    out.to_s
  end

  private def self.render_code_block(source : String, lang : String) : String
    class_attr = lang.empty? ? "" : %( class="language-#{HTML.escape(lang)}")
    if lang == "crystal" || lang == "cr"
      "<pre><code#{class_attr}>#{highlight_crystal(source)}</code></pre>\n"
    else
      "<pre><code#{class_attr}>#{HTML.escape(source)}</code></pre>\n"
    end
  end

  CRYSTAL_KEYWORDS = %w[
    abstract alias and as begin break case class def do else elsif end ensure
    enum extend for fun getter if in include is_a? lib macro module next nil
    not of or out private property protected public require rescue respond_to?
    return select self setter spawn struct super then true false type union
    unless until when while with yield
  ].to_set

  # 轻量 Crystal 高亮：注释、字符串、关键字、类型/常量、数字、符号、注解、
  # 运算符。不是完整 parser；只要求不破坏代码文本并给出可读的着色。
  private def self.highlight_crystal(source : String) : String
    out = String::Builder.new
    i = 0
    while i < source.size
      ch = source[i]
      if ch == '#'
        j = source.index('\n', i) || source.size
        out << span("com", source[i, j - i])
        i = j
      elsif ch == '"'
        j = scan_quoted(source, i, '"')
        out << span("str", source[i, j - i])
        i = j
      elsif ch == '\''
        j = scan_quoted(source, i, '\'')
        out << span("str", source[i, j - i])
        i = j
      elsif ch == '@' && i + 1 < source.size && source[i + 1] == '['
        j = scan_annotation(source, i)
        out << span("anno", source[i, j - i])
        i = j
      elsif ch == ':' && i + 1 < source.size && source[i + 1] == ':'
        out << "::"
        i += 2
      elsif ch == ':' && i + 1 < source.size && identifier_start?(source[i + 1])
        j = scan_identifier(source, i + 1)
        out << span("sym", source[i, j - i])
        i = j
      elsif identifier_start?(ch)
        j = scan_identifier(source, i)
        word = source[i, j - i]
        if CRYSTAL_KEYWORDS.includes?(word)
          out << span("kw", word)
        elsif word[0].uppercase?
          out << span("type", word)
        else
          out << HTML.escape(word)
        end
        i = j
      elsif ch.ascii_number?
        j = scan_number(source, i)
        out << span("num", source[i, j - i])
        i = j
      elsif operator_char?(ch)
        j = i + 1
        while j < source.size && operator_char?(source[j])
          j += 1
        end
        out << span("op", source[i, j - i])
        i = j
      else
        out << HTML.escape(ch.to_s)
        i += 1
      end
    end
    out.to_s
  end

  private def self.span(kind : String, text : String) : String
    %(<span class="tok-#{kind}">#{HTML.escape(text)}</span>)
  end

  private def self.identifier_start?(ch : Char) : Bool
    ch.ascii_letter? || ch == '_'
  end

  private def self.identifier_char?(ch : Char) : Bool
    ch.ascii_letter? || ch.ascii_number? || ch == '_' || ch == '?' || ch == '!'
  end

  private def self.scan_identifier(source : String, start : Int32) : Int32
    i = start + 1
    while i < source.size && identifier_char?(source[i])
      i += 1
    end
    i
  end

  private def self.scan_number(source : String, start : Int32) : Int32
    i = start + 1
    while i < source.size
      ch = source[i]
      break unless ch.ascii_number? || ch == '_' || ch == '.' || ch.ascii_letter?
      i += 1
    end
    i
  end

  private def self.scan_quoted(source : String, start : Int32, quote : Char) : Int32
    i = start + 1
    while i < source.size
      ch = source[i]
      if ch == '\\'
        i += 2
        next
      end
      if ch == quote
        return i + 1
      end
      i += 1
    end
    source.size
  end

  private def self.scan_annotation(source : String, start : Int32) : Int32
    depth = 0
    i = start
    while i < source.size
      ch = source[i]
      depth += 1 if ch == '['
      if ch == ']'
        depth -= 1
        return i + 1 if depth == 0
      end
      i += 1
    end
    source.size
  end

  private def self.operator_char?(ch : Char) : Bool
    "=+-*/%<>!&|^~".includes?(ch)
  end

  private def self.render_table(lines : Array(String)) : String
    rows = lines.map { |line| split_row(line) }
    return "" if rows.empty?
    header = rows[0]
    body_start = rows.size > 1 && rows[1].all? { |cell| cell.matches?(/^:?-{2,}:?$/) } ? 2 : 1
    out = String::Builder.new
    out << "<table>\n<thead><tr>"
    header.each { |cell| out << "<th>" << inline(cell) << "</th>" }
    out << "</tr></thead>\n<tbody>\n"
    rows[body_start, rows.size - body_start].each do |row|
      out << "<tr>"
      row.each { |cell| out << "<td>" << inline(cell) << "</td>" }
      out << "</tr>\n"
    end
    out << "</tbody></table>\n"
    out.to_s
  end

  private def self.split_row(line : String) : Array(String)
    text = line.strip
    text = text[1, text.size - 1] if text.starts_with?("|")
    text = text[0, text.size - 1] if text.ends_with?("|")
    text.split('|').map(&.strip)
  end

  private def self.inline(text : String) : String
    escaped = HTML.escape(text)
    escaped = escaped.gsub(/`([^`]+)`/) { "<code>#{$1}</code>" }
    escaped = escaped.gsub(/\*\*([^*]+)\*\*/) { "<strong>#{$1}</strong>" }
    escaped = escaped.gsub(/!\[([^\]]*)\]\(([^)]+)\)/) do
      alt = $1
      src = $2
      src = src.sub("../../site/", "../")
      %(<img src="#{src}" alt="#{alt}">)
    end
    escaped.gsub(/\[([^\]]+)\]\(([^)]+)\)/) do
      label = $1
      href = $2
      unless href.starts_with?("http://") || href.starts_with?("https://") || href.starts_with?("#")
        href = href.sub(/\.md(\#.*)?$/, ".html")
      end
      %(<a href="#{href}">#{label}</a>)
    end
  end

  private def self.slugify(text : String) : String
    text.downcase.gsub(/[^a-z0-9\p{L}\p{N}]+/, "-").strip('-')
  end
end

KitSite.build
