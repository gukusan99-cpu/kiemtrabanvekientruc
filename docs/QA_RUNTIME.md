# QA chạy thử (runtime) – bộ KT trên trình giả lập `tools/lispsim`

Không có AutoCAD trên máy, nên các file `lisp/*.lsp` được **chạy thật** trên một trình thông dịch
tập con AutoLISP viết bằng Python (chỉ thư viện chuẩn) với CSDL bản vẽ giả lập.

```bash
python3 -m unittest tests/test_runtime.py -v          # 20 test, ~4 s
KT_VERBOSE=1 python3 -m unittest tests/test_runtime.py  # in danh sách lỗi KT tìm được (để soi báo nhầm)
LISPSIM_LISPDIR=/duong/dan/lisp python3 -m unittest tests/test_runtime.py   # chạy trên bản lisp khác
```

Lần chạy cuối: trên bản `lisp/` mới nhất của workspace (sau commit `a65fdd9`, KT_Sheet.lsp đang sửa dở).
Kết quả: **15/20 test đạt, 5 test fail – cả 5 đều do một bug LISP duy nhất (B1).** Khi chạy lại trên bản
`lisp/` đã vá B1 (sửa 1 dòng, xem dưới) thì **20/20 đạt**.

---

## 1. Kết quả từng kịch bản

| # | Kịch bản | Kết quả |
|---|---|---|
| 0 | Ngữ nghĩa trình giả lập (chia nguyên, phạm vi động, thông báo lỗi, wcmatch, `*error*`) | ĐẠT |
| 1 | KTMAU trên bản vẽ MẪU → `KT_ChuanCongTy.txt` | **FAIL do B1**: file được ghi, hợp lệ, có SETTING/LAYER/TEXTSTYLE/KHUNG/BLOCK/LAYOUT/DANHMUC, nhưng **mục DIMSTYLE rỗng** và TEXTSTYLE thiếu `KT-DIM`. Đã vá B1 → đạt toàn bộ. |
| 2 | KTALL trên chính bản vẽ mẫu | ĐẠT: **0 LOI, 0 CANHBAO**, 2 GOIY đúng thực tế (block `CUA_DI_900` không được chèn: BLOCK-LAYER, BLOCK-THUA). Không có lỗi nội bộ, không sửa/xóa đối tượng gốc. |
| 3 | Bản vẽ NHÂN VIÊN có 12 lỗi cài | 11/12 phát hiện đúng mã + đúng đối tượng. **DIM-STYLE không phát hiện – hệ quả của B1** (chuẩn không có DIMSTYLE nên KTDIM bỏ qua kiểm tra). Với file chuẩn đủ DIMSTYLE: 12/12. |
| 4 | Chế độ VinaCAD (mọi `vla-*`/`vlax-*` → "no function definition") | ĐẠT: 14 lệnh không crash; kết quả KTALL **giống hệt** chế độ AutoCAD (đường dự phòng DXF của `kt:box`/`kt:effname` hoạt động, kể cả khung tên là dynamic block `*U`). KTMAU fail chỉ vì B1. |
| 5 | KTN/KTP/KTX/KTBC + CSV | ĐẠT: KTN/KTP xoay vòng đúng "Loi i/n", chuyển CTAB sang layout khi lỗi ở layout; KTBC ghi `C:\DuAn\NHANVIEN_KiemTra.csv` (dòng `sep=,` + header 9 cột, mỗi dòng 9 cột, STT liên tục); KTX xóa hết đánh dấu KT_CHECK và danh sách lỗi. |
| 6 | Hiệu chuẩn: `legacy/CheckDimOverlap.lsp` (CDO, CDON, CDOX) | ĐẠT: chạy không lỗi, tìm đúng 1 cặp TRUNG. |

Lỗi cài trong bản vẽ nhân viên và mã được báo:

| Lỗi cài | Mã KT | |
|---|---|---|
| layer lạ `ABC-LA` | LAYER-LA (LOI) | ✓ |
| CIRCLE trên layer 0 | LAYER-0 (LOI) | ✓ |
| dim style lạ `ISO-25` | DIM-STYLE (LOI) | ✗ do B1 (✓ khi vá) |
| dim 1-50 trong khung 1/100 | DIM-TYLE (CANHBAO) | ✓ |
| dim ghi đè 3300, đo 3250 | DIM-GHIDE (LOI) "Ghi 3300 nhung do 3250" | ✓ |
| TEXT cao 400 ở 1/100 (4 mm) | TEXT-CAO (CANHBAO) | ✓ |
| 2 dim trùng | DIM-TRUNG (LOI) | ✓ |
| trục B mặt cắt lệch 100 | KHOP-TRUC (LOI) A-B 4500/4600, B-C 3300/3200 | ✓ |
| số hiệu khung trùng KT-02 | KHUNG-TRUNGSO (LOI) | ✓ |
| attribute NGAY rỗng | KHUNG-THIEU (CANHBAO) | ✓ |
| 2 LINE trùng (ngược chiều) | LINE-TRUNG (CANHBAO) | ✓ |
| LINE Z = 150 | Z-KHAC0 (CANHBAO) | ✓ |

Thử thêm (ngoài 5 kịch bản, script tạm, không đưa vào test): dim trục ghi sai → KHOP-DIMTRUC, dim tổng
sai → KHOP-TONG, cao độ +7.200 lệch 150 → KHOP-CAODO-VITRI, thứ tự trục A,C,B → KHOP-THUTU, khung ghi
1/50 chèn 1/100 → KHUNG-TYLE, nhảy số KT-04 → KHUNG-NHAYSO, ký hiệu mặt cắt trỏ KT-09 → KHUNG-THAMCHIEU,
xref mất → XREF-MAT, override DSTYLE DIMLFAC=2 → DIM-LFAC, layer tắt/đóng băng → LAYER-TAT, màu
ByObject → MAU-BYOBJ, polyline 1 đỉnh → PLINE-0, block chèn chồng → BLOCK-TRUNG, MTEXT rỗng → TEXT-RONG:
**tất cả phát hiện đúng, giống nhau ở 2 chế độ**. Bản vẽ rỗng, bản vẽ chỉ có khung ở layout, chưa có file
chuẩn, ESC ở từng prompt của KTMAU (in "Da huy, chua ghi file", không ghi file): không crash.
Đo số lần gọi hàm với 500 / 2000 đối tượng thêm: tăng tuyến tính ở cả 6 module (không có điểm O(n²)).

---

## 2. Bug LISP

### B1 – NGHIÊM TRỌNG – KTMAU không trích được mục DIMSTYLE
- **Vị trí**: `lisp/KT_Template.lsp:301`, hàm `ktmau:sec-dimstyle`.
- **Triệu chứng**: KTMAU in `[KTMAU] Loi khi chay KTMAU:SEC-DIMSTYLE: bad argument type: listp T`;
  file chuẩn sinh ra có mục DIMSTYLE **rỗng** và TEXTSTYLE thiếu textstyle của dim (`KT-DIM`).
  Hệ quả dây chuyền: KTDIM in "File chuan chua co muc DIMSTYLE - bo qua kiem tra DIM-STYLE" → **không bao
  giờ phát hiện dimstyle lạ**; DIM-LFAC so với mặc định 1 thay vì chuẩn; KTTEXT báo TEXT-STYLE nhầm cho
  chữ dùng style của dim (nếu có TEXT dùng `KT-DIM`). Xảy ra trên MỌI bản vẽ, cả AutoCAD lẫn VinaCAD.
- **Nguyên nhân**: `(cond ((and e (entget e))) (d))` – mệnh đề cond chỉ có biểu thức kiểm tra thì trả về
  giá trị của biểu thức đó, mà `and` trong AutoLISP trả về `T` chứ không trả về giá trị cuối →
  `ed = T` → `(kt:dxf 340 T)` → `(assoc 340 T)` lỗi. Ngăn xếp:
  `C:KTMAU > KTMAU:TRY > KTMAU:SEC-DIMSTYLE > KTMAU:DIM-TSTYLE > KT:DXF` (`KT_Core.lsp:260`).
- **Sửa**:
  ```lisp
  (setq e  (tblobjname "DIMSTYLE" nm)
        ed (cond ((and e (entget e))) (d))          ; SAI: and -> T
  ;; thanh (if tra ve gia tri entget, nil neu khong co)
  (setq e  (tblobjname "DIMSTYLE" nm)
        ed (cond ((if e (entget e))) (d))
  ;; hoac: ed (cond ((and e (entget e)) (entget e)) (d))
  ```
  Đã kiểm: vá dòng này → 20/20 test đạt, file chuẩn có `DIMSTYLE|1-100|100|1|2|1.5|KT-DIM|0|0`,
  `DIMSTYLE|1-50|...`, `TEXTSTYLE|KT-DIM|romans.shx||0|0.8`, KTALL trên bản vẽ nhân viên báo đủ 12/12.
- Đã quét toàn bộ `lisp/*.lsp` bằng reader của lispsim tìm mẫu `(cond ... ((and ...)) ...)` /
  `((or ...))` dùng làm giá trị: **chỉ có 1 chỗ này**. Đề nghị thêm luật này vào `tools/lisplint.py`
  (mệnh đề cond 1 phần tử mà là `and`/`or` → cảnh báo "trả về T, không phải giá trị").

### Quan sát (không phải bug, mức THẤP – để nhóm thiết kế quyết)
- O1 `KT_Match.lsp`, `ktmat:chk-axes`: khi thứ tự trục trên 1 bản vẽ bị đảo (A,C,B), chỉ cặp *liên tiếp*
  (A-C, C-B) được bỏ phiếu báo KHOP-TRUC; cặp A-B (không liên tiếp ở bản vẽ đó) không báo. Đã có
  KHOP-THUTU báo kèm nên người dùng vẫn thấy lỗi – chấp nhận được.
- O2 DIM-TYLE hiện là CANHBAO (đội review hạ mức) – docs/ARCHITECTURE và đầu file KT_Dim.lsp ghi LOI;
  nên thống nhất tài liệu.

---

## 3. Bug của công cụ lispsim (đã sửa, KHÔNG phải bug LISP)
- `PI` chưa được định nghĩa sẵn (AutoLISP có `PI`, `PAUSE`) → `ktmat:hv` và `ktcl:chk-insert-dup` lỗi
  `numberp: nil` giả. Đã thêm.
- Dòng `sep=,` đầu CSV và ô X/Y rỗng cho mục tổng kết là thay đổi CÓ CHỦ Ý của đội review → sửa test.
- Kịch bản nhập liệu KTMAU phải cập nhật khi đội review đổi câu hỏi tỷ lệ gốc ("Ty le goc (he so nhan voi
  scale X block)"). Câu trả lời trong test có kiểm chuỗi con của prompt (`Ans(value, match)`); lệch prompt
  → lỗi loại `sim` chứ không bị nhầm là bug LISP.

---

## 4. Công cụ lispsim – phạm vi và giới hạn

`tools/lispsim/`: `reader.py` (đọc mã, ghi file:dòng cho mỗi form), `interp.py` (bộ đánh giá + hàm
chuẩn), `cad.py` (entget/ssget/tbl*/entmake…, sysvar, file ảo, nhập liệu, ActiveX), `drawing.py` (CSDL +
builder), `fixtures.py` (bản vẽ MẪU / NHÂN VIÊN), `session.py` (phiên chạy).

- Ngữ nghĩa: phạm vi động (binding nông, khôi phục cả khi lỗi), biến local sau `/`, `nil`='()`, `T`,
  INT 32 bit (tràn số quay vòng + ghi cảnh báo) vs REAL, `/` 2 INT chia nguyên, cặp chấm, `and`/`or` trả `T`,
  `foreach` khôi phục biến, `vl-sort` xóa phần tử trùng (eq) như AutoCAD, `rtos` theo DIMZIN (mặc định 8).
- Lỗi giống AutoCAD (`bad argument type: stringp nil`, `numberp: "a"`, `consp 5`, `fixnump: 2.5`,
  `no function definition: X`, `too few/many arguments`, `divide by zero`) kèm ngăn xếp tên hàm defun và
  file:dòng của form. Lỗi không bị bắt → gọi `*error*` *tại chỗ* (biến local `*error*` còn hiệu lực) như
  AutoCAD. Lỗi bị `vl-catch-all-apply` bắt vẫn được ghi lại (`RunResult.caught`) để soi lỗi bị nuốt –
  đây là cách B1 được phát hiện (KTMAU nuốt lỗi và vẫn ghi file).
- CSDL: bảng LAYER/LTYPE/STYLE/DIMSTYLE/BLOCK/APPID, block (BLOCK…ENDBLK, ATTDEF), INSERT + ATTRIB + SEQEND,
  LINE, LWPOLYLINE, CIRCLE, TEXT, MTEXT, DIMENSION (+ block ẩn danh `*D` chứa LINE + MTEXT), VIEWPORT,
  layout (410/67), XDATA (ACAD DSTYLE, AcadAnnotative, AcDbBlockRepBTag), dictionary ACAD_LAYOUT.
  `tblsearch/tblnext "LAYER"` trả bản rút gọn (0 2 70 62 6) như AutoCAD.
  `entdel/entmod` lên đối tượng gốc được ghi vào `Drawing.violations` (kiểm quy tắc "không sửa bản vẽ").
- `ssget "_X"` có bộ lọc đầy đủ (`-4` `<AND <OR <NOT <XOR`, toán tử so sánh, wildcard không phân biệt hoa
  thường, 410, 62 mặc định 256); `ssget` không `"_X"` → Enter (nil) hoặc lấy từ `ss_inputs`.
- Nhập liệu: `getstring/getreal/getint/getkword/entsel/getpoint` lấy từ hàng đợi `Ans(...)`; hết hàng đợi =
  Enter (`getstring` → `""`); `Ans(CANCEL)` = ESC; `initget` bit 1/2/4 + từ khóa viết tắt.
- `"acad"`: ActiveX tối thiểu (`vla-GetBoundingBox` tính từ hình học thật kể cả INSERT lồng, attribute,
  `vla-get-EffectiveName` cho dynamic block); hàm `vla-*` chưa giả lập → lỗi loại `sim`
  (`SIM-UNSUPPORTED`), không lẫn với bug LISP. `"vinacad"`: không định nghĩa bất kỳ `vla-*`/`vlax-*`.
- **Giới hạn**: kích thước chữ (`textbox`, hộp bao TEXT/MTEXT) là ước lượng 0.75×h×số ký tự; không có
  HATCH/TABLE/IMAGE/xref thật; `distof` chỉ nhận dạng thập phân; tốc độ không phản ánh AutoCAD;
  hành vi riêng của VinaCAD ngoài ActiveX (vd. `layoutlist`, `vl-catch-all-apply` với `exit`) giả định
  giống AutoCAD – vẫn cần chạy KTPROBE trên VinaCAD thật để xác nhận.
