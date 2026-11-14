# Tessell Kit 静态文档站生成器（K5）
#
# 只转换 docs/kit 下的 Markdown 子集，不引入 Web 运行时或静态站依赖。
# 用法：crystal run tools/build_kit_site.cr
# 输出：site/kit/*.html 与 site/index.html

require "html"
require "file_utils"

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
    Page.new("执行记录", "docs/kit/execution.md", "execution.html"),
    Page.new("K6 复核", "docs/kit/K6-review.md", "k6-review.html"),
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
    blockquote { margin:16px 0; padding:8px 16px; border-left:3px solid var(--accent); color:var(--muted); background:var(--card); }
    table { border-collapse:collapse; width:100%; margin:16px 0; background:var(--card); }
    th, td { border:1px solid var(--border); padding:8px 10px; text-align:left; vertical-align:top; }
    th { background:rgba(127,127,127,.08); }
    .meta { color:var(--muted); font-size:13px; margin-bottom:24px; }
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
<p><a href="kit/index.html">进入组件文档 →</a></p>
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
          out << "<pre><code>" << HTML.escape(code.to_s) << "</code></pre>\n"
          code = String::Builder.new
          code_open = false
        else
          flush_paragraph.call
          close_list.call
          flush_table.call
          code_open = true
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
      out << "<pre><code>" << HTML.escape(code.to_s) << "</code></pre>\n"
    end
    out.to_s
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
    escaped.gsub(/\[([^\]]+)\]\(([^)]+)\)/) do
      label = $1
      href = $2
      href = href.sub(/\.md(\#.*)?$/, ".html")
      %(<a href="#{href}">#{label}</a>)
    end
  end

  private def self.slugify(text : String) : String
    text.downcase.gsub(/[^a-z0-9\p{L}\p{N}]+/, "-").strip('-')
  end
end

KitSite.build
