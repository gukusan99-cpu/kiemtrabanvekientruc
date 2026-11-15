# tools/lisplint.py — kiểm tra tĩnh AutoLISP

Công cụ Python 3 (chỉ dùng thư viện chuẩn) để kiểm tra mã `.lsp` khi không có AutoCAD/VinaCAD.

```bash
python3 tools/lisplint.py lisp/                 # cả thư mục (đệ quy, coi là 1 dự án)
python3 tools/lisplint.py a.lsp b.lsp --json    # xuất JSON
python3 tools/lisplint.py lisp/ --min-level WARN  # ẩn INFO
python3 -m unittest tools/test_lisplint.py -v   # chạy test
```

Đầu ra: `file:dòng: MỨC: thông điệp [MÃ]`, dòng cuối là tổng kết.
Exit code: `0` không có ERROR, `1` có ERROR, `2` lỗi sử dụng (không tìm thấy file).

| Mã | Mức | Ý nghĩa |
|---|---|---|
| PAREN, STRING, COMMENT | ERROR | ngoặc thiếu/thừa, chuỗi hoặc comment khối `;\| \|;` chưa đóng |
| UNDEF-FUNC | ERROR (WARN với `vl-*`/`vlax-*` lạ) | gọi hàm không có defun trong dự án và không phải built-in |
| NOT-FUNC, SYNTAX, SETQ-CONST | ERROR | đầu list là số/chuỗi, setq lẻ, `if` thừa nhánh… |
| ARITY | ERROR | sai số đối số so với defun trong dự án (và một số built-in hay dùng) |
| DUP-CMD | ERROR | lệnh `c:XXX` định nghĩa trùng |
| DCL-ACTION | ERROR | chuỗi mã của `action_tile` / `new_dialog` sai cú pháp hoặc gọi `$value`… như hàm. Hàm gọi trong chuỗi cũng được kiểm UNDEF-FUNC/ARITY (`$key $value $reason $data $x $y` là biến DCL) |
| DUP-DEFUN, REDEF-BUILTIN, DUP-LOCAL | WARN | defun trùng tên / ghi đè built-in / biến khai báo 2 lần |
| LEAK | WARN | biến được `setq` trong defun mà không khai báo sau `/` (trừ `*TEN*`) |
| RISKY | WARN | hàm rủi ro trên VinaCAD/IntelliCAD — danh sách `RISKY_FUNCTIONS` ở đầu `lisplint.py` |
| NON-ASCII | WARN | chuỗi có ký tự Unicode (nên dùng tiếng Việt không dấu) |
| VL-LOAD-COM | WARN | dùng vla-/vlax- nhưng không có `(vl-load-com)` |
| ACTIVEX | INFO | gọi `vla-*` (phụ thuộc ActiveX) |

Chỉ thị trong comment của file `.lsp`:

```lisp
; lisplint: extern LM:ssget LM:str->lst     ; khai báo hàm ngoài (thư viện nạp riêng)
(foo) ; lisplint: ignore                    ; bỏ qua mọi cảnh báo trên dòng này
(bar) ; lisplint: ignore=LEAK,RISKY         ; bỏ qua mã chỉ định
```

## Giới hạn đã biết

- Không chạy mã: không biết hàm tạo động (`eval`, `read`, `defun-q-list-set`, `load` file ngoài dự án) — dùng `; lisplint: extern`.
- Thiếu ngoặc được định vị theo giả định mỗi form top-level bắt đầu ở cột 0; nếu code thụt lề bất thường chỉ báo được dòng mở ngoài cùng.
- Kiểm tra số đối số built-in chỉ có cho danh sách `BUILTIN_ARITY` (hàm thông dụng); `vla-*` không kiểm tra tên/đối số.
- Kiểm tra rò rỉ chỉ xét `setq`/`(set 'x)`; không phát hiện biến chỉ đọc mà chưa gán, không mô phỏng phạm vi động.
- Hàm khai báo trùng với số tham số khác nhau thì bỏ qua kiểm tra số đối số.

## tools/lispsim/dcl.py — giả lập DCL

`attach_dcl(session)` cài `load_dialog`/`new_dialog`/`start_dialog`/`action_tile`/`set_tile`/`start_list`…
vào lispsim: parse file `.dcl` (ngoặc nhọn, `;`, chỉ tile cơ bản, key không trùng), báo `problems` khi
`set_tile`/`action_tile` dùng key không có hoặc gọi `command`/`get*`/`entmake`/zoom lúc hộp thoại đang mở.
`dlg.script` = danh sách lần mở hộp thoại, mỗi lần là các bước `(key giá-trị [reason])` / `(key,)` / hàm Python.
`attach_dcl(s, available=False | fail_load=True | fail_new=True)` mô phỏng CAD không có DCL. Ví dụ: `tests/test_dialog.py`.
