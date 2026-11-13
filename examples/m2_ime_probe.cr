# M2-WP3 IME probe: programmatic preedit/result roundtrip + candidate probe (M-1/C2)
# Reuses m0_ime_probe/m0_window_probe window+message-pump structure.
# Pure FFI: kernel32/user32/imm32 (no gdi32/opengl32 required).
# Usage:
#   crystal run examples/m2_ime_probe.cr -- --frames=60
#   crystal run examples/m2_ime_probe.cr -- --frames=60 --json

@[Link("kernel32")]
lib K32
  fun GetModuleHandleW(lpModuleName : UInt16*) : Void*
  fun GetLastError : UInt32
end

@[Link("user32")]
lib U32
  struct WNDCLASSEXW
    cbSize : UInt32
    style : UInt32
    lpfnWndProc : (Void*, UInt32, LibC::UIntPtrT, LibC::IntPtrT -> LibC::IntPtrT)
    cbClsExtra : Int32
    cbWndExtra : Int32
    hInstance : Void*
    hIcon : Void*
    hCursor : Void*
    hbrBackground : Void*
    lpszMenuName : UInt16*
    lpszClassName : UInt16*
    hIconSm : Void*
  end

  struct POINT
    x : Int32
    y : Int32
  end

  struct MSG
    hwnd : Void*
    message : UInt32
    wParam : LibC::UIntPtrT
    lParam : LibC::IntPtrT
    time : UInt32
    pt : POINT
  end

  struct RECT
    left : Int32
    top : Int32
    right : Int32
    bottom : Int32
  end

  fun RegisterClassExW(lpWndClass : WNDCLASSEXW*) : UInt16
  fun CreateWindowExW(dwExStyle : UInt32, lpClassName : UInt16*, lpWindowName : UInt16*, dwStyle : UInt32,
                      x : Int32, y : Int32, nWidth : Int32, nHeight : Int32,
                      hWndParent : Void*, hMenu : Void*, hInstance : Void*, lpParam : Void*) : Void*
  fun ShowWindow(hWnd : Void*, nCmdShow : Int32) : Int32
  fun UpdateWindow(hWnd : Void*) : Int32
  fun DestroyWindow(hWnd : Void*) : Int32
  fun PostQuitMessage(nExitCode : Int32) : Void
  fun DefWindowProcW(hWnd : Void*, msg : UInt32, wParam : LibC::UIntPtrT, lParam : LibC::IntPtrT) : LibC::IntPtrT
  fun PeekMessageW(lpMsg : MSG*, hWnd : Void*, wMsgFilterMin : UInt32, wMsgFilterMax : UInt32, wRemoveMsg : UInt32) : Int32
  fun TranslateMessage(lpMsg : MSG*) : Int32
  fun DispatchMessageW(lpMsg : MSG*) : LibC::IntPtrT
  fun LoadCursorW(hInstance : Void*, lpCursorName : UInt16*) : Void*
  fun AdjustWindowRectEx(lpRect : RECT*, dwStyle : UInt32, bMenu : Int32, dwExStyle : UInt32) : Int32
  fun PostMessageW(hWnd : Void*, msg : UInt32, wParam : LibC::UIntPtrT, lParam : LibC::IntPtrT) : Int32
  fun GetKeyboardLayout(idThread : UInt32) : Void*
  fun GetKeyboardLayoutList(nBuff : Int32, lpList : Void**) : Int32
  fun ActivateKeyboardLayout(hkl : Void*, flags : UInt32) : Void*
  fun LoadKeyboardLayoutW(pwszKLID : UInt16*, flags : UInt32) : Void*
  fun SetForegroundWindow(hWnd : Void*) : Int32
  fun SetFocus(hWnd : Void*) : Void*
end

@[Link("imm32")]
lib IMM
  alias HIMC = Void*
  alias HKL  = Void*

  struct POINT
    x : Int32
    y : Int32
  end

  struct RECT
    left : Int32
    top : Int32
    right : Int32
    bottom : Int32
  end

  struct COMPOSITIONFORM
    dwStyle : UInt32
    ptCurrentPos : POINT
    rcArea : RECT
  end

  struct CANDIDATEFORM
    dwIndex : UInt32
    dwStyle : UInt32
    ptCurrentPos : POINT
    rcArea : RECT
  end

  struct CANDIDATELIST
    dwSize : UInt32
    dwStyle : UInt32
    dwCount : UInt32
    dwSelection : UInt32
    dwPageStart : UInt32
    dwPageSize : UInt32
    dwOffset : UInt32[1]
  end

  fun ImmGetContext(hWnd : Void*) : HIMC
  fun ImmReleaseContext(hWnd : Void*, hIMC : HIMC) : Int32
  fun ImmAssociateContext(hWnd : Void*, hIMC : HIMC) : HIMC
  fun ImmSetOpenStatus(hIMC : HIMC, fOpen : Int32) : Int32
  fun ImmGetOpenStatus(hIMC : HIMC) : Int32
  fun ImmSetCompositionWindow(hIMC : HIMC, lpCompForm : COMPOSITIONFORM*) : Int32
  fun ImmGetDescriptionW(hkl : HKL, lpszDescription : UInt16*, uBufLen : UInt32) : UInt32
  fun ImmGetIMEFileNameW(hkl : HKL, lpszFileName : UInt16*, uBufLen : UInt32) : UInt32
  fun ImmSetCompositionStringW(hIMC : HIMC, dwIndex : UInt32, lpComp : Void*, dwCompLen : UInt32, lpRead : Void*, dwReadLen : UInt32) : Int32
  fun ImmGetCompositionStringW(hIMC : HIMC, dwIndex : UInt32, lpBuf : Void*, dwBufLen : UInt32) : Int32
  fun ImmGetCandidateListCountW(hIMC : HIMC, lpdwListCount : UInt32*) : UInt32
  fun ImmGetCandidateListW(hIMC : HIMC, deIndex : UInt32, lpCandList : CANDIDATELIST*, dwBufLen : UInt32) : UInt32
  fun ImmGetCandidateWindow(hIMC : HIMC, dwIndex : UInt32, lpCandidate : CANDIDATEFORM*) : Int32
  fun ImmIsIME(hkl : HKL) : Int32
end

module ProbeState
  class_property quit_requested : Bool = false
  class_property hwnd : Void* = Pointer(Void).null
  class_property himc : IMM::HIMC = Pointer(Void).null

  class_property ime_setcontext : Int32 = 0
  class_property ime_start : Int32 = 0
  class_property ime_composition : Int32 = 0
  class_property ime_end : Int32 = 0
  class_property ime_notify : Int32 = 0

  class_property preedit_posted : Bool = false
  class_property preedit_seen : Bool = false
  class_property preedit_readback : String = ""
  class_property preedit_roundtrip : Bool = false
  class_property preedit_got_len : Int32 = -1

  class_property result_posted : Bool = false
  class_property result_seen : Bool = false
  class_property result_readback : String = ""
  class_property result_roundtrip : Bool = false
  class_property result_got_len : Int32 = -1

  class_property cand_pos : String = "not_triggered"
end

WS_OVERLAPPEDWINDOW = 0x00CF0000_u32
WS_VISIBLE          = 0x10000000_u32
CW_USEDEFAULT       = 0x80000000_u32.to_i32!
SW_SHOW             = 5
PM_REMOVE           = 0x0001_u32
WM_CLOSE            = 0x0010_u32
WM_DESTROY          = 0x0002_u32
WM_QUIT             = 0x0012_u32
WM_KEYDOWN          = 0x0100_u32
VK_ESCAPE           = 0x1B_u64
IDC_ARROW           = Pointer(UInt16).new(32512_u64)

WM_IME_SETCONTEXT       = 0x0281_u32
WM_IME_STARTCOMPOSITION = 0x010D_u32
WM_IME_COMPOSITION      = 0x010F_u32
WM_IME_ENDCOMPOSITION   = 0x010E_u32
WM_IME_NOTIFY           = 0x0282_u32

GCS_COMPSTR   = 0x0008_u32
GCS_CURSORPOS = 0x0080_u32
GCS_RESULTSTR = 0x0800_u32
SCS_SETSTR    = 0x0001_u32

IMN_SETCANDIDATEPOS = 0x0009_u32
IMN_OPENCANDIDATE   = 0x0005_u32
CFS_POINT           = 0x0002_u32
KLF_ACTIVATE        = 0x00000001_u32

def to_wstr(s : String) : Slice(UInt16)
  u = s.to_utf16
  buf = Slice(UInt16).new(u.size + 1, 0_u16)
  u.size.times { |i| buf[i] = u[i] }
  buf
end

def utf16_to_string(buf : Slice(UInt16), byte_len : Int32) : String
  return "" if byte_len <= 0
  count = byte_len // 2
  return "" if count <= 0
  slice = buf.to_unsafe.to_slice(count)
  String.from_utf16(slice)
end

def read_comp_string(himc : IMM::HIMC, index : UInt32) : {String, Int32}
  needed = IMM.ImmGetCompositionStringW(himc, index, Pointer(Void).null, 0_u32)
  return {"", needed} if needed <= 0
  u16_count = (needed + 1) // 2
  buf = Slice(UInt16).new(u16_count + 1, 0_u16)
  got = IMM.ImmGetCompositionStringW(himc, index, buf.to_unsafe.as(Void*), needed.to_u32)
  if got <= 0
    return {"", got}
  end
  {utf16_to_string(buf, got), got}
end

def sanitize_json_str(s : String) : String
  s.gsub("\\", "\\\\").gsub("\"", "\\\"").gsub("\n", "\\n").gsub("\r", "\\r")
end

def pump_messages(iterations : Int32)
  msg = U32::MSG.new
  iterations.times do
    while U32.PeekMessageW(pointerof(msg), Pointer(Void).null, 0_u32, 0_u32, PM_REMOVE) != 0
      if msg.message == WM_QUIT
        ProbeState.quit_requested = true
        break
      end
      U32.TranslateMessage(pointerof(msg))
      U32.DispatchMessageW(pointerof(msg))
    end
    break if ProbeState.quit_requested
  end
end

WNDPROC = ->(hwnd : Void*, msg : UInt32, wparam : LibC::UIntPtrT, lparam : LibC::IntPtrT) : LibC::IntPtrT do
  case msg
  when WM_CLOSE
    U32.DestroyWindow(hwnd)
    return 0_i64
  when WM_DESTROY
    U32.PostQuitMessage(0)
    ProbeState.quit_requested = true
    return 0_i64
  when WM_KEYDOWN
    if wparam.to_u64 == VK_ESCAPE
      U32.DestroyWindow(hwnd)
      return 0_i64
    end
  when WM_IME_SETCONTEXT
    ProbeState.ime_setcontext += 1
  when WM_IME_STARTCOMPOSITION
    ProbeState.ime_start += 1
  when WM_IME_COMPOSITION
    ProbeState.ime_composition += 1
    lp = lparam.to_u64.to_u32
    himc = ProbeState.himc
    unless himc.null?
      if ProbeState.preedit_posted && !ProbeState.preedit_seen && (lp & GCS_COMPSTR) != 0
        txt, got = read_comp_string(himc, GCS_COMPSTR)
        ProbeState.preedit_readback = txt
        ProbeState.preedit_got_len = got
        ProbeState.preedit_seen = true
        ProbeState.preedit_roundtrip = (txt == "nihao")
      end
      if ProbeState.result_posted && !ProbeState.result_seen && (lp & GCS_RESULTSTR) != 0
        txt, got = read_comp_string(himc, GCS_RESULTSTR)
        ProbeState.result_readback = txt
        ProbeState.result_got_len = got
        ProbeState.result_seen = true
        ProbeState.result_roundtrip = (txt == "你好")
      end
    end
  when WM_IME_ENDCOMPOSITION
    ProbeState.ime_end += 1
  when WM_IME_NOTIFY
    ProbeState.ime_notify += 1
    cmd = wparam.to_u64.to_u32
    if cmd == IMN_SETCANDIDATEPOS
      cf = IMM::CANDIDATEFORM.new
      cf.dwIndex = 0_u32
      if IMM.ImmGetCandidateWindow(ProbeState.himc, 0_u32, pointerof(cf)) != 0
        ProbeState.cand_pos = "#{cf.ptCurrentPos.x},#{cf.ptCurrentPos.y}"
      else
        ProbeState.cand_pos = "notify_no_window"
      end
    end
  end
  U32.DefWindowProcW(hwnd, msg, wparam, lparam)
end

frames_target = 60
json_out = false
i = 0
while i < ARGV.size
  a = ARGV[i]
  if a.starts_with?("--frames=")
    frames_target = a.split("=", 2)[1].to_i
  elsif a == "--frames" && i + 1 < ARGV.size
    frames_target = ARGV[i + 1].to_i
    i += 1
  elsif a == "--json"
    json_out = true
  end
  i += 1
end

hinstance = K32.GetModuleHandleW(Pointer(UInt16).null)
class_name = to_wstr("TessellM2ImeProbe")
title = to_wstr("Tessell M2 IME Probe")

wc = U32::WNDCLASSEXW.new
wc.cbSize = sizeof(U32::WNDCLASSEXW).to_u32
wc.style = 0_u32
wc.lpfnWndProc = WNDPROC
wc.cbClsExtra = 0
wc.cbWndExtra = 0
wc.hInstance = hinstance
wc.hIcon = Pointer(Void).null
wc.hCursor = U32.LoadCursorW(Pointer(Void).null, IDC_ARROW)
wc.hbrBackground = Pointer(Void).null
wc.lpszMenuName = Pointer(UInt16).null
wc.lpszClassName = class_name.to_unsafe
wc.hIconSm = Pointer(Void).null
atom = U32.RegisterClassExW(pointerof(wc))

width = 320
height = 240
rect = U32::RECT.new
rect.left = 0
rect.top = 0
rect.right = width
rect.bottom = height
U32.AdjustWindowRectEx(pointerof(rect), WS_OVERLAPPEDWINDOW, 0, 0)
win_w = rect.right - rect.left
win_h = rect.bottom - rect.top

hwnd = U32.CreateWindowExW(0_u32, class_name.to_unsafe, title.to_unsafe, WS_OVERLAPPEDWINDOW | WS_VISIBLE,
  CW_USEDEFAULT, CW_USEDEFAULT, win_w, win_h, Pointer(Void).null, Pointer(Void).null, hinstance, Pointer(Void).null)
ProbeState.hwnd = hwnd

if hwnd.null?
  err = K32.GetLastError
  puts "ime_injection=blocked ime_injection_reason=create_window_failed ime_injection_available=false ime_hkl_is_ime=false ime_desc=(empty) ime_file= imm_available=false imm_set_str_ret=0 preedit_roundtrip=false preedit_text= result_roundtrip=false result_text= preedit_expected_len=5 preedit_got_len=-1 result_expected_len=2 result_got_len=-1 candidate_list_bytes=0 candidate_list_count_raw=0 candidate_list_entries=0 cand_pos=not_triggered IMM_ERR=create_window_#{err} frames=0 kl_count=0 kl_ids="
  puts "IME_PROBE_EXIT=0"
  exit 0
end

U32.ShowWindow(hwnd, SW_SHOW)
U32.UpdateWindow(hwnd)
U32.SetForegroundWindow(hwnd)
U32.SetFocus(hwnd)
pump_messages(5)

# Enumerate keyboard layouts
kl_count = U32.GetKeyboardLayoutList(0, Pointer(Void*).null)
kl_ids_list = [] of String
active_hkl = U32.GetKeyboardLayout(0_u32)
active_hkl_val = active_hkl.address.to_u64
if kl_count > 0
  arr = Pointer(Void*).malloc(kl_count)
  got = U32.GetKeyboardLayoutList(kl_count, arr)
  got.times do |idx|
    h = arr[idx]
    kl_ids_list << "0x#{h.address.to_s(16)}"
  end
end
kl_ids_str = kl_ids_list.join(",")

# Try to activate a non-US layout if present (prefer one with different lang id than 0x0409)
activated_hkl = active_hkl
if kl_count > 0
  arr2 = Pointer(Void*).malloc(kl_count)
  got2 = U32.GetKeyboardLayoutList(kl_count, arr2)
  chosen = Pointer(Void).null
  got2.times do |idx|
    h = arr2[idx]
    lid = (h.address.to_u64 & 0xFFFF_u64)
    if lid != 0x0409_u64 && lid != 0x0000_u64
      chosen = h
      break
    end
  end
  if chosen.null?
    # fallback: any different from active
    got2.times do |idx|
      h = arr2[idx]
      if h.address != active_hkl.address
        chosen = h
        break
      end
    end
  end
  unless chosen.null?
    ret_act = U32.ActivateKeyboardLayout(chosen, KLF_ACTIVATE)
    unless ret_act.null?
      activated_hkl = ret_act
    end
    pump_messages(5)
  end
end

# Get context after focus/activation
himc = IMM.ImmGetContext(hwnd)
ProbeState.himc = himc
imm_available = !himc.null?
imm_err = "none"
ime_desc = ""
ime_file = ""
imm_open_status = -1
imm_set_open_ret = -1
imm_set_str_preedit_ret = 0
imm_set_str_result_ret = 0
candidate_list_bytes = 0_u32
candidate_list_count_raw = 0_u32
candidate_list_entries = 0_u32
preedit_expected_len = "nihao".size
result_expected_len = "你好".size
imm_is_ime_flag = false

hkl_for_desc = U32.GetKeyboardLayout(0_u32)
imm_is_ime_flag = IMM.ImmIsIME(hkl_for_desc) != 0

if imm_available
  hkl = hkl_for_desc
  dbuf = Slice(UInt16).new(256, 0_u16)
  dlen = IMM.ImmGetDescriptionW(hkl, dbuf.to_unsafe, 256_u32)
  if dlen > 0
    ime_desc = String.from_utf16(dbuf.to_unsafe.to_slice(dlen.to_i))
  end
  fbuf = Slice(UInt16).new(260, 0_u16)
  flen = IMM.ImmGetIMEFileNameW(hkl, fbuf.to_unsafe, 260_u32)
  if flen > 0
    ime_file = String.from_utf16(fbuf.to_unsafe.to_slice(flen.to_i))
  end

  IMM.ImmAssociateContext(hwnd, himc)
  imm_set_open_ret = IMM.ImmSetOpenStatus(himc, 1)
  imm_open_status = IMM.ImmGetOpenStatus(himc)

  comp = IMM::COMPOSITIONFORM.new
  comp.dwStyle = CFS_POINT
  comp.ptCurrentPos = IMM::POINT.new
  comp.ptCurrentPos.x = 10
  comp.ptCurrentPos.y = 10
  comp.rcArea = IMM::RECT.new
  comp.rcArea.left = 0
  comp.rcArea.top = 0
  comp.rcArea.right = width
  comp.rcArea.bottom = height
  IMM.ImmSetCompositionWindow(himc, pointerof(comp))

  # Candidate probe: ImmGetCandidateListCountW returns bytes needed, lpdwListCount receives number of lists
  candidate_list_bytes = IMM.ImmGetCandidateListCountW(himc, pointerof(candidate_list_count_raw))
  if candidate_list_bytes > 0
    # try to read first candidate list to get dwCount (entries)
    buf = Pointer(UInt8).malloc(candidate_list_bytes.to_i)
    got_cand = IMM.ImmGetCandidateListW(himc, 0_u32, buf.as(IMM::CANDIDATELIST*), candidate_list_bytes)
    if got_cand > 0
      cl = buf.as(IMM::CANDIDATELIST*).value
      candidate_list_entries = cl.dwCount
    else
      candidate_list_entries = 0_u32
    end
  else
    candidate_list_entries = 0_u32
  end

  # Programmatic injection attempt: preedit "nihao"
  pre_utf16 = "nihao".to_utf16
  pre_bytes = (pre_utf16.size * 2).to_u32
  imm_set_str_preedit_ret = IMM.ImmSetCompositionStringW(himc, SCS_SETSTR, pre_utf16.to_unsafe.as(Void*), pre_bytes, Pointer(Void).null, 0_u32)
  if imm_set_str_preedit_ret != 0
    ProbeState.preedit_posted = true
    U32.PostMessageW(hwnd, WM_IME_COMPOSITION, 0_u64, GCS_COMPSTR.to_i64)
  end

  pump_messages(10)

  res_utf16 = "你好".to_utf16
  res_bytes = (res_utf16.size * 2).to_u32
  imm_set_str_result_ret = IMM.ImmSetCompositionStringW(himc, SCS_SETSTR, res_utf16.to_unsafe.as(Void*), res_bytes, Pointer(Void).null, 0_u32)
  if imm_set_str_result_ret != 0
    ProbeState.result_posted = true
    U32.PostMessageW(hwnd, WM_IME_COMPOSITION, 0_u64, GCS_RESULTSTR.to_i64)
  end
else
  imm_err = "ImmGetContext_null win32_error=#{K32.GetLastError}"
  imm_set_str_preedit_ret = 0
  imm_set_str_result_ret = 0
end

frames_done = 0
msg = U32::MSG.new
while frames_done < frames_target && !ProbeState.quit_requested
  while U32.PeekMessageW(pointerof(msg), Pointer(Void).null, 0_u32, 0_u32, PM_REMOVE) != 0
    if msg.message == WM_QUIT
      ProbeState.quit_requested = true
      break
    end
    U32.TranslateMessage(pointerof(msg))
    U32.DispatchMessageW(pointerof(msg))
  end
  break if ProbeState.quit_requested
  frames_done += 1
end

programmatic_available = imm_available && (imm_set_str_preedit_ret != 0 || imm_set_str_result_ret != 0)
reported_ime_injection_available = programmatic_available ? "true" : "false"
reported_imm_set_str_ret = if !imm_available
  0
elsif imm_set_str_preedit_ret != 0
  imm_set_str_preedit_ret
elsif imm_set_str_result_ret != 0
  imm_set_str_result_ret
else
  0
end

if !imm_available
  imm_err = "ImmGetContext_null" if imm_err == "none"
  ime_injection = "blocked"
  ime_injection_reason = "imm_context_unavailable"
elsif !programmatic_available
  win32e = K32.GetLastError
  imm_err = "ImmSetCompositionStringW_rejected preedit_ret=#{imm_set_str_preedit_ret} result_ret=#{imm_set_str_result_ret} win32_error=#{win32e}" if imm_err == "none"
  ime_injection = "blocked"
  ime_injection_reason = imm_is_ime_flag ? "imm_set_composition_rejected" : "no_active_ime_on_host"
else
  ime_injection = "ok"
  ime_injection_reason = "none"
end

preedit_text_out = ProbeState.preedit_readback
result_text_out = ProbeState.result_readback
preedit_roundtrip_out = ProbeState.preedit_roundtrip && ProbeState.preedit_seen
result_roundtrip_out = ProbeState.result_roundtrip && ProbeState.result_seen
preedit_got_len = ProbeState.preedit_got_len
result_got_len = ProbeState.result_got_len

safe_desc = ime_desc.empty? ? "(empty)" : ime_desc.gsub(/\s+/, "_")
safe_file = ime_file.empty? ? "(empty)" : ime_file.gsub(/\s+/, "_")
safe_preedit = preedit_text_out.gsub(/\s+/, "_")
safe_result = result_text_out.gsub(/\s+/, "_")
safe_err = imm_err.gsub(/\s+/, "_")
safe_cand_pos = ProbeState.cand_pos.gsub(/\s+/, "_")
safe_kl_ids = kl_ids_str.gsub(/\s+/, "_")

line = "ime_injection=#{ime_injection} ime_injection_reason=#{ime_injection_reason} ime_injection_available=#{reported_ime_injection_available} ime_hkl_is_ime=#{imm_is_ime_flag} ime_desc=#{safe_desc} ime_file=#{safe_file} imm_available=#{imm_available} imm_is_ime=#{imm_is_ime_flag} imm_open_status=#{imm_open_status} imm_set_open_ret=#{imm_set_open_ret} imm_set_str_ret=#{reported_imm_set_str_ret} imm_set_str_preedit_ret=#{imm_set_str_preedit_ret} imm_set_str_result_ret=#{imm_set_str_result_ret} preedit_roundtrip=#{preedit_roundtrip_out} preedit_text=#{safe_preedit} preedit_expected_len=#{preedit_expected_len} preedit_got_len=#{preedit_got_len} result_roundtrip=#{result_roundtrip_out} result_text=#{safe_result} result_expected_len=#{result_expected_len} result_got_len=#{result_got_len} candidate_list_bytes=#{candidate_list_bytes} candidate_list_count_raw=#{candidate_list_count_raw} candidate_list_entries=#{candidate_list_entries} cand_pos=#{safe_cand_pos} ime_messages_setcontext=#{ProbeState.ime_setcontext} ime_messages_start=#{ProbeState.ime_start} ime_messages_composition=#{ProbeState.ime_composition} ime_messages_end=#{ProbeState.ime_end} ime_messages_notify=#{ProbeState.ime_notify} kl_count=#{kl_count} kl_ids=#{safe_kl_ids} active_hkl=0x#{active_hkl_val.to_s(16)} activated_hkl=0x#{activated_hkl.address.to_s(16)} IMM_ERR=#{safe_err} frames=#{frames_done} hwnd=0x#{hwnd.address.to_s(16)} himc=0x#{himc.address.to_s(16)}"
puts line

if json_out
  ime_desc_json = ime_desc.empty? ? "(empty)" : ime_desc
  ime_file_json = ime_file.empty? ? "(empty)" : ime_file
  json = %({"ime_injection":"#{ime_injection}","ime_injection_reason":"#{ime_injection_reason}","ime_injection_available":#{reported_ime_injection_available},"ime_hkl_is_ime":#{imm_is_ime_flag},"ime_desc":"#{sanitize_json_str(ime_desc_json)}","ime_file":"#{sanitize_json_str(ime_file_json)}","imm_available":#{imm_available},"imm_is_ime":#{imm_is_ime_flag},"imm_open_status":#{imm_open_status},"imm_set_str_ret":#{reported_imm_set_str_ret},"imm_set_str_preedit_ret":#{imm_set_str_preedit_ret},"imm_set_str_result_ret":#{imm_set_str_result_ret},"preedit_roundtrip":#{preedit_roundtrip_out},"preedit_text":"#{sanitize_json_str(preedit_text_out)}","preedit_expected_len":#{preedit_expected_len},"preedit_got_len":#{preedit_got_len},"result_roundtrip":#{result_roundtrip_out},"result_text":"#{sanitize_json_str(result_text_out)}","result_expected_len":#{result_expected_len},"result_got_len":#{result_got_len},"candidate_list_bytes":#{candidate_list_bytes},"candidate_list_entries":#{candidate_list_entries},"cand_pos":"#{sanitize_json_str(ProbeState.cand_pos)}","kl_count":#{kl_count},"kl_ids":"#{sanitize_json_str(kl_ids_str)}","IMM_ERR":"#{sanitize_json_str(imm_err)}","frames":#{frames_done}})
  puts json
end

IMM.ImmReleaseContext(hwnd, himc) unless himc.null?
U32.DestroyWindow(hwnd) unless ProbeState.quit_requested
puts "IME_PROBE_EXIT=0"
exit 0
