# verify-M4-WP3-WP4 (task-126, dalisi-qing-2)
- HEAD=1161e53; 只读核验，未改 src/spec/examples/tools/docs/usage.md，未 commit。
- 裁定：**PASS-WITH-DEFECTS**（P1 无，P2 无，P3 见下；判据真实可失败）。
- spec 221/0 由 lead 已跑，本次未重复。

## 判据真实性（examples/app_demo.cr）
- 逐字节含 alpha：`m4d_pixel_diff` :232-244 比较 RGBA 四字节；size 不等返 a.size//4。
- 状态真变：:633-648 A初始→wheel(-1)→do_scroll :564-572(仅 scroll_y 变才脏 :568-571)
  →B脏帧/C同态全帧；`diff_pixels=BvsC :647`，`diff_a_vs_c=AvsC :648`（scroll 真变）。
- 主题对拍：:652-657 经 'T'→:531→toggle_theme :557-562 得 pixels_dark_t；:659-664
  同会话直接设 theme 得 pixels_dark_direct，`diff_theme=:665` 为两路径同态对拍
  （非“切换后 vs --theme=dark 跨启动重跑”）；roundtrip :667-675 再经 'T' 切回与
  初始 pixels_a 比（`diff_theme_roundtrip=:675`）。
- 零分配 :729-790：warmup60 :730；prime 6 帧仅预热丢弃 :733-749；3 窗 GC.collect+
  disable+测 N+ensure GC.enable :757-773，max :774-776；判据 A<1000 B<=256 :784 非
  严格 0；attempt>=2 break :785，打印 ALLOC_ATTEMPT1 :782（含 pass/fail_reason）。
- 非硬编码：`verify=(pass?"pass":"fail")` 计算值 :713；pass 条件 :690-691；无常量 diff。

## 负例反证（bin/_v_app_neg.cr，已删）
- 去除 wheel 事件后：`quads_dirty=0 culled=170 diff_pixels=0 diff_A_vs_C=0`
  `alloc_windows=[0,0,3792] attempt1 fail→[0,0,0] attempt2 scroll=0 verify=fail EXIT=1`。

## app_demo 实跑（usage.md 命令逐条核对）
- build -o bin/app_demo.exe EXIT=0(3749840B)；裸 PATH EXIT=-1073741515（符 usage.md:82）。
- verify 默认：diff=0 diff_A_vs_C=3113 theme=0 rt=0 alloc=[0,0,0] a1 pass EXIT=0。
- --theme=dark：pass，diff_A_vs_C=3102。--dpi=1.5：a1 [0,3792,0] fail→a2 pass。
- crystal run 形式：a1 [0,0,3792] fail→a2 pass，diff_A_vs_C=3113 verify=pass。
- usage.md 与代码/参数/流程/DPI/判据一致；KeyCode 无 KeyT（event.cr:20-30）符 :87-91。

## gate.ps1（tools/gate.ps1，14 项非恒 PASS）
- 逻辑：spec/build/examples 校验 token+exit :43-119；zero_alloc criterion_ok 计数
  :122-131；bench_scroll 仅记录 :134-145；atlas/package_bare_path/hygiene
  (unexpected→FAIL :186-224)/fail_probe 强制 fail :227-234；白名单含 M3-gate-r4.md :194。
- 重跑(powershell)：13 PASS + `file_hygiene FAIL`（unexpected: M M3-C8-gl-scroll.md,
  M M3-WP1-backend-dirty.md, M M3-iteration-log.md, ?? M4-iteration-log.md；allowed 含
  M4-WP4-gate.md/usage.md/app_demo.cr/gate.ps1），GATE_RESULT=FAIL EXIT=1。
  （当前未提交改动致 hygiene 异常，判据行为合理。）
- `-FailProbe C:\nonexistent\x`：fail_probe FAIL exit=1，GATE_RESULT=FAIL EXIT=1。

## 缺陷
- P3 `examples/app_demo.cr:659-675`：diff_theme 为同会话“事件切换 vs 直接设态”
  对拍，非跨启动对拍；roundtrip :667-675 已覆盖切回一致性。
- P3 `docs/evidence/M4-WP4-gate.md`：记录 20:22 hygiene 列表反映当时工作区；本次
  重跑因新增未提交改动而 FAIL，属环境差异非门禁缺陷。

## 清理
- 已删 bin/app_demo.exe、bin/_v_app_neg.cr；未动他人文件，未跑 clean/checkout/reset。