# RESEARCH – Bộ AutoLISP kiểm tra hồ sơ KTTC kiến trúc (AutoCAD + VinaCAD)

> Người soạn: nhóm nghiên cứu phương án. Ngày: 2026-11-14.
> Ký hiệu độ tin cậy: **[XN]** = đã xác nhận từ nguồn; **[SL]** = suy luận/kinh nghiệm, PHẢI kiểm bằng lệnh thăm dò `KTPROBE` (mục 1.4) trên máy có VinaCAD.

---

## 1. Tương thích VinaCAD vs AutoCAD

### 1.1 VinaCAD là gì / nền tảng
- VinaCAD: phần mềm CAD "made in Vietnam" (hệ sinh thái Standard/Pro/Enterprise/Web/Mobile/SDK). FAQ chính thức ghi phát triển bởi skyACE Group; app Android ghi Prima Solutions / TGL Solutions. **[XN]**
- FAQ tuyên bố "tương thích cao với AutoCAD, BricsCAD, IJCAD", đọc/ghi DWG, DXF, DGN; app mobile mở DWG/DXF/IFC/STEP. **[XN]**
- Có hỗ trợ LISP: tiện ích **VinaLisp** (ribbon gom lisp phổ biến) và nạp .lsp riêng bằng lệnh **APLOAD/APPLOAD**. **[XN]**
- **Lõi bên dưới (IntelliCAD/ODA/GstarCAD/…) KHÔNG tìm được nguồn công bố.** Việc đọc DWG+DGN+IFC+STEP gợi ý dùng **ODA SDK** (Drawings/IFC SDK) – giống IntelliCAD, BricsCAD, GstarCAD/IJCAD, ZWCAD… đều là "DWG clone". **[SL]**
- Hệ quả thực tế: phải coi VinaCAD như một "CAD clone" bất kỳ → **AutoLISP lõi (entget/entmake/ssget/tbl*) gần như chắc chạy; Visual LISP (vl-/vla-/vlax-/vlr-) KHÔNG được giả định**. Diễn đàn IntelliCAD cũng khuyên: code không dùng vl-/vla-/vlax- thì chạy được, một số ít hàm lõi chỉ hỗ trợ một phần. **[XN cho IntelliCAD, SL cho VinaCAD]**
- Không truy cập được vina-cad.com / bimcad-vietnam.com từ máy chủ nghiên cứu (mạng chặn) → cần người dùng thử trực tiếp.

### 1.2 Bảng mức rủi ro hàm (dùng chung AutoCAD 2018+ và VinaCAD)

| Nhóm | Hàm | Mức | Ghi chú / thay thế |
|---|---|---|---|
| Lõi DXF | entget, entnext, entlast, entmod, entmake, entdel, entupd, handent, ssget (kể cả "_X" + filter), ssname, sslength, ssadd, tblsearch, tblnext, tblobjname, namedobjdict, dictsearch, dictnext, getvar/setvar, findfile, layoutlist | **An toàn** | Xương sống của bộ tool. `entmake` LAYER/TEXT/CIRCLE/LWPOLYLINE như CDO là OK. |
| Lõi khác | textbox, rtos, distof, angtos, polar, inters, trans, osnap, getpoint/getreal/initget, strcase, vl-string-* cơ bản | An toàn/[SL] | `textbox` chỉ cho TEXT; MTEXT dùng DXF 42/43. `trans` OK. |
| vl-* thuần LISP | vl-load-com, vl-remove-if(-not), vl-position, vl-string-search, vl-string-subst, vl-string-trim, vl-princ-to-string, vl-prin1-to-string, vl-list*, vl-member-if | Thấp–TB [SL] | Clone phổ biến (BricsCAD/ZWCAD/GstarCAD) đều có. Vẫn bọc kiểm tra tồn tại ở `kt:init`. |
| Bắt lỗi | vl-catch-all-apply, vl-catch-all-error-p | TB [SL] | Bọc qua `kt:try` – nếu không có thì gọi thẳng + `*error*` cục bộ. |
| Sắp xếp | vl-sort, vl-sort-i | TB | Ngoài rủi ro tồn tại, **vl-sort xoá phần tử trùng khi sort số/chuỗi** (hành vi AutoCAD). Tự viết `kt:sort` (merge sort) – an toàn và đúng. |
| File | open/close/read-line/write-line, vl-file-delete, vl-file-size, vl-directory-files, vl-filename-base/directory | TB [SL] | Dùng open/write-line làm chuẩn; vl-file-* chỉ là tiện ích có fallback. |
| ActiveX | vlax-get-acad-object, vla-get-ActiveDocument, vla-StartUndoMark, vlax-ename->vla-object, vla-get-EffectiveName, vla-get-Measurement, vla-ZoomCenter/Window, vlax-3d-point, vlax-get/put-property | **Cao** | Chỉ dùng có fallback. Zoom → `(command "_.ZOOM" "_W" p1 p2)`; Undo → `(command "_.UNDO" "_BE")`/`"_E"`; Measurement → DXF 42 của DIMENSION. |
| Curve | vlax-curve-getArea/getDistAtParam/getClosestPointTo… | **Cao** | Tự tính từ DXF: LINE, LWPOLYLINE (có bulge), ARC, CIRCLE. Không cần SPLINE cho KTTC. |
| Reactor | vlr-* | **Cấm** | Không cần cho bộ kiểm tra. |
| Chọn | sssetfirst | TB [SL] | Thường có; nếu lỗi bỏ qua (chỉ là tiện ích hiển thị). Cần PICKFIRST=1. |
| Mới (AutoCAD 2012+) | getpropertyvalue, setpropertyvalue, dumpallproperties | **Cao** | Tên thuộc tính khác nhau giữa các CAD (BricsCAD có hậu tố ~Native). **Cấm dùng.** |
| Mới (2015+) | command-s, vl-cmdf mới | TB | Dùng `command` thường; không gọi trong `*error*` nếu có thể. |
| Express | acet-* (acet-ui-progress, acet-str-…, acet-ss-…) | **Cấm** | Không có trên clone, AutoCAD cũng có máy không cài Express. |
| Thư viện ngoài | dos_* (DOSLib), OpenDCL, .NET/ARX | **Cấm** | |
| DCL | load_dialog/new_dialog | TB [SL] | Hạn chế; giữ giao diện dòng lệnh như CDO. |
| COM ngoài | vlax-create-object "Excel.Application"/"Scripting.FileSystemObject" | **Cấm** | Không hỗ trợ ngay cả AutoCAD LT; clone không chắc. Xuất CSV/HTML bằng write-line. |

### 1.3 Tiếng Việt & file
- AutoCAD 2021+ có LISPSYS (Unicode); **AutoCAD 2018 (định dạng template) và nhiều clone vẫn là AutoLISP ANSI**: ký tự ngoài codepage trả về dạng chuỗi `\U+1EA1`. **[XN cơ chế AutoCAD, SL cho VinaCAD]**
- Tên file/thư mục có dấu ("Nhà Chị Hạnh (Gia Lộc).dwg") có thể làm `findfile/open` hỏng → **file tool, config, báo cáo luôn tên ASCII**; không ghép DWGNAME có dấu vào đường dẫn, dùng `kt:ascii` để bỏ dấu/thay `_`. Lisp mẫu trên mạng VN cũng khuyên tránh dấu trong đường dẫn nạp lisp. **[XN]**
- Báo cáo:
  - **TXT/CSV**: chỉ ASCII (tiếng Việt không dấu); với chuỗi lấy từ bản vẽ, chuyển `\U+XXXX` → chữ không dấu bằng bảng tra (`kt:unaccent`). Dấu phân cách `;` (Excel VN dùng dấu phẩy thập phân) hoặc `,` + bọc nháy kép.
  - **HTML**: đổi `\U+XXXX` → `&#xXXXX;` → file thuần ASCII nhưng **hiển thị đúng tiếng Việt có dấu** ở mọi trình duyệt, không phụ thuộc encoding của `write-line`. Khai báo `<meta charset="us-ascii">` hoặc utf-8 (ASCII là tập con). Đây là định dạng báo cáo khuyến nghị.
  - Ký tự 0x80–0xFF (Latin/CP1258) cũng escape `&#NNN;` theo codepage hiện tại – hoặc đơn giản thay bằng `?` và log.
- Prompt/thông báo trong CAD: **tiếng Việt không dấu** (như CDO). Không lưu file .lsp dạng UTF-8 có BOM; lưu ANSI/ASCII thuần.

### 1.4 QUY TẮC CODE TƯƠNG THÍCH (bắt buộc)
1. **Ưu tiên DXF thuần**: đọc bằng `entget`, tạo bằng `entmake`, sửa bằng `entmod`. Không dùng vla- cho dữ liệu nếu DXF lấy được.
2. **Feature-detect một lần** ở `kt:init`: `(setq *KT:VLA* (and (= (type vl-load-com) 'SUBR) (not (vl-catch-all-error-p (vl-catch-all-apply 'vlax-get-acad-object nil)))))` – viết an toàn: kiểm `(type sym)` ∈ `'(SUBR EXRXSUBR USUBR)` trước khi gọi. Lưu cờ `*KT:VLA* *KT:CATCH* *KT:SORT* *KT:SSF*`.
3. **Mọi hàm rủi ro đi qua wrapper** trong core: `kt:try`, `kt:zoom-win`, `kt:zoom-center`, `kt:undo-begin/end`, `kt:sort`, `kt:select` (sssetfirst), `kt:effname`, `kt:file-exists`. Module KHÔNG gọi vla-/vlax- trực tiếp.
4. Zoom fallback: `(command "_.ZOOM" "_C" pt h)` / `"_W"`; tạm tắt CMDECHO; dùng tiền tố `_.` để chạy trên bản không tiếng Anh.
5. Undo: `(command "_.UNDO" "_BE")`…`"_E"` (chạy cả AutoCAD lẫn clone), không phụ thuộc vla-StartUndoMark.
6. **Cấm**: acet-*, dos_*, getpropertyvalue/setpropertyvalue, vlr-*, vlax-create-object, command-s, DCL phức tạp, OpenDCL.
7. Tự viết: sort (merge sort), split chuỗi, trim, join, so sánh số có dung sai, độ dài/diện tích LWPOLYLINE (bulge), giao đoạn thẳng, AABB.
8. Khi dùng ssget "_X" luôn lọc theo 410 (layout) khi cần; với nội dung trong block dùng duyệt `tblobjname "BLOCK"` + entnext (như `cdo:dimtext`).
9. Đối tượng tạo ra (đánh dấu) chỉ: LAYER, CIRCLE, LWPOLYLINE, TEXT (không MTEXT phức tạp, không MLEADER) → entmake chắc chạy.
10. Biến toàn cục `*KT:...*`, hàm `kt:...`, lệnh `c:KT...`; mọi biến cục bộ khai sau `/`. Không đè hàm hệ thống.
11. Tên file ASCII, đường dẫn lấy từ `(findfile "kt-core.lsp")` → thư mục tool; config + báo cáo đặt cạnh DWG (`DWGPREFIX`) với tên ASCII.
12. Không phụ thuộc biến hệ thống mới (LISPSYS, VTENABLE…): đọc bằng `(getvar)` trong `kt:try`, nil thì bỏ qua.
13. Lệnh thăm dò **`KTPROBE`**: in `(ver)`, `ACADVER`, `PRODUCT`, `PLATFORM`, danh sách hàm thiếu (duyệt list symbol rủi ro, `(type s)`), thử ghi file `\U+1EA1` → gửi kết quả cho dev. Chạy đầu tiên trên mỗi máy VinaCAD.
14. Nạp: 1 file `kt-load.lsp` gọi `(load ...)` các module theo thứ tự; không compile .fas/.vlx (clone có thể không đọc được) – phát hành **.lsp nguồn**.

---

## 2. Danh mục hạng mục kiểm tra (Khả thi tự động: C=Cao, TB, T=Thấp)

### A. Layer / thuộc tính đối tượng
| # | Hạng mục | KT | Thuật toán gợi ý |
|---|---|---|---|
| A1 | Layer không có trong chuẩn | C | tblnext LAYER, so tên (strcase) với danh sách cfg; bỏ qua layer xref (`|`) và layer kiểm tra. |
| A2 | Layer sai màu/linetype/lineweight/plot so chuẩn | C | So DXF 62/6/370/290 của LAYER với cfg. |
| A3 | Đối tượng nằm layer 0 / Defpoints (ngoài block def) | C | ssget "_X" '((8 . "0")), loại VIEWPORT; Defpoints chỉ cho phép DIM/VIEWPORT. |
| A4 | Màu/linetype/LW gán ByObject | C | Đối tượng có DXF 62 ≠ 256 (và ≠0 trong block), 6 ≠ "BYLAYER", 370 ≠ -1. Cho phép danh sách ngoại lệ (hatch màu nền…) trong cfg. |
| A5 | Đối tượng trong block def không ở layer 0/ByBlock (block "bẩn") | TB | Duyệt BLOCK def, đếm entity layer ≠ "0". Chỉ cảnh báo. |
| A6 | Layer rỗng, layer tắt/đóng băng chứa nội dung cần in | TB | Đếm đối tượng mỗi layer; layer off/freeze (62<0, 70&1) có đối tượng → cảnh báo. |
| A7 | Đối tượng Z≠0 / elevation | C | LINE 10/11 z, LWPOLYLINE 38, INSERT/TEXT 10 z, 210≠(0 0 1) (lật mirror 3D). |
| A8 | Linetype không hiện (LTSCALE/PSLTSCALE/CELTSCALE sai) | TB | So getvar với cfg; đối tượng có DXF 48 ≠ 1. |

### B. Kích thước (DIM)
| # | Hạng mục | KT | Thuật toán |
|---|---|---|---|
| B1 | Dimstyle không thuộc chuẩn | C | DXF 3 của DIMENSION ∉ cfg; tblnext DIMSTYLE thừa. |
| B2 | Dimstyle chuẩn nhưng bị sửa tham số | C | So DXF DIMSTYLE (40 DIMSCALE, 144 DIMLFAC, 140 DIMTXT, 41 DIMASZ, 340 textstyle, 271 DIMDEC…) với cfg trích từ template. |
| B3 | Override cục bộ trên dim | C | `(entget en '("ACAD"))` → xdata "DSTYLE" có cặp mã → liệt kê. |
| B4 | DIMSCALE/DIMLFAC sai so tỷ lệ | C | Dim ở model: DIMSCALE phải = mẫu số tỷ lệ của viewport chứa nó (xem D3); dim ở paper: DIMSCALE=1 và DIMLFAC = 1/scale VP (nếu đo xuyên VP) – quy tắc lấy từ cfg. |
| B5 | Text override (ghi đè số) | C | DXF 1 ≠ "" và không chứa "<>" → lỗi đỏ; có "<>" + tiền/hậu tố → cảnh báo nhẹ. So thêm: nếu chuỗi là số, so với DXF 42 → "ghi đè sai giá trị". |
| B6 | Dim lệch giá trị đo (đo lệch lẻ) | C | DXF 42 (measurement) × DIMLFAC; giá trị không tròn theo bước cfg (vd 5mm) → nghi vẽ sai/bắt điểm trượt. |
| B7 | Dim không liên kết (non-associative) | TB | Có `(102 . "{ACAD_REACTORS")` trỏ tới ACAD_DIMASSOC? Xét xdict 360. Clone có thể không tạo DIMASSOC → chỉ báo thông tin, có cờ tắt. |
| B8 | Dim chồng lấn / trùng | C | Đã có CDO – đưa vào làm module. |
| B9 | Dim bị explode (LINE+TEXT rời trên layer dim) | TB | TEXT số trên layer dim nhưng không phải DIMENSION; cặp LINE+SOLID/arrow gần. |
| B10 | Chuỗi kích thước không khép (tổng chi tiết ≠ kích thước tổng) | TB | Gom dim cùng phương, cùng đường dim song song lệch nhỏ; chuỗi nối tiếp (14 của dim i = 13 dim i+1) tổng phải = dim bao ngoài cùng phạm vi. |

### C. Chữ
| # | Hạng mục | KT | Thuật toán |
|---|---|---|---|
| C1 | Textstyle không chuẩn / font sai/thiếu | C | tblnext STYLE: tên ∉ cfg, DXF 3/4 font khác cfg; `findfile` font .shx/.ttf (Fonts folder) – thiếu → cảnh báo. |
| C2 | Chiều cao chữ sai theo tỷ lệ | C | Model: h_TEXT(40)/scale VP ∈ {2.0,2.5,3.5,5,7}±dung sai (cfg). Paper: h ∈ danh sách. MTEXT: 40 và mã `\H` trong chuỗi (nghi ngờ). |
| C3 | Width factor/oblique khác chuẩn | C | DXF 41/51. |
| C4 | Chữ dùng font không gõ được TV (VNI/TCVN3 lẫn Unicode) | TB | Font name chứa ".VnTime"/"VNI-" → cảnh báo trộn bảng mã. |
| C5 | Lỗi chính tả / thuật ngữ | T | Chỉ bắt danh sách từ sai phổ biến trong cfg. |

### D. Khung tên & layout & danh mục
| # | Hạng mục | KT | Thuật toán |
|---|---|---|---|
| D1 | Thiếu khung tên trên layout | C | Mỗi layout (layoutlist) có INSERT khung tên (theo tên/tập tag cfg) ở 410=layout. |
| D2 | Attribute rỗng / còn giá trị mặc định template | C | Duyệt ATTRIB sau INSERT (66=1): 1 = "" hoặc = giá trị default trong cfg ("XXX", "TÊN BẢN VẼ"). |
| D3 | Tỷ lệ ghi khung tên ≠ tỷ lệ viewport | C | VIEWPORT (≠ VP id 1): scale = DXF41/DXF45; so attrib TỶ LỆ "1/100", "1:50". VP nhiều tỷ lệ → liệt kê. |
| D4 | Số bản vẽ trùng / nhảy số / sai mã | C | Thu attrib SỐ BV mọi layout; tách tiền tố (KT-) + số; sort, tìm trùng & khoảng trống; regex đơn giản theo mẫu cfg. |
| D5 | Tên bản vẽ trùng | C | Chuẩn hoá (strcase, bỏ khoảng trắng) → đếm. |
| D6 | Tên layout ≠ số bản vẽ trong khung | C | So `CTAB` name với attrib. |
| D7 | Thiếu bản vẽ so danh mục template / danh mục bản vẽ trong file ≠ thực tế | TB | Đọc bảng danh mục (TEXT/attrib trong block DANH MỤC hoặc TABLE: entget ACAD_TABLE nhóm 1 phức tạp → TB) so với list layout. Danh mục bắt buộc (MB tầng, MĐ, MC, chi tiết WC, cầu thang, cửa…) đặt trong cfg. |
| D8 | Ngày, người vẽ/kiểm, phiên bản thống nhất | C | Attrib cùng tag phải giống nhau toàn bộ layout. |
| D9 | Viewport không khoá (DXF 90 bit 16384) / VP nằm layer in | C | Đọc VIEWPORT 90, 8. |

### E. Tính nhất quán liên bản vẽ (MB–MĐ–MC)
| # | Hạng mục | KT | Thuật toán |
|---|---|---|---|
| E1 | Tên trục trùng/thiếu/thứ tự | TB | Block trục (tên cfg) + attrib; trục số theo X, chữ theo Y; sort theo toạ độ, kiểm thứ tự 1,2,3 / A,B,C, phát hiện nhảy/trùng. |
| E2 | Khoảng cách trục khớp giữa các mặt bằng | TB | Mỗi MB (vùng = VP hoặc khung ở model) → map tên trục→toạ độ; so khoảng cách liên tiếp giữa các MB (dung sai 1mm). Dim trục trên MĐ/MC so với MB. |
| E3 | Kích thước tổng MB vs MĐ/MC | TB | Lấy dim lớn nhất theo phương có 2 điểm đo trùng 2 trục biên → so. |
| E4 | Cốt cao độ (ký hiệu cốt) khớp | TB | Block cốt + attrib giá trị (±0.000, +3.600): parse số; trên MĐ/MC kiểm `ycốt` tuyến tính: (y_i − y_0)/scale×1000 ≈ giá trị (dung sai). Thu danh sách cao độ tầng từ các bản vẽ → so chéo (MB ghi cốt sàn vs MC). |
| E5 | Chiều cao tầng thống nhất | TB | Từ E4 tính hiệu cốt; so bảng tầng trong cfg/bản MC chuẩn. |
| E6 | Callout mặt cắt/chi tiết trỏ tới bản vẽ tồn tại | C | Block ký hiệu MC/chi tiết: attrib (ký hiệu "1-1", số BV "KT-05"); kiểm số BV ∈ danh sách D4; ký hiệu ∈ tiêu đề hình trên BV đích (block tiêu đề chi tiết). Hai chiều: chi tiết nào không được gọi. |
| E7 | Ký hiệu cửa (D1, S2…) khớp bảng thống kê cửa | TB | Đếm attrib tag cửa trên MB vs bảng thống kê. |
| E8 | Trùng khớp hình học MB tầng trên/dưới (cột, thang) | T | Cần nhận diện cột (hatch/block) – để giai đoạn sau. |

### F. Vệ sinh file
| # | Hạng mục | KT | Thuật toán |
|---|---|---|---|
| F1 | Xref mất/chưa resolve, đường dẫn tuyệt đối | C | tblnext BLOCK 70&4 (xref); DXF 1 path, `findfile`; 70&32 = resolved. |
| F2 | Ảnh mất | C | dictsearch namedobjdict "ACAD_IMAGE_DICT" → IMAGEDEF DXF 1 → findfile. |
| F3 | Block rác / chưa dùng (purge) | C | Tập tên INSERT (model+paper+lồng trong block def), so tblnext BLOCK (bỏ *Model/*Paper, xref, anonymous *D/*U dùng chung). Tương tự layer/style/linetype/dimstyle chưa dùng. |
| F4 | Đối tượng trùng (copy chồng) | C | Hash: type+layer+toạ độ làm tròn (LINE 2 đầu đã sắp, CIRCLE tâm+R, LWPOLYLINE list đỉnh, INSERT tên+điểm+góc+scale, TEXT điểm+chuỗi); sort + quét trùng. |
| F5 | Polyline trùng/đè một phần, đỉnh trùng, đoạn dài 0 | C | LWPOLYLINE: đỉnh liên tiếp khoảng cách < tol; LINE dài < tol. Chồng một phần: tương tự `cdo:lineover` cho cặp đoạn thẳng hàng. |
| F6 | Hatch hở / không liên kết / boundary mất | TB | HATCH DXF 71 (associative) = 0 → cảnh báo; hatch quá nhiều loop (91) hoặc diện tích/ bbox bất thường; "hở" khi vẽ thật nằm ngoài khả năng LISP (hatch đã tồn tại luôn kín) → kiểm hatch không có boundary liên kết (330 rỗng). |
| F7 | Proxy object, đối tượng lỗi, AUDIT | TB | ssget "_X" '((0 . "ACAD_PROXY_ENTITY")); gợi ý chạy AUDIT (không tự sửa). |
| F8 | Đơn vị bản vẽ (INSUNITS, LUNITS, MEASUREMENT) sai | C | getvar so cfg. |
| F9 | Đối tượng ngoài vùng làm việc (rất xa gốc) | C | ssget "_X" bbox; điểm cách cụm chính > N lần kích thước → đánh dấu. |

Ưu tiên triển khai: **A1–A4, A7, B1–B6, B8, C1–C3, D1–D6, F1–F5, F8** (đều Cao) → sau đó E6, E4, E1–E2, B10, D7.

---

## 3. Kiến trúc bộ tool

```
kiemtrabanvekientruc/
  src/kt-load.lsp        ; nạp toàn bộ, in danh sách lệnh
  src/kt-core.lsp        ; thư viện lõi (bắt buộc)
  src/kt-cfg.lsp         ; đọc/ghi file cấu hình, lệnh KTCFG (trích chuẩn)
  src/kt-mark.lsp        ; layer đánh dấu, danh sách lỗi, KTN/KTP/KTX, xuất báo cáo
  src/kt-layer.lsp       ; nhóm A
  src/kt-dim.lsp         ; nhóm B (tích hợp CDO)
  src/kt-text.lsp        ; nhóm C
  src/kt-sheet.lsp       ; nhóm D (khung tên, layout, viewport)
  src/kt-xcheck.lsp      ; nhóm E (trục, cốt, callout)
  src/kt-clean.lsp       ; nhóm F
  config/chuan-cty.ini   ; chuẩn công ty (trích từ template, sửa tay được)
```

### 3.1 kt-core.lsp (prefix `kt:`)
- `kt:init` (feature-detect, cờ `*KT:VLA*`…), `kt:try`, `kt:sort`, `kt:zoom-win`, `kt:undo-begin/end`, `kt:select`.
- Dữ liệu: `kt:dxf (code ed)`, `kt:ss->list`, `kt:tbl-list "LAYER"`, `kt:attribs (en) -> ((TAG . val)…)`, `kt:blockname (en)` (hiệu dụng: vla-get-EffectiveName nếu có; fallback: tên thường, block "*U" nhận diện bằng **tập tag attrib**), `kt:layouts`, `kt:viewports (layout) -> ((en scale center…))`, `kt:space-of (en)`.
- Hình học: vector 2D (như cdo:*), AABB, SAT, `kt:lwpts`, `kt:polylen` (bulge), `kt:eq`.
- Chuỗi: `kt:split`, `kt:join`, `kt:trim`, `kt:unaccent` (bảng \U+ → không dấu), `kt:html-esc`, `kt:csv-esc`, `kt:ascii-name`.

### 3.2 File cấu hình `chuan-cty.ini` (text, dễ sửa, ASCII)
Định dạng INI phân đoạn, mỗi dòng `key=v1|v2|…`, dòng `;` là chú thích. Đọc bằng read-line + `kt:split`. Ví dụ:
```
[META]
nguon=Nha Chi Hanh (Gia Loc).dwg ; ghi bang kt:ascii-name
ngay=2026-11-14
acadver=AC1032
[LAYER]          ; ten|mau|linetype|lineweight|plot
KT-TUONG|7|Continuous|50|1
KT-TRUC|1|CENTER|13|1
[LAYER_CAM]      ; layer khong duoc chua doi tuong
0
Defpoints
[DIMSTYLE]       ; ten|DIMSCALE|DIMLFAC|DIMTXT|DIMASZ|DIMTXSTY|DIMDEC|DIMCLRT...
KT-100|100|1|2.5|1.5|KT-CHU|0|...
[TEXTSTYLE]      ; ten|font|bigfont|height|width|oblique
KT-CHU|Arial.ttf||0|0.8|0
[TEXT_HEIGHT]    ; chieu cao chu tren giay cho phep (mm)
cho_phep=1.8|2.0|2.5|3.5|5.0|7.0
[TITLEBLOCK]
ten_block=KHUNG-A3|KHUNG-A1
tag_bat_buoc=SO_BV|TEN_BV|TY_LE|NGAY|NGUOI_VE|KIEM
tag_so_bv=SO_BV
tag_ty_le=TY_LE
mau_so_bv=KT-##
gia_tri_mac_dinh=XXX|TEN BAN VE
[BLOCK_KYHIEU]   ; vai tro=ten block|tag
truc=TRUC|TEN
cot=COT_CAO_DO|GIA_TRI
callout=KH_MATCAT|KY_HIEU;SO_BV
[SYSVAR]
INSUNITS=4
LTSCALE=1
PSLTSCALE=1
[LAYOUT]         ; danh muc ban ve mau
KT-01|MAT BANG TANG 1
[TOLERANCE]
dim_buoc=5
dim_lech=0.5
text_h=0.05
```
- **Lệnh `KTCFG`** (chạy khi đang mở template "Nhà Chị Hạnh (Gia Lộc)"): duyệt tblnext LAYER/LTYPE/STYLE/DIMSTYLE (đọc DXF đầy đủ của dimstyle qua `tblobjname`+`entget`), getvar đơn vị/LTSCALE, layoutlist + viewport scale, INSERT có attrib trên mỗi layout (block xuất hiện ở ≥ 1/2 số layout & có ≥3 attrib → đoán là khung tên, hỏi xác nhận bằng getkword), block có attrib khác (trục, cốt, callout – liệt kê để người dùng gán vai trò), giá trị attrib hiện có làm "mặc định" để phát hiện chưa sửa. Ghi file `chuan-cty.ini` (tên ASCII) vào thư mục tool; nếu đã có → ghi `chuan-cty.new.ini` để so, không đè.
- `KTCFGL` nạp lại cfg; module đọc cfg qua `kt:cfg-get "LAYER"`.
- Lưu ý template là AutoCAD 2018 (AC1032): AutoCAD 2018+ và VinaCAD (đọc DWG mới) mở được; các bản AutoCAD < 2018 KHÔNG mở được → yêu cầu tối thiểu AutoCAD 2018.

### 3.3 Lệnh (ngắn, giống CDO)
| Lệnh | Việc |
|---|---|
| KTPROBE | Thăm dò tương thích (mục 1.4.13) |
| KTCFG / KTCFGL | Trích chuẩn từ template / nạp lại cfg |
| KT | Chạy tất cả (hỏi phạm vi: layout hiện tại / tất cả) |
| KTL, KTD, KTT, KTK, KTC, KTV | Chỉ chạy nhóm Layer / Dim / Text / Khung tên / Chéo (trục-cốt-callout) / Vệ sinh |
| KTN / KTP | Zoom lỗi kế tiếp / trước |
| KTX | Xoá đánh dấu |
| KTR | Xuất báo cáo CSV + HTML |
| KTSET | Dung sai, bật/tắt nhóm kiểm tra |

---

## 4. Báo cáo kết quả

### 4.1 Cấu trúc 1 lỗi (list chung toàn bộ module)
`(ma_loi muc_do nhom layout diem bankinh (en1 en2 …) "mo ta khong dau" "gia tri thuc" "gia tri chuan")`
- `ma_loi`: A3, B5…; `muc_do`: LOI (đỏ) / CANHBAO (vàng) / THONGTIN (xanh).
- Lưu `*KT:ISSUES*` + chỉ số `*KT:IDX*` (như CDO). Lưu handle (DXF 5) thay vì ename để báo cáo/khôi phục giữa phiên.

### 4.2 Đánh dấu trong bản vẽ
- Layer riêng `KT_CHECK` (không in: DXF 290=0, màu đỏ), có thể con: `KT_CHECK-LOI`, `KT_CHECK-CANHBAO` để bật/tắt.
- Ký hiệu: CIRCLE + TEXT mã lỗi (như cdo:mark); vẽ **trong đúng không gian** của đối tượng (410 = layout của lỗi; model nếu ở model). Lỗi cấp bản vẽ (sysvar, layer thừa) → không vẽ, chỉ báo cáo.
- Chiều cao chữ đánh dấu tỉ lệ theo VIEWSIZE hoặc theo bbox đối tượng.
- `KTX` xoá bằng ssget "_X" layer KT_CHECK*. Không sửa đối tượng của nhân viên (chỉ đọc) – leader tự sửa/ trả về.

### 4.3 Xem lần lượt
- `KTN`/`KTP`: nếu lỗi ở layout khác → `(setvar "CTAB" layout)` trước; zoom bằng `kt:zoom-center` (fallback `command "_.ZOOM" "_C"`), chọn đối tượng bằng `kt:select`, in "Loi i/n [A3] mo ta…".
- Bộ lọc: `KTN` hỏi `[Tat ca/Loi/Canhbao/Nhom]` lần đầu.

### 4.4 Xuất file (KTR)
- `<ten_dwg_ascii>_KT_<yyyymmdd-hhmm>.csv`: cột `STT;Ma;Muc do;Nhom;Layout;X;Y;Handle;Mo ta;Gia tri;Chuan` – ASCII, `;`.
- `.html`: bảng tổng hợp (số lỗi theo nhóm/mức), bảng chi tiết có lọc màu; chữ tiếng Việt lấy từ bản vẽ giữ dấu bằng `&#x…;`. Không JS ngoài; CSS nội tuyến → mở được offline, gửi kèm cho nhân viên.
- Ghi ngày giờ bằng `(getvar "CDATE")`; thư mục = DWGPREFIX nếu ghi được, ngược lại thư mục tool.
- Tùy chọn TXT tóm tắt in lên dòng lệnh (như CDO).

---

## 5. Rủi ro & việc cần làm tiếp
1. Chạy `KTPROBE` trên VinaCAD thật → cập nhật bảng 1.2 (thay [SL] bằng kết quả).
2. Xác nhận VinaCAD có tạo/giữ DIMASSOC, ACAD_REACTORS, xdata DSTYLE khi mở file AutoCAD (ảnh hưởng B3, B7).
3. Mở template bằng AutoCAD 2018+ chạy `KTCFG`, rà file ini với leader (vai trò block trục/cốt/callout).
4. Kiểm tra encoding tiếng Việt: attrib có dấu trả về dạng `\U+` hay ký tự codepage trên từng CAD.

## Nguồn tham khảo
- VinaCAD FAQ (tương thích): https://vina-cad.com/vi/faq/general/tinh-tuong-thich/vinacad-co-tuong-thich-voi-autocad-khong
- VinaCAD – VinaLisp, nạp .lsp bằng APLOAD: https://vina-cad.com/en/faq/general/Lisp-CAD/vinalisp
- VinaCAD trang chính: https://vina-cad.com/en ; Google Play: https://play.google.com/store/apps/details?id=com.vinacad.app
- BIMCAD Vietnam – VinaCAD vs AutoCAD: https://bimcad-vietnam.com/vi/news/vinacad-vs-autocad
- IntelliCAD forum (code không dùng vl-/vla-/vlax- thì chạy): https://forums.intellicadms.com/viewtopic.php?p=3797
- IntelliCAD LISP/SDS: https://intellicadms.com/13-in-detail/programming-development-toolkit/16-lisp-sds-icarx
- Autodesk – What's New/Changed AutoLISP (hàm không hỗ trợ, LT): https://help.autodesk.com/cloudhelp/2024/ENU/AutoCAD-AutoLISP/files/GUID-037BF4D4-755E-4A5C-8136-80E85CCEDF3E.htm
- Bricsys – getpropertyvalue khác AutoCAD: https://forum.bricsys.com/discussion/comment/38912/ ; https://developer.bricsys.com/bricscad/help/en_US/V25/DevRef/source/GenericPropertiesFunctions.htm
- ZWCAD LISP FAQ (khác biệt sysvar, (ver)): https://dl.zwsoft.com/support/ZWCAD/2025/LISP/Migration_Manual/ZWCAD_Lisp_FAQ_enu_2025.pdf
- Lỗi nạp lisp do đường dẫn có dấu: https://www.lisp.vn/2025/07/cach-khac-phuc-loi-load-lisp-khong-nhan.html
