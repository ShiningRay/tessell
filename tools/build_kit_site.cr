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
    Page.new("自定义大控件", "docs/kit/cookbook-custom-widget.md", "cookbook-custom-widget.html"),
    Page.new("扩展 Kit", "docs/kit/extending.md", "extending.html"),
    Page.new("分发约定", "docs/kit/distribution.md", "distribution.html"),
    Page.new("Row / Column", "docs/kit/components/row-column.md", "components/row-column.html"),
  ]

  # 导航分组：与 PAGES 的输出路径对应，渲染时据此高亮当前页。
  NAV_GROUPS = {
    "开始"   => ["index.html"],
    "组件"   => PAGES.select { |p| p.output.starts_with?("components/") }.map(&.output),
    "指南"   => ["design-tokens.html", "component-contract.html", "cookbook-custom-widget.html", "apps.html"],
    "仓库"   => ["plan.html", "cross-platform.html", "execution.html", "repository-strategy.html", "k6-review.html"],
  }

  # 站点根相对路径：Kit 页位于 site/kit/ 下，组件页再深一层。
  private def self.root_for(output : String) : String
    depth = output.split("/").reject(&.empty?).size - 1
    "../" * (depth + 1)
  end

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
    <<-HTML
<!doctype html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>#{HTML.escape(title)} — Tessell Kit</title>
<link rel="stylesheet" href="#{root_for(page.output)}assets/site.css">
</head>
<body>
<div class="layout">
#{sidebar(page.output, root_for(page.output))}
<main>
<div class="meta">来源：#{HTML.escape(page.source)} · <a href="#{root_for(page.output)}api/index.html">API 参考</a></div>
#{body}
</main>
</div>
#{layout_tail}
HTML
  end

  # 分组侧栏；当前页用 aria-current 高亮（样式见 site/assets/site.css）。
  private def self.sidebar(current : String, root : String, prefix : String = "") : String
    groups = NAV_GROUPS.map do |heading, outputs|
      links = outputs.map do |output|
        page = PAGES.find { |p| p.output == output }
        next if page.nil?
        href = "#{prefix}#{relative(current, output)}"
        marker = output == current ? %( aria-current="page") : ""
        %(<a class="nav-link" href="#{href}"#{marker}>#{HTML.escape(page.title)}</a>)
      end.compact.join("\n")
      %(<div class="nav-group">\n<div class="nav-group-title">#{HTML.escape(heading)}</div>\n#{links}\n</div>)
    end.join("\n")
    <<-HTML
<nav class="site-nav">
<details class="nav-details" open>
<summary>Tessell Kit</summary>
<div class="nav-body">
<a class="brand" href="#{root}index.html"><strong>Tessell Kit</strong><span>自绘组件库文档</span></a>
#{groups}
<div class="nav-foot">
<a class="nav-link" href="#{root}api/index.html">API 参考</a>
<a class="nav-link" href="https://github.com/ShiningRay/tessell" rel="noopener">GitHub 仓库</a>
</div>
</div>
</details>
</nav>
HTML
  end

  private def self.layout_tail : String
    <<-HTML
<script>
  // 窄屏默认折叠整站导航（桌面保持展开）；纯渐进增强，无脚本时导航仍可见。
  (function () {
    var d = document.querySelector(".nav-details");
    if (d && window.matchMedia("(max-width: 820px)").matches) d.open = false;
  })();
</script>
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
<title>Tessell Kit — 自绘组件库文档</title>
<meta name="description" content="Tessell 的 retained-mode 自绘组件库文档：组件 API、设计 token、组件契约与跨平台方案。">
<link rel="stylesheet" href="assets/site.css">
</head>
<body class="landing">
<div class="layout">
#{sidebar("", "", "kit/")}
<main>
<section class="hero">
<p class="hero-eyebrow">Crystal · retained-mode · 自绘</p>
<h1>Tessell Kit</h1>
<p class="hero-lead">Tessell 的组件库：Button、Checkbox、Text、Input、Select、Tooltip、Dialog、ScrollView、VirtualList，共用一套设计 token 与键盘/a11y 契约。</p>
<div class="hero-actions">
<a class="btn primary" href="kit/index.html">阅读组件文档</a>
<a class="btn" href="api/index.html">API 参考</a>
<a class="btn" href="https://github.com/ShiningRay/tessell" rel="noopener">GitHub</a>
</div>
</section>

<div class="card-grid">
<a class="card" href="kit/components/button.html">
<h3>组件</h3>
<p>9 个组件的状态、variant、键盘路径与主题 token，逐页写清限制。</p>
</a>
<a class="card" href="kit/design-tokens.html">
<h3>设计 token</h3>
<p>颜色、间距、圆角、尺寸档位来自 Theme::Metrics，组件不得另造一套。</p>
</a>
<a class="card" href="kit/component-contract.html">
<h3>组件契约</h3>
<p>身份与状态、尺寸与布局、失效最小化、输入与无障碍的公共约定。</p>
</a>
<a class="card" href="kit/cross-platform.html">
<h3>跨平台方案</h3>
<p>Windows / macOS / Linux 按 L0–L3 分级收口，未验证项显式标注。</p>
</a>
</div>

<div class="preview-frame">
<img src="previews/gallery-light.png" alt="Tessell Kit 组件矩阵预览（浅色主题）">
<p class="preview-caption">Kit gallery 无窗口渲染产物：由 PaintList 生成，证明绘制命令与主题组合，不等于真实窗口上屏证据。</p>
</div>

<p class="meta">本页由 <code>tools/build_kit_site.cr</code> 生成 · 站点样式见 <code>site/assets/site.css</code></p>
</main>
</div>
#{layout_tail}
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
    list_item : String? = nil
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
    flush_item = -> do
      if item = list_item
        out << "<li>" << inline(item) << "</li>\n"
        list_item = nil
      end
    end
    close_list = -> do
      if list_open
        flush_item.call
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
        flush_item.call
        unless list_open
          out << "<ul>\n"
          list_open = true
        end
        list_item = stripped[2..]
      elsif stripped.starts_with?("> ")
        flush_paragraph.call
        close_list.call
        out << "<blockquote>" << inline(stripped[2..]) << "</blockquote>\n"
      elsif item = list_item
        # 列表项软换行：续行并入上一条，避免拆成「ul + p + ul」
        list_item = "#{item} #{stripped}"
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
