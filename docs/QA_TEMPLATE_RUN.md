# QA chạy thật trên bản vẽ mẫu công ty (Template.dxf)

Bộ KT (`lisp/*.lsp`) chạy **thật** trên bản vẽ mẫu công ty (DXF 27 MB, AC1024, ANSI_1252, 7 674 đối
tượng Model, 3 151 block, 85 000 đối tượng trong block) bằng trình giả lập `tools/lispsim` + bộ nạp
DXF mới `tools/lispsim/dxfload.py`. Mỗi mã lỗi được lấy mẫu, đối chiếu dữ liệu thật trong DXF (ezdxf) và
phán: **ĐÚNG** (template có lỗi thật) / **BÁO NHẦM** (lỗi logic lisp) / **CRASH**.

> Người sửa lisp (Dev E) đọc mục 3 "Báo nhầm còn mở". QA KHÔNG sửa `lisp/*.lsp`.
> File này được cập nhật mỗi lần chạy lại (mục "Lịch sử chạy").

```bash
# chạy 1 lệnh / xem thống kê + mẫu lỗi (handle để tra trong DXF)
python3 -I tools/run_dxf.py Template.dxf                                  # file chuẩn lisp/KT_ChuanCongTy.txt (nếu có, không thì KTMAU)
python3 -I tools/run_dxf.py Template.dxf --mode vinacad --samples 5 --json out.json
python3 -I tools/run_dxf.py Template.dxf --cmds KTALL,KTN,KTBC
# hồi quy (skip nếu không có DXF – DXF không nằm trong repo)
KT_TEMPLATE_DXF=/duong/dan/Template.dxf python3 -m unittest tests/test_template.py -v    # ~2 phút
```

---

## 1. Kết quả lần chạy mới nhất

**Lần chạy #4 – 2026-11-15 17:50** – lisp: `KT_Core 17:41 (679fcc)`, `KT_Dim 17:41 (9b8c6b)`,
`KT_Template 17:41 (586347)`, `KT_Sheet 17:41 (069764)`, `KT_Match 17:24`, `KT_Text 17:25`, `KT_Layer 15:38`,
`KT_Clean 10:40`; file chuẩn **chọn lọc** `lisp/KT_ChuanCongTy.txt 17:21 (159d5d)` của Dev E.

| Lệnh | Thời gian | Số lần gọi hàm defun | Lỗi nội bộ (crash / lỗi bị nuốt) |
|---|---:|---:|---|
| KTMAU (AutoCAD, Enter = tự đoán) | 9.3 s | 487 414 | 0 – khung KHUNGTEENA (+KHUNGDIENNUOC, KHUNGT43), 61 DANHMUC, LAYOUT Layout1/Layout2 |
| KTMAU (VinaCAD) | 10.4 s | 510 709 | 0 – **giống hệt AutoCAD** (B-T3 đã sửa) |
| KTALL (AutoCAD) | 34.2 s | 1 739 724 | 0, không sửa/xóa đối tượng gốc |
| KTALL (VinaCAD, không ActiveX) | 42.8 s | 2 030 043 | 0, kết quả **giống hệt** AutoCAD (814 lỗi) |
| KTN, KTN, KTP, KTBC, KTX | < 1.5 s | | 0 – KTN/KTP xoay vòng `Loi i/814`, CSV 814 dòng |

Nạp DXF: 4–5 s (91 841 đối tượng CSDL).

### KTALL theo module / mã / mức (file chuẩn chọn lọc) và phán định

| Module | Mã | Mức | AutoCAD | VinaCAD | Phán định (mẫu đã soi) |
|---|---|---|---:|---:|---|
| DIM | DIM-CHU | CANHBAO | 23 | 23 | ĐÚNG – vd 163208 "20" / 1631FB "200" (h 60, cách tâm 110, chữ Arial rộng 105/157) chồng nhau thật |
| DIM | DIM-CHUDIM | CANHBAO | 18 | 18 | ĐÚNG – vd chữ đứng "1300" của 14D74C cắt đường dim y=-705145 của 14D73F |
| DIM | DIM-GHIDE | LOI | 12 | 12 | ĐÚNG – 152183 chữ `\A1;141` nhưng số đo (mã 42, đã nhân DIMLFAC) = 143; 132A53 ghi "25", đo 49 349.9 |
| DIM | DIM-LE | CANHBAO | 129 | 129 | ĐÚNG – kích thước lẻ (6199.574, 99.935…) do bắt điểm sai |
| DIM | DIM-LFAC | CANHBAO | 39 | 39 | ĐÚNG – style lạ JFP_DG 1-20 override DIMLFAC 0.5/0.2 (chi tiết phóng to) |
| DIM | DIM-LFAC | LOI | 2 | 2 | ĐÚNG – 132A53/132D27 DIMLFAC=100 (style xref bind) |
| DIM | DIM-STYLE | LOI | 3 | 3 | ĐÚNG theo chuẩn chọn lọc (D60, JFP_DG 1- 20, Xr…$0$Standard_m là style "rác") |
| DIM | DIM-TYLE | CANHBAO | 112 | 112 | ĐÚNG (gần chuẩn) – vd style 1/30 dùng trong khung 1/35, override DIMTXT 125 ở 1/100 |
| DIM | DIM-TYLE | LOI | 2 | 2 | ĐÚNG – 2 dim style xref DIMTXT 2 ở 1/100 |
| KHOP | KHOP-CAODO-MB | GOIY | 5 | 5 | ĐÚNG (gợi ý) – cao độ mặt bằng không có trên mặt cắt/mặt đứng |
| KHUNG | KHUNG-DANHMUC | GOIY | 1 | 1 | ĐÚNG – template không có bảng danh mục |
| KHUNG | KHUNG-NGOAI | GOIY | 21 | 21 | ĐÚNG phần lớn (ezdxf: đối tượng nằm ngoài cả 73 khung); vài LINE layer `KCS_Plotter` (không in) cắt qua khung – xem G2 |
| KHUNG | KHUNG-THAMCHIEU | CANHBAO | 2 | 2 | ĐÚNG/cần người xác nhận – ký hiệu mặt cắt A, B (block 1444/41244) nhưng bản vẽ tên "MẶT CẮT 1-1/2-2" |
| KHUNG | KHUNG-TRUNGSO | LOI | 1 | 1 | ĐÚNG – 2 khung cùng số hiệu C/04 "CHI TIẾT CỬA" |
| KHUNG | KHUNG-TYLE | LOI | 1 | 1 | ĐÚNG – PC/01 (phối cảnh) ghi 1:75, chèn scale 0.6 × 100 = 1/60 |
| LAYER | BLOCK-LAYER | GOIY | 56 | 56 | ĐÚNG theo chuẩn chọn lọc |
| LAYER | LAYER-0 | LOI | 60 | 60 | ĐÚNG – ezdxf: 42 INSERT + 16 LWPOLYLINE + 1 LINE + 1 ARC trên layer 0 |
| LAYER | LAYER-LA | LOI | 34 | 34 | ĐÚNG theo chuẩn chọn lọc (layer copy từ file khác: FF-FURN, i_Noithat, cua…) |
| LAYER | MAU-BYOBJ | CANHBAO | 126 | 126 | ĐÚNG – màu gán trực tiếp (62=8/252/152…), linetype/lineweight gán tay |
| SACH | ANH-MAT | LOI | 2 | 2 | ĐÚNG trong môi trường QA – ảnh logo đường dẫn tương đối `..\1. CONG VIEC\…` / không có đường dẫn |
| SACH | HATCH-KLK | GOIY | 1 | 1 | ĐÚNG – 335 hatch không liên kết |
| SACH | LAYER-RONG | GOIY | 1 | 1 | ĐÚNG – layer MANH8 không có đối tượng nào |
| SACH | LINE-TRUNG | CANHBAO | 13 | 13 | ĐÚNG – ezdxf: 13 cặp LINE trùng khít (cùng/ngược chiều) |
| SACH | PLINE-0 | GOIY | 3 | 3 | ĐÚNG – EDDB6, EE289 2 đỉnh trùng; 14F08E dài 3e-5 |
| SACH | Z-KHAC0 | CANHBAO | 5 | 5 | **2 ĐÚNG** (Z=-0.096) / **3 BÁO NHẦM** (Z=0.00075, 0.00048, -1.3e-6 hiện "Z = 0", "Z = -0") – B-T4 |
| TEXT | TEXT-CAO | CANHBAO | 36 | 36 | ĐÚNG theo chuẩn (chữ 2.32/5/2.12 mm giấy ngoài CAO_CHU_GIAY) |
| TEXT | TEXT-CAO | GOIY | 82 | 82 | ĐÚNG (gợi ý "hợp TL 1/xx") – chữ chi tiết trong khung tỷ lệ khác |
| TEXT | TEXT-FONTMAT | CANHBAO | 1 | 1 | phụ thuộc máy – `uv-abc.shx` không có trong thư mục font giả lập |
| TEXT | TEXT-STYLE | LOI | 7 | 7 | ĐÚNG theo chuẩn chọn lọc (ACA-AVH, TEXT, CA.JSC1, Xr…$0$…) |
| TEXT | TEXT-WIDTH | GOIY | 16 | 16 | ĐÚNG – style 0_T_Arial width 0.8 ≠ chuẩn 1 |
| | | **Tổng** | **814** | **814** | LOI 124 / CANHBAO 504 / GOIY 186 |

Không có CRASH. Báo nhầm còn trong KTALL: **3 mục Z-KHAC0** (B-T4). KTMAU còn B-T2 (chỉ ảnh hưởng khi
dùng file KTMAU sinh thay cho file chọn lọc).

Lưu ý ngữ nghĩa mã 42 của DIMENSION: AutoCAD lưu số đo **đã nhân DIMLFAC** (template: 152183 hình học 286,
DIMLFAC 0.5, mã 42 = 143; 132A53 hình học 493.5, DIMLFAC 100, mã 42 = 49 349.9). Lisp đã dùng đúng (Dev E);
builder `Drawing.dim_linear` của lispsim cũng đã sửa theo (trước ghi số đo hình học).

---

## 2. Lỗi THẬT của template (nên sửa trong bản vẽ mẫu)
1. 60 đối tượng vẽ trên layer `0` trong Model (42 block, 16 polyline…).
2. ~126 đối tượng gán màu/linetype/lineweight trực tiếp (không ByLayer); 157 HATCH màu 8 (được bỏ qua bằng `MAU_BYOBJ_BO_QUA|HATCH`).
3. Số hiệu **C/04** dùng cho 2 khung "CHI TIẾT CỬA" (handle EC5DC, 1030E1).
4. PC/01 ghi tỷ lệ 1:75 nhưng khung chèn scale 0.6 (1/60).
5. Dim ghi đè sai: 10 dim JFP (vd 152183) ghi `141`/`171` trong khi DIMLFAC 0.5 cho 71.5/86.5; 2 dim xref (132A53, 132D27) ghi "25", đo 49–47 m, DIMLFAC 100.
6. 129 dim đo lẻ (bắt điểm lệch 0.06–0.5 mm), 13 cặp LINE trùng, 3 polyline dài 0, Z ≠ 0 (2 block nội thất Z=-0.096).
7. "Rác" từ file khác: 34 layer, 3 dimstyle, 7 textstyle không thuộc họ công ty (JFP, VTD, YLD, xref bind `Xr QC chong tham$0$…`), ảnh logo mất đường dẫn, layer rỗng MANH8.
8. 23 cặp chữ dim chồng nhau + 18 chữ dim đè đường dim (dim liên tục 20/50 mm ở TL 1/30).

---

## 3. Báo nhầm / bug lisp CÒN MỞ (cho Dev E)

### B-T1 – KTMAU ghi `LAYOUT|` rỗng (3 dòng) – TRUNG BÌNH – **ĐÃ SỬA (#4)**
- `lisp/KT_Template.lsp`, `ktmau:layouts`: `(kt:dxf 1 ed)` lấy **mã 1 đầu tiên** của LAYOUT = tên page setup
  thuộc subclass `AcDbPlotSettings` (thường ""), không phải tên layout (mã 1 sau `(100 . "AcDbLayout")`).
  AutoCAD thật cũng trả thứ tự này. Hệ quả: `LAYOUT|` ×3, kể cả Model (tên "" ≠ "MODEL" nên không bị loại).
- Sửa: `(setq ed (member '(100 . "AcDbLayout") ed))` trước khi lấy 1 và 71 (hoặc dùng `layoutlist`
  + tab order); loại tên "" . Test: `T1_KTMAU.test_layout_names_not_empty` (đang expectedFailure).

### B-T2 – KTMAU bỏ dimstyle của xref đã bind – THẤP
- `lisp/KT_Template.lsp`, `ktmau:sec-dimstyle`: `(not (vl-string-search "$" nm))` nhằm bỏ style con
  `ISO-25$0` nhưng bỏ luôn `Xr QC chong tham$0$Standard_m` (đang dùng) trong khi layer/textstyle
  `Xr…$0$…` vẫn được lấy → chạy KTALL với file KTMAU sinh báo DIM-STYLE LOI cho chính template.
- Sửa: chỉ bỏ style con: `(wcmatch nm "*`$#")` (tên kết thúc `$` + 1 chữ số).

### B-T3 – VinaCAD: hộp bao dự phòng sai với WIPEOUT/IMAGE/HATCH/ELLIPSE → KTMAU đoán sai khung – CAO – **ĐÃ SỬA (#4)**
- `lisp/KT_Core.lsp`, `kt:ent-pts` nhánh `T`: lấy mọi mã 10–15 làm điểm. Với WIPEOUT/IMAGE mã 11/12 là
  **vector pixel** (template: 11 = (2 325 289, 0)), 13 là kích thước pixel, 14 là đỉnh clip (toạ độ pixel);
  HATCH mã 10 đầu là điểm cao độ (0,0,z) + 10 sau mã 98 là điểm seed; ELLIPSE 11 là vector trục.
- Hệ quả trên template (chế độ VinaCAD): `kt:blk-ext "GHICHUCHITIET"` = 2.3 triệu → KTMAU tự đoán khung tên
  là **GHICHUCHITIET** (3 bản) thay vì KHUNGTEENA (73 bản); file chuẩn sinh ra có CAO_CHU_GIAY
  `75,125,…,1500` (đơn vị model), DANHMUC 3 dòng sai, KHUNGTEENA bị xếp là BLOCK KHAC.
  (KTALL VinaCAD với file chuẩn chọn lọc hiện cho kết quả giống AutoCAD.)
- Sửa: trong `kt:ent-pts` thêm nhánh: `IMAGE`/`WIPEOUT` → 4 góc `p10 + u*i*w + v*j*h` (u=11, v=12, (w h)=13);
  `HATCH` → chỉ đỉnh biên (bỏ 10 đầu, dừng ở mã 98) hoặc bỏ qua HATCH; `ELLIPSE` → tâm ± |vector 11|;
  nhánh `T` chỉ dùng mã 10/11 cho LINE-like, không dùng 12–15. Test: `test_vinacad_guess_frame` (expectedFailure).

### B-T4 – Z-KHAC0 báo "Z = 0" / "Z = -0" – THẤP (3 báo nhầm / 5)
- `lisp/KT_Clean.lsp` (dòng ~190): ngưỡng `(> (abs zmax) 1e-6)`; template có INSERT Z = 0.00075, 0.00048,
  -1.27e-6 (sai số số học, không thấy được) → thông báo in "Z = 0", "Z = -0" gây khó hiểu.
- Sửa: ngưỡng ≥ 0.001 (hoặc `DUNG_SAI_KICH_THUOC` × 0.01), in bằng `(rtos z 2 4)`. Test `test_z_noise`.

### G – Góp ý (không phải lỗi)
- G1 KTN in `[LOI] LAYER-LAYER-LA` (module + mã đã có tiền tố module) – `KT_Core.lsp` `kt:goto`, nên in mã một lần.
- G2 KHUNG-NGOAI: nên bỏ qua layer không in (plot = 0, vd `KCS_Plotter`) và xét hộp bao thay vì điểm 10 cho LINE dài cắt qua khung.
- G3 LAYER-TT (khi dùng file KTMAU sinh): layer TrueColor (FF-Plants, `\U+68112`) luôn bị báo "mau 86 (TrueColor) (chuan 86)"
  vì file chuẩn không lưu TrueColor → template tự báo lỗi chính nó. Nên: KTMAU ghi thêm cờ TC, hoặc KTLAYER chỉ báo TC khi chuẩn ghi rõ ACI.
- G4 `ktdim:textquad` cần mã 42/43 của MTEXT; AutoCAD luôn có, nhưng DXF lưu từ phần mềm khác có thể thiếu → `h = 0`,
  dung sai 1e-6 → dim liên tục chung điểm (lệch 0.002) bị báo DIM-DUONG. Nên dự phòng `h = (cdr (assoc 40 ed))`.

### Đã sửa (giữ test hồi quy trong `tests/test_template.py`)
| # | Mô tả | Trạng thái |
|---|---|---|
| F1 | DIM-TYLE 300 lỗi "Dim TL 1/1 nằm trong khung TL 1/100" – style DIMSCALE 0 (tỷ lệ "nướng" vào DIMTXT 150) + override DIMSCALE 1 | Dev E đổi DIM-TYLE sang chiều cao chữ giấy – **đã hết** (`test_dimscale0_style_not_tyle_1_1`) |
| F2 | KHOP-CAODO-VITRI 10 LOI "lệch 93.6mm": COTCAODO lật 180° (scale X âm) – vạch cao độ ở y=-49.03 trong block, không ở điểm chèn | Dev E thêm điểm tham chiếu block (`BLOCK|COTCAODO|CAODO|COTE||-88.25,-49.03`, KTMAU tự dò) – **đã hết** |
| F3 | KTMAU tự đoán khung (AutoCAD) | đúng KHUNGTEENA, tỷ lệ gốc 100, 61 dòng DANHMUC |
| F4 | B-T1 LAYOUT rỗng | #4: `LAYOUT|Layout1`, `LAYOUT|Layout2` (`test_layout_names_not_empty`) |
| F5 | B-T3 VinaCAD đoán sai khung | #4: KTMAU VinaCAD = AutoCAD (`test_vinacad_guess_frame`) |
| F6 | DIM-GHIDE/DIM-LFAC nhân DIMLFAC 2 lần ("Ghi 141 nhung do 72", "do 49349 hien 4934987") | #4: "Ghi 141 nhung do 143", "do 493.499 hien 49349.880" |

---

## 4. Bộ nạp DXF `tools/lispsim/dxfload.py`

Đọc **tag thô** DXF theo đúng thứ tự file (không qua đối tượng ezdxf), giữ mã nhóm gốc:
- Mọi thực thể Model + layout (thực thể của layout không active trong block `*Paper_SpaceN` được đưa vào
  CSDL chính, `410` = tên layout), `entnext`/`ssget "_X"` theo thứ tự file.
- entget như AutoCAD: `(-1)(0)(330 owner)(5 handle)(100 "AcDbEntity")(67)(410)(8)…`; có nhóm 102
  (`{ACAD_REACTORS`/`{ACAD_XDICTIONARY`) thì 5 đứng trước như AutoCAD; mã 330/340/350/360/390/480 → ename;
  5/105/320–329/1005 giữ chuỗi handle; **góc 50–58 đổi độ → radian**; bổ sung giá trị mặc định entget luôn có
  (TEXT 50/41/51/7/71/72/11/73, INSERT 41/42/43/50/70/71/44/45, 210…). MTEXT thiếu 42/43 → ước lượng.
- Bảng VPORT/LTYPE/LAYER/STYLE/VIEW/UCS/APPID/DIMSTYLE/BLOCK_RECORD (`tblsearch/tblnext/tblobjname`),
  định nghĩa block BLOCK…ENDBLK (entnext đi qua cả ATTRIB/SEQEND của INSERT lồng), INSERT + ATTRIB + SEQEND,
  POLYLINE + VERTEX + SEQEND, DIMENSION + block `*D`, XDATA (`-3`, mọi app: ACAD DSTYLE, AcadAnnotative,
  AcDbBlockRepBTag → `vla-get-EffectiveName` cho `*U`), DICTIONARY (namedobjdict, ACAD_LAYOUT, ACAD_IMAGE_DICT…).
- **Chuỗi**: AutoLISP ANSI thấy ký tự ngoài codepage dạng `\U+XXXX` ("TRỤC" → `TR\U+1EE4C`), ký tự cp1252 giữ
  nguyên 1 byte (lưu dạng latin-1 để `ascii`/file ghi đúng byte). `load_dxf(path, unicode=True)` = AutoCAD 2021+.
- Header → `getvar` (EXTMIN/EXTMAX/DIMSCALE/LTSCALE/INSUNITS/TEXTSIZE/CLAYER…).

Sửa thêm trong lispsim (hình học `vla-GetBoundingBox` giả lập, `drawing.py`): ARC đúng cung, ELLIPSE theo
tham số, HATCH theo biên (bỏ điểm cao độ & seed), IMAGE/WIPEOUT theo đường clip, OCS (210 = 0 0 -1 → lật X),
chữ căn lề neo theo điểm 11, đếm `\U+XXXX`/`%%c` là 1 ký tự. So với ezdxf trên 7 674 đối tượng Model: lệch
> 20 % chỉ còn ở DIMENSION/INSERT chứa chữ (ước lượng bề rộng chữ).

**Giới hạn đã biết**: không đọc DXF nhị phân; bề rộng chữ ước lượng 0.75·h·số ký tự (không có font thật);
`tblsearch` không sinh các mã suy diễn kiểu R12 (5/6/7 tên block mũi tên của DIMSTYLE); LWPOLYLINE không bổ
sung 40/41/42/91 từng đỉnh nếu DXF bỏ; thứ tự `ssget "_X"` = thứ tự file DXF; ảnh/xref/font tìm trong hệ
file ảo (không có file thật → ANH-MAT/TEXT-FONTMAT phụ thuộc môi trường).

## 5. Hiệu năng
- KTALL trên template: 35–44 s trong lispsim (1.7–2.1 triệu lần gọi hàm defun; nhiều nhất `kt:dxf` ~460 k,
  `kt:inbox` ~240 k). Tăng tuyến tính, không có điểm treo.
- Tối ưu interpreter (`interp.py`: `ev` dùng `type()` + gọi Subr trực tiếp, `isnum` nhanh; `cad.py`: cache
  danh sách bảng cho `tblnext` – trước đó mỗi `tblnext "BLOCK"` dựng lại list 3 151 block, 12 794 lần gọi):
  KTALL 38.8 s → 35.4 s; `entnext` O(1) theo chỉ số (trước O(n)).

---

## Lịch sử chạy
| # | Giờ | lisp / chuẩn | KTALL AutoCAD | Ghi chú |
|---|---|---|---|---|
| 1 | 17:00 | lisp commit 1866f0b+, chuẩn = KTMAU sinh | 31 s, 1 154 lỗi (LOI 126) | DIM-TYLE 300 báo nhầm (F1), KHOP-CAODO-VITRI 10 (F2), DIM-DUONG 14 (do lispsim thiếu MTEXT 42/43 – đã sửa trong bộ nạp) |
| 2 | 17:20 | KT_Dim mới, chuẩn = KTMAU sinh | 36 s, 934 lỗi | F1 còn 74 → Dev E đang sửa |
| 3 | 17:40 | lisp 17:35, chuẩn chọn lọc 17:21 | 37.7 s, 814 lỗi (LOI 124) | F1, F2 đã hết; còn B-T1..B-T4 |
| 4 | 17:50 | xem mục 1 | 34.2 s, 814 lỗi (LOI 124) | B-T1, B-T3, nhân DIMLFAC 2 lần đã sửa; còn B-T2, B-T4 |
