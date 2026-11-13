# M2-WP2b 图集与光栅化：实现与证据（当前 HEAD）

- 任务：task-85（C2 关闭：契约证据当前 HEAD 可重跑）
- 基线：`4cc928a`（HEAD at verification time）；`76ef5d6` 仅作历史参照，不再作为关闭依据
- 证据来源（当前 HEAD 实跑）：
  - `crystal run tools/atlas_raster_verify.cr`（EXITCODE=0，8 项关键断言全齐，见 §3）
  - `crystal spec spec/glyph_atlas_spec.cr spec/rasterizer_spec.cr`（24 examples, 0 failures）
  - `crystal spec` 全量（186 examples, 0 failures，见 §3）
- 时间：2026-11-13 Asia/Shanghai
- 本轮改动范围：仅 `tools/atlas_raster_verify.cr`（新增）、`docs/evidence/M2-WP2b.md`（本文件重写）；未改 src/spec/其他 docs；禁 commit

## 1. 实现描述（`src/tessell/text/glyph_atlas.cr`，当前 HEAD）

- `GlyphKey(font_id:Int32, glyph_id:UInt32, size_px:Int32, subpixel:UInt8, flags:UInt8)` + FNV-1a-64 哈希/==/hash：`glyph_atlas.cr:8-67`
- `GlyphSlot(page:Int32, x:Int32, y:Int32, w:Int32, h:Int32, bearing_x:Int32, bearing_y:Int32, advance:Float32)`：`glyph_atlas.cr:69-82`
- `GlyphAtlas::FrameEvictionError < Exception`：`glyph_atlas.cr:85-86`
- `Page{data:Bytes, shelves, used_pixels, live_count}`：`glyph_atlas.cr:97-117`
- `GlyphAtlas.new(@page_size:Int32=1024, @capacity:Int32=4096)`：`glyph_atlas.cr:131`
- `waste_ratio`：`glyph_atlas.cr:150-156`
- 帧契约：`begin_frame/end_frame/in_frame?`：`glyph_atlas.cr:158-168`
- `lookup(key)` 命中刷新 LRU tick：`glyph_atlas.cr:174-181`
- `insert(key, w, h, ...)`：拒绝 `w<=0||h<=0`（`glyph_atlas.cr:186-188`）；重复 key 返回原 slot 并刷新 tick（`glyph_atlas.cr:192-197`）；容量不足时帧外驱逐/帧内抛错（`glyph_atlas.cr:253-259`）
- `page_data(page)` / `slot_rect(slot)`：`glyph_atlas.cr:207-213`
- `invalidate_font(font_id)` 定向移除并返回计数：`glyph_atlas.cr:215-224`
- `evict_lru(count)`：帧内淘汰抛 `FrameEvictionError`（`glyph_atlas.cr:226-227`），帧外淘汰最旧并回收整页空闲页（`glyph_atlas.cr:226-238,273-286`）
- `clear`：`glyph_atlas.cr:239-251`
- `place(...)`：超大字形预检查在 `acquire_page` 之前（`glyph_atlas.cr:288-313`，P3-1 约束保持）
- R8 单通道；shelf 装箱；UV 由 slot/page_size 稳定导出（现有 slot 坐标不随扩容移动）

## 2. 实现描述（`src/tessell/text/rasterizer.cr`，当前 HEAD）

- `GlyphPlacement(key, glyph_id, advance_px, offset_x, offset_y, w, h, u0,v0,u1,v1, page=-1)`：`rasterizer.cr:17-37`
- `ShapedRunKey(font_id,size_px,text_hash,key_hash)` FNV-1a 混合/==/hash：`rasterizer.cr:39-80`
- `Rasterizer::FrameEvictionError` / `ShapedRunEntry(placements,tick)`：`rasterizer.cr:83-92`
- `Rasterizer.new(measurer, atlas, font_id=0, run_cache_capacity=256)`：`rasterizer.cr:106-114`
- `coverage(p)` 统计 atlas 槽 >0 像素：`rasterizer.cr:141-158`
- `shape_run_into(text,size_px,sink):Int32`：命中 tick++ 后逐项拷贝 cached placements（跳过 HB/FT）；未命中走 `shape_and_rasterize_into` 后 `store_run` 快照（`rasterizer.cr:168-190`）
- `rasterize_into(text,size_px,sink)`：保留 per-glyph HB/FT + atlas hit/miss/rasters 语义路径（`rasterizer.cr:195-198`，经 `shape_and_rasterize_into`）
- `shape_and_rasterize_into`：HB reset/add_utf8/guess/shape + `rasterize_glyph` 循环（`rasterizer.cr:200-238`）
- shaped-run 帧守卫 LRU：`begin_frame/end_frame/in_run_frame?`、`store_run`/`ensure_run_capacity_for_insert`、`evict_run_lru` 帧内抛 `FrameEvictionError`（`rasterizer.cr:128-138,240-274`）
- `rasterize_glyph`：atlas 命中计 hits；`gid==0` 零位图 placement 保留 HB advance（`rasterizer.cr:298-301`）；空位图 `w=h=0` placeholder（`rasterizer.cr:322-325`）；miss 走 FT `LOAD_RENDER`+atlas insert+bitmap copy（`rasterizer.cr:287-330`）
- `copy_bitmap_to_atlas` 处理 FT pitch 正/负：`rasterizer.cr:332-360`
- `placement_from_slot`：`uv = slot/page_size`（`rasterizer.cr:362-374`）
- `FtMeasurer` 暴露 `ft_face_handle/hb_font_handle/hb_buffer_handle/upem_value`：`rasterizer.cr:379-395`

## 3. 当前 HEAD 实跑证据

### 3.1 可重跑契约探针 `tools/atlas_raster_verify.cr`

命令（PowerShell, `C:\msys64\ucrt64\bin` 在 PATH）：

```
cd C:\Users\ShiningRay\projects\ShiningRay\tessell
$env:PATH="C:\msys64\ucrt64\bin;$env:PATH"
crystal run tools/atlas_raster_verify.cr
```

完整输出（8 项关键断言齐全）：

```
frame_eviction_raised=true class=Tessell::Text::GlyphAtlas::FrameEvictionError
frame_eviction_after_end_evicted=1
invalidate_font_evicted=2 font1a_nil=true font1b_nil=true font2_present=true
lru_tick_k1_present=true lru_tick_k2_nil=true lru_tick_k3_present=true
RANDOM200 ok=true count=200 pages=1
UV_STABLE=true mismatch=0 pages_before=5 pages_after=10
page_reuse_page_count_before=2 page_count_after_free=2 page_count_after=2 reused=true
lookup_probe deltas=[0,0,0] delta_work=0 N=1000 pass=true
shaped_run_hit_equiv=true count_base=9 count_hit=9 bad=0 run_cache_size=1
ATLAS_RASTER_VERIFY_EXIT=0
```

- EXITCODE=0

### 3.2 规格实跑（当前 HEAD `4cc928a`）

```
crystal spec spec/glyph_atlas_spec.cr spec/rasterizer_spec.cr
# Finished in 34.46 milliseconds
# 24 examples, 0 failures, 0 errors, 0 pending
# EXITCODE=0

crystal spec
# Finished in 487.71 milliseconds
# 186 examples, 0 failures, 0 errors, 0 pending
# EXITCODE=0
```

## 4. 行为契约（当前 HEAD 证据；`76ef5d6` 仅历史参照）

| 契约 | 结论 | 当前 HEAD 证据（探针输出行 / 代码锚点） | 备注 |
|---|---|---|---|
| 帧内禁淘汰抛 `FrameEvictionError`；帧外可驱逐 | 已验证（当前 HEAD） | `frame_eviction_raised=true class=Tessell::Text::GlyphAtlas::FrameEvictionError`；`frame_eviction_after_end_evicted=1`（§3.1）；`glyph_atlas.cr:158-168,226-238,253-259` | atlas 帧契约 |
| `invalidate_font` 定向驱逐计数且不误伤他字体 | 已验证（当前 HEAD） | `invalidate_font_evicted=2 font1a_nil=true font1b_nil=true font2_present=true`（§3.1）；`glyph_atlas.cr:215-224` | 定向清理 |
| LRU tick：`lookup` 命中刷新，`evict_lru` 淘汰最旧 | 已验证（当前 HEAD） | `lru_tick_k1_present=true lru_tick_k2_nil=true lru_tick_k3_present=true`（§3.1）；`glyph_atlas.cr:174-181,226-238` | LRU 语义 |
| 随机装箱 200 个不同尺寸无重叠/越界 | 已验证（当前 HEAD） | `RANDOM200 ok=true count=200 pages=1`（§3.1） | shelf 装箱正确性 |
| UV 稳定：扩容前后同 key slot/uv 不变 | 已验证（当前 HEAD） | `UV_STABLE=true mismatch=0 pages_before=5 pages_after=10`（§3.1） | 扩容不移动既有 glyph |
| 整页空闲后复用，`page_count` 不增 | 已验证（当前 HEAD） | `page_reuse_page_count_before=2 page_count_after_free=2 page_count_after=2 reused=true`（§3.1）；`glyph_atlas.cr:273-286,315-324` | 页回收复用 |
| `lookup` 3×1000 全命中 delta=0（判据 A/B, 3 窗 max, GC.enable in ensure） | 已验证（当前 HEAD） | `lookup_probe deltas=[0,0,0] delta_work=0 N=1000 pass=true`（§3.1） | 热路径零分配探针 |
| `shape_run_into` 命中路径与 `rasterize_into` per-glyph 路径 placements 逐字段一致（缓存未改语义） | 已验证（当前 HEAD） | `shaped_run_hit_equiv=true count_base=9 count_hit=9 bad=0 run_cache_size=1`（§3.1）；`rasterizer.cr:168-198,200-238,287-330` | task-73 shaped-run 语义保持 |
| `glyph_atlas_spec + rasterizer_spec` 回归 | 已验证（当前 HEAD） | `24 examples, 0 failures, 0 errors, 0 pending` EXITCODE=0（§3.2） | 定向 spec |
| 全量 spec 回归 | 已验证（当前 HEAD） | `186 examples, 0 failures, 0 errors, 0 pending` EXITCODE=0（§3.2） | 全仓基线保持 |
| P3-1 超大 glyph 失败不遗留空页 | 已验证（当前 HEAD 代码） | `glyph_atlas.cr:299-304`（acquire_page 前预检查）；spec `oversized glyph raises without leaving a stray page...` 覆盖（§3.2） | 约束保持 |
| 0 尺寸 insert 拒绝且无副作用 | 已验证（当前 HEAD 代码） | `glyph_atlas.cr:186-188`；spec `zero-size insert raises ArgumentError...` 覆盖（§3.2） | 设计决策，非缺陷 |
| 重复 key 幂等（首 slot 胜出） | 已验证（当前 HEAD 代码） | `glyph_atlas.cr:192-197`；spec `duplicate-key insert is idempotent...` 覆盖（§3.2） | 已文档化行为 |

历史参照：`docs/evidence/verify-M2-WP2b.md`（`76ef5d6`，99 行）记录早期底层探针采样；自 task-73 起 `rasterizer.cr` 增加 shaped-run 缓存，行号与路径结构已变化，历史采集不再作为 C2 关闭依据，以上表格以当前 HEAD 可重跑证据为准。

## 5. 未验证清单

- GL 上屏像素与帧时：见 `docs/evidence/verify-M2-WP2d.md`（PASS-WITH-DEFECTS）与 `examples/m2_text_window.cr` 实跑；非本探针覆盖。
- `"لا"` 在 msyh 下 drawable=0：字体覆盖缺失，非光栅化/图集 bug（verify-M2-WP2d.md §3 及增量补记）。
- GL 纹理对象删除/生命周期泄漏：未测（超出 M2-WP2b atlas/rasterizer 契约范围）。
- `shape_run_into` 在更大字体集/多 size 混合长时运行下的内存占用上界：由 `run_cache_capacity`(默认 256)+LRU 限界，未做长稳压测。

## 6. 引用

- `tools/atlas_raster_verify.cr`（当前 HEAD 可重跑探针，task-85 新增）
- `src/tessell/text/glyph_atlas.cr:8-360`
- `src/tessell/text/rasterizer.cr:17-397`
- `docs/evidence/verify-M2-WP2b.md`（历史参照 `76ef5d6`，99 行）
- `docs/evidence/verify-M2-WP2d.md`（PASS-WITH-DEFECTS，162 行）
- `docs/evidence/M2-gate.md` / `docs/evidence/M2-gate-r2.md`（门禁）
- `docs/evidence/M2-WP2c-zero-alloc-criterion.md`（零分配判据，40 行）