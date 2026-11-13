# M3-WP4 路径 stencil/cover 独立核验

- 日期：2026-11-14；HEAD `281e18a`；工作区 5 M + 5 ??（M3-WP4 交付）。
- 只读重跑；临时改动均已恢复（§3/§4 有 hash）；未 commit；临时探针已删。
- **裁定：PASS-WITH-DEFECTS**（P0/P1/P2 无；P3 三项）。stencil 确实在干活，CPU 参考独立。

## 1. 必跑矩阵

| 命令 | EXIT | 关键 token |
|---|---|---|
| `crystal spec` | 0 | `263 examples, 0 failures, 0 errors, 0 pending` |
| `crystal build src/tessell.cr` | 0 | 产物已删（`bin/_verify_build.exe`），未留档 |
| `m3_path_window --frames=20 --verify` ×2 | 0,0 | `7794/7794 diff=0 stencil_bits=8 verify=pass`；alloc `[64,64,64]`/`[64,64,80]` |
| `m3_path_window --frames=20 --verify --no-stencil` ×2 | 1,1 | `16244/7794 diff=8450 verify=fail` |

- 正例两次均 `mode=stencil_cover`、`star_offset=0.13/0.29`、`star_vertices=5`。
- 负例两次均 `mode=fan_no_stencil`，EXIT 1，证明 fan 实心填中心。

## 2. stencil 反证（核心）

- 临时把 `src/tessell/render/gl/gl_backend.cr:623` 的 `GL_INVERT` 改为 `GL_KEEP`，重跑 `--verify`：
  `mode=stencil_cover stencil_bits=8 fill_pixels_gl=0 fill_pixels_cpu=7794 diff_pixels=7794 verify=fail`，EXIT 1。
- 说明 cover 只在 stencil 非零处落色；若 stencil 未写入，GL 填充为 0，不是“忽略 stencil 也能过”。
- 恢复：从 `bin/` 备份复制回；`gl_backend.cr` SHA256=`C348329B...ACB6732`，与改前一致；
  `git diff --stat -- src/tessell/render/gl/gl_backend.cr` 仍为 `117 (+111/-6)`；备份已删。

## 3. CPU 参考独立性

- `examples/m3_path_window.cr:412-437`：先 `Polygon.new(star)`，再 `contains?` + 像素中心采样生成 `mask`；
  `pw_compare(gl_buf, mask, ...)` 只把 GL 回读与 CPU mask 比较，CPU 计数不读 GL。
- 判据 `:535-537` 精确为 `stencil_bits>=8 && diff_pixels==0 && fill_pixels_gl==fill_pixels_cpu && fill_pixels_gl>0`；
  无 `diff<=N` 容差；`stencil_bits` 来自 `gl_backend.cr:159-160` 的 `glGetIntegerv`，未写死。
- 改半径 100→80（`:368`）重跑：`4930/4931 diff_pixels=1 verify=fail`，EXIT 1；`star_vertices=5`。
  证明 CPU/GL 数字随几何变化，不是常量；恢复后 example SHA256=`054EF0D1...CD0B59`，与改前一致。

## 4. Polygon 语义（一次性 probe，已删）

- `POLY_ZERO_COPY=true`（`polygon.cr:15` 持有调用方数组引用）。
- `POLY_CENTER_CONTAINS=false`：五角星中心按 even-odd 为空（`:21-46`）。
- `POLY_MASK_W=190 H=180 COUNT=7771 NOT_CONST=true`；sink 不足 `POLY_SMALL_SINK_RAISED=true`（`:51-79`）。
- `POLY_FAN_TRIS=2`，`VALUES=0,0,10,0,10,10,0,0,10,10,0,10`，`POLY_FAN_ORDER_OK=true`（`:84-111`，n-2 个三角）。

## 5. 回归

- dirty：EXIT 0，`diff_pixels=0 diff_A_vs_C=889 4/57/53`。
- text：EXIT 0，`2801`、`ratio=1.0617892342683852`、`pixel_match=true`。
- emoji：EXIT 0，`1171`、`ratio=0.9629934210526315`。
- scroll dy20：EXIT 0，`diff_pixels=0 diff_A_vs_C=3101 alloc_windows=[0,0,0]`。

## 6. gate 审计

- 运行 `tools/gate.ps1`：15 项中 **14 PASS**，仅 `file_hygiene` FAIL；`GATE_RESULT=FAIL`。
- FAIL 原因只有 5 个已修改 tracked 文件：`spec/backend_protocol_spec.cr`、`src/tessell.cr`、
  `src/tessell/render/backend.cr`、`src/tessell/render/gl/gl_backend.cr`、`tools/gate.ps1`；符合未提交预期。
- 新增仅 `ex_m3_path_verify`（14→15），其 token 以 `verify=pass` 开头；
  既有 14 项判据未见改弱（diff 仅插入该检查与 hygiene 白名单）。
- `file_hygiene` 新增 5 个合法未跟踪：`examples/m3_path_window.cr`、`spec/path_gl_spec.cr`、
  `docs/evidence/M3-WP4-stencil-cover.md`、`spec/polygon_spec.cr`、`src/tessell/render/polygon.cr`；
  未加入其它无关文件。

## 7. 证据对账与缺陷

- `docs/evidence/M3-WP4-stencil-cover.md` 实测 **71 行**；`[未验证]` 5 条（GPU/驱动、MSAA、
  cover 三角化、stencil/dirty 复用、nonzero），每条均写验证方式；无“通用/跨平台/严格零分配”措辞。
- 正例 7794/7794/diff0、负例 16244/8450、stencil_bits=8、0.13/0.29 均与实测一致；
  零分配 probe 本机 `delta_work=64 windows=[64,64,64]`，文档 `:38` 为 `80/[80,64,80]`（区间内，非逐字节复现）。
- **P3-1** `examples/m3_path_window.cr:6` 注释仍写中心 `(400.37,300.61)`，实际 `:366-368` 为
  `400.13/300.29`（文档 `:31` 已写 0.13/0.29）。
- **P3-2** 半径 80 复测 `diff_pixels=1`；`diff==0` 只对当前 5 角/偏移几何成立，属边界 fill convention；
  文档解释了偏移选择，但未列半径/几何敏感性。
- **P3-3** 文档零分配 probe 的 `delta_work/windows` 与本次运行相差 16B（64 vs 80）；A/B 判据均过，非阻断。

## 8. 结论

- stencil/cover 反证成立：去掉 `GL_INVERT` 后 `fill_pixels_gl=0`、`diff=7794`、EXIT 1。
- CPU 期望值由 `Polygon.contains?` + 像素中心独立生成，且随几何变化；判据未放宽。
- **PASS-WITH-DEFECTS**：无 P0/P1/P2，P3 三项记录；M3-WP4 可按“本机 WGL、单几何样例”关闭，
  不得外推为跨平台/跨驱动/任意几何的逐像素保证。
