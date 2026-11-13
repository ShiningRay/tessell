# M3-WP4 stencil/cover 路径验证（task-141 stage B）

## 1. 设计与流程
- 路径：CPU `Tessell::Render::Polygon`（even-odd，`polygon.cr`）+ GL stencil/cover
  （`gl_backend.cr` `GLBackend#draw_polygon`）。判据目标：`diff_pixels == 0`。
- 流程：`glEnable(GL_STENCIL_TEST)` → `glClearStencil(0)` +
  `glClear(GL_STENCIL_BUFFER_BIT)` → `glStencilMask(0xFF)` →
  `glStencilFunc(GL_ALWAYS,0,0xFF)` + `glStencilOp(GL_KEEP,GL_KEEP,GL_INVERT)` →
  `glColorMask(0,0,0,0)` → `GL_TRIANGLE_FAN` 全顶点写奇偶 → `glColorMask(1,1,1,1)` →
  `glStencilFunc(GL_NOTEQUAL,0,0xFF)` + `glStencilOp(GL_KEEP,GL_KEEP,GL_KEEP)` →
  bounds 矩形 `GL_QUADS` 以预乘色覆盖 stencil!=0 → `glDisable(GL_STENCIL_TEST)` +
  恢复 mask/texture/scissor。`@stencil_fills += 1`，return true。
- 守卫（诚实）：`points.size<3` / `even_odd=false`（nonzero 未实现）/
  `@stencil_bits<=0` → return false，不静默错误填充。init 读 `GL_STENCIL_BITS`。
- 常量/签名来源：OpenGL 1.1（lead m01411 给定）：`GL_STENCIL_TEST=0x0B90`
  `GL_STENCIL_BUFFER_BIT=0x00000400` `GL_ALWAYS=0x0207` `GL_NOTEQUAL=0x0205`
  `GL_KEEP=0x1E00` `GL_INVERT=0x150A` `GL_STENCIL_BITS=0x0D57`；`glStencilFunc/Op/Mask`
  `glClearStencil` `glColorMask` `glGetIntegerv`。

## 2. 实现与规格（stage A+B）
- `src/tessell/render/polygon.cr:1-151`，`backend.cr:13-50`（FrameStats.stencil_fills,
  draw_polygon 默认 false），`gl_backend.cr`（stencil 常量+绑定+@stencil_bits/init
  查询+draw_polygon+begin_frame/dirty 清 stencil），`src/tessell.cr:15` require。
- `spec/polygon_spec.cr` 9 its（含 3 零分配探针），`spec/backend_protocol_spec.cr`
  RecordingBackend.draw_polygon + 2 its，`spec/path_gl_spec.cr` 6 its（无窗口）。
- 验证：`crystal spec` `263 examples, 0 failures, 0 errors, 0 pending`；
  `crystal build src/tessell.cr` EXIT 0；`crystal build examples/m3_path_window.cr` EXIT 0。

## 3. 示例运行原始 token 行（examples/m3_path_window.cr，800×600）
星形：5 外顶点 pentagram 顺序（自交 fan），半径 100，中心 (400,300) + 偏移。
偏移选择：`star_offset_x=0.13 star_offset_y=0.29`。理由：lead 提示首选 `+0.37,+0.61`
可避开边过像素中心；实测该偏移得 `diff_pixels=1`（GL top-left 填充与像素中心点采样
在单边界像素处不一致），改为 `0.13,0.29` 后 `diff_pixels=0`；判据仍为
`diff_pixels == 0`（未放宽）。PFD `cStencilBits=8`，运行读 `stencil_bits=8`。

正例 `--frames=20 --verify`（EXIT 0）：
```text
zero-alloc probe(path_draw_polygon): delta_prime=48 delta_calib=0 delta_work=80 N=1000 windows=[80,64,80] retried=false attempt=1
mode=stencil_cover stencil_bits=8 fill_pixels_gl=7794 fill_pixels_cpu=7794 star_pixels=7794 diff_pixels=0 star_offset_x=0.13 star_offset_y=0.29 star_vertices=5 frames=20 alloc_windows=[80,64,80] retried=false attempt=1 negative_holds=true verify=pass
```
负例 `--frames=20 --verify --no-stencil`（EXIT 1，fan 实心填中心，反证非偶然空心）：
```text
zero-alloc probe(path_draw_polygon): delta_prime=32 delta_calib=0 delta_work=64 N=1000 windows=[64,64,64] retried=false attempt=1
mode=fan_no_stencil stencil_bits=8 fill_pixels_gl=16244 fill_pixels_cpu=7794 star_pixels=7794 diff_pixels=8450 star_offset_x=0.13 star_offset_y=0.29 star_vertices=5 frames=20 alloc_windows=[64,64,64] retried=false attempt=1 negative_holds=true verify=fail
```
稳态 `--frames=20`（EXIT 0）：
```text
zero-alloc probe(path_draw_polygon): delta_prime=48 delta_calib=0 delta_work=64 N=1000 windows=[64,64,64] retried=false attempt=1
mode=stencil_cover stencil_bits=8 fill_pixels_gl=7794 fill_pixels_cpu=7794 star_pixels=7794 diff_pixels=0 star_offset_x=0.13 star_offset_y=0.29 star_vertices=5 frames=20 alloc_windows=[64,64,64] retried=false attempt=1 negative_holds=true verify=pass
```
零分配：3 窗 max，判据 A `delta_work < N(1000)`、B `<=256`，ensure GC.enable，≤1 重试；
上述窗口 64–80B，满足 A/B。verify：`stencil_bits>=8 && diff_pixels==0 &&
fill_pixels_gl==fill_pixels_cpu && fill_pixels_gl>0`。

## 4. 门禁
- `tools/gate.ps1` 新增 `ex_m3_path_verify`（`--verify --frames=20`，需
  `verify=pass,stencil_bits=,diff_pixels=0,fill_pixels_gl=,fill_pixels_cpu=`），
  位于 scroll dy600 后，14→15 项（仅新增）。为本任务未提交交付物可过 hygiene，
  whitelist 增加 `examples/m3_path_window.cr`、`spec/path_gl_spec.cr`、
  `docs/evidence/M3-WP4-stencil-cover.md`（披露）。

## 5. 未验证 [未验证]
- [未验证] 真机/多显卡/多驱动：仅本机 WGL+当前驱动实测 stencil_bits=8；其它 GPU/驱动
  可能无 stencil 或行为差异，`glGetIntegerv(GL_STENCIL_BITS)` 为运行时真值。
- [未验证] 抗锯齿（MSAA）：当前 PFD 未请求多采样；开启 MSAA 时覆盖/边缘采样与像素中心
  CPU 参考可能不再逐像素一致，需另定判据。
- [未验证] cover 三角化质量：cover 使用多边形 bounds 的单个 GL_QUADS；对极端凹/复杂
  bounds 或未来路径形状需验证覆盖充分性与裁剪交互。
- [未验证] stencil 复用与 dirty 交互：每次 draw_polygon 清 stencil buffer 位并禁用/恢复
  scissor；与 dirty-rect 部分提交、同帧多 polygon、多 pass 的组合未系统验证。
- [未验证] nonzero 规则：`even_odd=false` 当前诚实返回 false（未实现 GL_INCR/DECR）。
