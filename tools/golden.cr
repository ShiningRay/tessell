# golden-image 回归 CLI（issue #9）：
#   crystal run tools/golden.cr -- baseline.tsraw current.tsraw --diff out.png --max-diff 0
#   crystal run tools/golden.cr -- baseline.png current.png
# 退出码 0=pass（diff_pixels <= max-diff），1=fail，2=用法/格式错误。
# 同时支持 TSRAW→PNG 转换：
#   crystal run tools/golden.cr -- --convert shot.tsraw shot.png

require "./lib/png"

args = ARGV.dup
if args.empty?
  STDERR.puts "usage: golden.cr [--convert in.tsraw out.png] | baseline current [--diff out.png] [--max-diff N]"
  exit 2
end

if args[0] == "--convert"
  unless args.size >= 3
    STDERR.puts "usage: golden.cr --convert in.tsraw out.png"
    exit 2
  end
  w, h, rgba = TessellPNG.from_tsraw(args[1])
  TessellPNG.write(args[2], w, h, rgba)
  puts "GOLDEN_CONVERT in=#{args[1]} out=#{args[2]} size=#{w}x#{h}"
  exit 0
end

baseline = args[0]
current = args[1]? || (STDERR.puts "usage: golden.cr baseline current"; exit 2)
diff_path = nil
max_diff = 0
i = 2
while i < args.size
  case args[i]
  when "--diff"
    diff_path = args[i + 1]?
    i += 1
  when "--max-diff"
    max_diff = (args[i + 1]? || "0").to_i
    i += 1
  else
    STDERR.puts "unknown arg #{args[i]}"
    exit 2
  end
  i += 1
end

begin
  r = TessellGolden.compare(baseline, current, diff_path)
  ok = r.pass?(max_diff)
  puts "GOLDEN_COMPARE baseline=#{baseline} current=#{current} size=#{r.width}x#{r.height} " \
       "diff_pixels=#{r.diff_pixels} max_channel_diff=#{r.max_channel_diff} " \
       "max_diff=#{max_diff} diff_png=#{diff_path || "-"} verify=#{ok ? "pass" : "fail"}"
  exit ok ? 0 : 1
rescue e : ArgumentError | File::NotFoundError
  STDERR.puts "GOLDEN_COMPARE error: #{e.message}"
  exit 2
end
