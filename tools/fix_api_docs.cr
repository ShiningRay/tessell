# 修正 crystal docs 输出版里的仓库相对链接。
#
# `crystal docs` 会把 README 正文嵌进 `site/api/index.html`，其中的
# `docs/*.md`、`site/previews/*`、`LICENSE` 相对链接在 GitHub 上可用，
# 在 Pages 上会 404。这里按「本地 Kit 页 → 仓库 GitHub 原文」降级改写。
#
# 用法：crystal run tools/fix_api_docs.cr

module ApiDocsFix
  REPO = "https://github.com/ShiningRay/tessell/blob/main"
  API_DIR = "site/api"
  KIT_DIR = "site/kit"

  # docs 路径与 Kit 站点输出名不一致的少数条目
  ALIASES = {
    "docs/cross-platform-plan.md" => "cross-platform.html",
    "docs/kit/K6-review.md"       => "k6-review.html",
  }

  # docs/kit/*.md 输出为 site/kit/*.html；其余 docs 页没有静态版，回落到 GitHub。
  private def self.kit_target(path : String) : String?
    return ALIASES[path]? if ALIASES.has_key?(path)
    return nil unless path.starts_with?("docs/kit/") && path.ends_with?(".md")
    rel = path.lchop("docs/kit/").rchop(".md")
    return "#{rel}.html" if File.exists?(File.join(KIT_DIR, "#{rel}.html"))
    # 大小写不敏感回退（GitHub Pages 在 Linux 上区分大小写）
    dir = File.join(KIT_DIR, File.dirname(rel))
    return nil unless Dir.exists?(dir)
    wanted = "#{File.basename(rel)}.html".downcase
    found = Dir.entries(dir).find { |entry| entry.downcase == wanted }
    return nil unless found
    prefix = File.dirname(rel)
    prefix == "." ? found : "#{prefix}/#{found}"
  end

  private def self.rewrite(html : String) : String
    html = html.gsub(/(href|src)="(docs\/[^"#]+\.md)(#[^"]*)?"/) do
      attr, path, anchor = $1, $2, $~[3]?
      if target = kit_target(path)
        "#{attr}=\"../kit/#{target}#{anchor}\""
      else
        "#{attr}=\"#{REPO}/#{path}#{anchor}\""
      end
    end
    html = html.gsub(/(href|src)="(site\/previews\/[^"]+)"/) do
      "#{$1}=\"../previews/#{$2.lchop("site/previews/")}\""
    end
    html.gsub(/(href)="LICENSE"/) { "#{$1}=\"#{REPO}/LICENSE\"" }
  end

  def self.run : Nil
    files = Dir.glob("#{API_DIR}/**/*.html")
    changed = 0
    files.each do |file|
      original = File.read(file)
      updated = rewrite(original)
      next if updated == original
      File.write(file, updated)
      changed += 1
    end
    puts "fix_api_docs: #{changed}/#{files.size} files rewritten"
  end
end

ApiDocsFix.run
