# M2-WP2b 图集与光栅化：实现与证据（当前 HEAD）

- 任务：task-79（C2），门禁 No-Go `docs/evidence/M2-gate.md` P2-1
- 基线：`2a2b620`（HEAD at report time；非历史 `76ef5d6`）
- 证据来源：实跑 `crystal spec spec/glyph_atlas_spec.cr spec/rasterizer_spec.cr`
- 时间：2026-11-13 Asia/Shanghai
- 本轮只读：未改 src/spec/examples，未 commit

## 1. 实现描述（`src/tessell/text/glyph_atlas.cr`）

- `GlyphKey(font_id:Int32, glyph_id:UInt32, size_px:Int32, subpixel:UInt8, flags:UInt8)` + FNV-1a-64 哈希：`glyph_atlas.cr:8-67`
- `GlyphSlot(page:Int32, x:Int32, y:Int32, w:Int32, h:Int32, bearing_x:Int32, bearing_y:Int32, advance:Float32)`：`glyph_atlas.cr:69-82`
- `GlyphAtlas.new(@page_size:Int32=1024, @capacity:Int32=4096)`：`glyph_atlas.cr:131`
- `Page{data:Bytes=size*size, shelves, used_pixels, live_count}`：`glyph_atlas.cr:97-117`
- `begin_frame/end_frame/in_frame?`：`glyph_atlas.cr:158-168`
- `lookup(key)` 命中刷新 LRU tick：`glyph_atlas.cr:174-181`
- `insert(key, w, h, ...)`：拒绝 `w<=0||h<=0`（`glyph_atlas.cr:186-188`）；重复 key 返回原 slot（`glyph_atlas.cr:192-197`）
- `place(...)`：超大字形预检查在 `acquire_page` 之前（`glyph_atlas.cr:299-304`，P3-1 修复）
- `evict_lru`：帧内淘汰抛 `FrameEvictionError`（`glyph_atlas.cr:226-227`，帧内不淘汰契约定）
- `invalidate_font(font_id)`：`glyph_atlas.cr:215-224`
- `page_data(page):Bytes`：`glyph_atlas.cr:207-209`
- `slot_rect(slot):NamedTuple(x,y,w,h)`：`glyph_atlas.cr:211-213`
- `clear`：`glyph_atlas.cr:239-251`
- `waste_ratio`：`glyph_atlas.cr:150-156`
- R8 单通道；UV 稳定（扩容 2→6 页逐字节稳定，verify-M2-WP2b.md §3）；帧内不淘汰为已验证契约

## 2. 实现描述（`src/tessell/text/rasterizer.cr`）

- `GlyphPlacement(key, glyph_id:UInt32, advance_px:Float32, offset_x:Int32, offset_y:Int32, w:Int32, h:Int32, u0,v0,u1,v1:Float32, page:Int32=-1)`：`rasterizer.cr:14-34`
- `coverage(p):Int32` 数图集槽 >0 像素：`rasterizer.cr:61-78`
- `rasterize_into(text, size_px, sink)`：HB shape + FT `LOAD_RENDER` + `sink.clear`，零 Array 分配：`rasterizer.cr:88-126`
- `gid==0` → 零位图 placement 保留 HB advance：`rasterizer.cr:139-142`
- 空位图 → `w=h=0` placeholder：`rasterizer.cr:163-166`
- `copy_bitmap_to_atlas` 处理 FT pitch 正/负：`rasterizer.cr:173-201`
- `placement_from_slot` uv=slot/page_size：`rasterizer.cr:203-215`
- `FtMeasurer` 暴露 `ft_face_handle/hb_font_handle/hb_buffer_handle/upem_value`：`rasterizer.cr:218-236`

## 3. 规格实跑（当前 HEAD `2a2b620`）

命令（PowerShell, `C:\msys64\ucrt64\bin` 在 PATH）：

```
crystal spec spec/glyph_atlas_spec.cr
# 13 examples, 0 failures, 0 errors, 0 pending
# EXITCODE=0
crystal spec spec/rasterizer_spec.cr
# 11 examples, 0 failures, 0 errors, 0 pending
# EXITCODE=0
crystal spec spec/glyph_atlas_spec.cr spec/rasterizer_spec.cr
# 24 examples, 0 failures, 0 errors, 0 pending
# EXITCODE=0
```

- `glyph_atlas_spec.cr`：13 examples，0 failures，EXIT=0（含 zero-alloc probe `delta_prime=0 delta_calib=0 delta_work=0 N=1000 windows=[0,0,0]`）
- `rasterizer_spec.cr`：11 examples，0 failures，EXIT=0
- 合计：24 examples，0 failures，0 errors，0 pending，EXIT=0

## 4. 行为契约（verify-M2-WP2b.md，历史基线 `76ef5d6`，需在 `2a2b620` 重验的条款）

| 契约 | 结论 | 证据 | 备注 |
|---|---|---|---|
| 帧内淘汰抛 `FrameEvictionError` | 已验证 | `glyph_atlas.cr:226-227` + verify-M2-WP2b.md §2 | 合同不变 |
| `invalidate_font` 计数正确 | 已验证 | `glyph_atlas.cr:215-224` + verify-M2-WP2b.md §2 | 合同不变 |
| LRU tick 刷新 | 已验证 | `glyph_atlas.cr:174-181` + verify-M2-WP2b.md §2 | 合同不变 |
| 200 随机装箱无重叠/越界 | 已验证 | verify-M2-WP2b.md §2 | 代码路径未变 |
| UV 扩容 2→6 页逐字节稳定 | 已验证 | verify-M2-WP2b.md §3 | 代码路径未变 |
| 页复用 page_count 不增 | 已验证 | verify-M2-WP2b.md §3 | 代码路径未变 |
| `lookup 3×1000 delta=0` | 已验证 | verify-M2-WP2b.md §3 | 代码路径未变 |
| `crystal spec` 127 examples 0 failures | 历史 | verify-M2-WP2b.md §3 | 当前 182 examples（含新增 spec） |
| P3-1 超大失败遗留空页 | 已修复 | `glyph_atlas.cr:299-304` 预检查 | 当前 HEAD 已含修复 |
| P3-2 0 尺寸可接受 | 已接受 | `glyph_atlas.cr:186-188` | 设计决策，非缺陷 |
| 重复 key 忽略新 size | 已知行为 | `glyph_atlas.cr:192-197` | 非缺陷，文档化 |

## 5. 未验证清单

- 以上契约在当前 HEAD `2a2b620` 的**重新实跑**仅覆盖 spec 层（24 examples, EXIT=0）；verify-M2-WP2b.md 的 99 行证据采集于 `76ef5d6`，代码路径未变但未在 `2a2b620` 重新采集底层探针输出。
- GL 上屏像素与帧时：见 `verify-M2-WP2d.md`（PASS-WITH-DEFECTS）与 `m2_text_window.cr` 实跑。
- `"لا"` 在 msyh 下 drawable=0：字体覆盖缺失，非光栅化 bug（verify-M2-WP2d.md §3 + 增量补记）。
- GL 纹理对象删除泄漏：未测。

## 6. 引用

- `src/tessell/text/glyph_atlas.cr:8-251`
- `src/tessell/text/rasterizer.cr:14-236`
- `docs/evidence/verify-M2-WP2b.md`（历史基线 `76ef5d6`，99 行）
- `docs/evidence/verify-M2-WP2d.md`（PASS-WITH-DEFECTS，162 行）
- `docs/evidence/M2-gate.md`（No-Go，396 行）
- `docs/evidence/M2-WP2c-zero-alloc-criterion.md`（零分配判据，40 行）

(End of file)