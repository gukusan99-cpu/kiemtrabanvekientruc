# Phân tích bản vẽ mẫu công ty (Template.dxf) → quy cách cho bộ KT

Nguồn: `Template.dxf` (27 MB, AC1024, `$DWGCODEPAGE` ANSI_1252, `$INSUNITS` 4 = mm, `$DIMSCALE` 0).
Số liệu sinh bằng `python3 -I tools/template_analysis.py Template.dxf` (báo cáo đầy đủ ra stdout,
`--cfg` sinh `lisp/KT_ChuanCongTy.txt` đã chọn lọc, `--json` danh sách khung). Kiểm chứng bằng
`tools/lispsim` + `dxfload` (KTMAU/KTALL chạy thật, xem `docs/QA_TEMPLATE_RUN.md`).

## 1. Tổng quan
- Model: 7 674 đối tượng (2 857 DIMENSION, 1 170 LWPOLYLINE, 1 131 LINE, 948 INSERT, 639 TEXT, 387 HATCH,
  214 MTEXT, 147 LEADER, 146 CIRCLE…). Layout1/Layout2 **rỗng** → mọi bản vẽ nằm trong Model, khung tên
  chèn theo tỷ lệ (Model 1:1, mm). Không có viewport.
- **73 khung**: 61 `KHUNGTEENA` (khung tên chính), 11 `KHUNGT43` (tờ bìa hạng mục, không attribute),
  1 `KHUNGDIENNUOC` (tờ phối cảnh PC/01). Xếp lưới theo hàng, mỗi hàng = 1 hạng mục, đầu hàng là tờ bìa.

## 2. Khung tên
| Block | Vai trò | Kích thước block | Tỷ lệ gốc | Attribute |
|---|---|---|---|---|
| KHUNGTEENA | khung A3 (420×297) **vẽ sẵn ở 1/100** | 42 000 × 29 700, điểm gốc = góc trên-trái | 100 | `SO_HIEU_BV`, `TEN_BAN_VE`, `TEN_CONG_TRINH`, `TY_LE` |
| KHUNGT43 | tờ bìa "HẠNG MỤC: …" | 22 680 × 16 038 (cùng tỉ lệ cạnh A) | 54 | – |
| KHUNGDIENNUOC | khung cùng mẫu + `NGAY`, `TEN_NGUOI_THIET_KE`, `TEN_TA`, `HOSO` | 42 000 × 29 700 | 100 | như trên |

- Tỷ lệ thực = |scale X| × tỷ lệ gốc: KHUNGTEENA scale 1 / 0.6 / 0.35 / 0.3 / 0.2 = 1/100, 1/60, 1/35, 1/30, 1/20;
  KHUNGT43 scale 1.852 / 0.648 / 0.556 = 1/100, 1/35, 1/30. `TY_LE` ghi dạng **`1:100`** – khớp tỷ lệ thực ở
  61/61 khung KHUNGTEENA (lệch duy nhất: PC/01).
- ATTDEF: `TY_LE` "1:100" (h 250, style `0_T_Arial Bold 2.5`), `SO_HIEU_BV` "KT/Z1/NDH/MB_01" (h 200),
  `TEN_CONG_TRINH`, `TEN_BAN_VE` (h 250). Block còn 37 TEXT cố định (tên công ty, chủ trì, KTS…) và 2 IMAGE logo.
- **Tên bản vẽ 2 dòng**: `TEN_BAN_VE` = loại ("MẶT BẰNG CÔNG NĂNG"), `TEN_CONG_TRINH` (tên tag gây hiểu nhầm)
  = dòng 2 ("TẦNG 1 & TẦNG 2", "TRỤC A-B, B-A", trống ở chi tiết). → file chuẩn khai báo
  `TEN_BAN_VE+TEN_CONG_TRINH`; dòng 2 được phép để trống.
- **Số hiệu** = `<mã hạng mục>/<2 số>`; trùng tên giữa các tờ của một bộ chi tiết là bình thường
  (C/01…C/07 "CHI TIẾT CỬA", VS/01…03 "CHI TIẾT WC1").

| Hạng mục (tờ bìa) | Số hiệu | Tên bản vẽ (+ dòng 2) | TL |
|---|---|---|---|
| Bìa hồ sơ + "MB BỐ TRÍ NỘI THẤT" | KT/01–04 | MẶT BẰNG CÔNG NĂNG (TẦNG 1&2, 3&4, TUM&MÁI, ĐỈNH MÁI) | 1/100 |
| MB TƯỜNG XÂY | TX/01–04 | MẶT BẰNG TƯỜNG XÂY (như trên) | 1/100 |
| MB ĐỊNH VỊ CỬA | ĐVC/01–03 | MẶT BẰNG ĐỊNH VỊ CỬA | 1/100 |
| – | C/00, C/01–07 | TỔNG HỢP CỬA, CHI TIẾT CỬA | 1/60 |
| MB CHỐNG THẤM | CTH/01, CTH/02–05 | CHI TIẾT CHỐNG THẤM; MẶT BẰNG CHỐNG THẤM | 1/100 |
| MẶT ĐỨNG | MD/01–03 | MẶT ĐỨNG (TRỤC A-B, B-A), MẶT ĐỨNG TRỤC 1-7, 7-1 | 1/100 |
| MẶT CẮT | MC/01–03 | GHI CHÚ MẶT CẮT, MẶT CẮT 1-1, 2-2 | 1/100 |
| CHI TIẾT KIẾN TRÚC | CT/01–03, CT/04–12 | CHI TIẾT MẶT ĐỨNG (trục…), CHI TIẾT CT-01…03 | 1/100, 1/30 |
| CHI TIẾT THANG BỘ | TH/01, TH/02 | CHI TIẾT THANG BỘ, CHI TIẾT BẬC THANG | 1/35, 1/20 |
| CHI TIẾT VỆ SINH | VS/01–12 | CHI TIẾT WC1…WC4 (3 tờ/WC) | 1/30 |
| MB LÁT SÀN | LS/01–04 | MẶT BẰNG LÁT SÀN | 1/100 |
| – | PC/01 | PHỐI CẢNH 1 (KHUNGDIENNUOC) | 1/60 (ghi 1:75) |

Danh mục: template **không có bảng danh mục** (KTKHUNG: GOIY). Mục `DANHMUC` của file chuẩn lấy từ 61 khung.

## 3. Ký hiệu
| Block | Vai trò | Tag | Cách đặt / định dạng | Số lần |
|---|---|---|---|---|
| `TRỤC` (LISP thấy `TR\U+1EE4C`) | trục | `A` (giữa-tâm, style `0 ARIAL 2.5`) | 2 vòng tròn r 233/267 tâm (0,−400); **điểm chèn = đuôi** (0,0) nằm trên đường trục; chèn xoay 180°, scale X âm → vòng tròn ở trên, cùng X với trục. Chỉ có trên mặt đứng/mặt cắt/chi tiết (mặt bằng: trục nằm trong block lồng – KTKHOP không đọc) | 142 |
| `COTCAODO` | cao độ MĐ/MC | `COTE` "+3.900", "-0.450" (dấu + bắt buộc, 3 số lẻ, m) | **đỉnh tam giác (−88.25, −49.03) nằm trên vạch cao độ, điểm chèn ở trên vạch 49 × scale**; cốt âm chèn mirror + xoay 180° → điểm chèn ở DƯỚI vạch. Scale = TL/104.7 (0.955 ở 1/100, 0.286 ở 1/30) | 157 |
| `KI HIEU CODE MB` | cao độ mặt bằng | `+0.000` (tên tag) = "+7.450", "%%P0.000" | điểm chèn = tâm, trên vạch ngang | 59 |
| `41244` / `1444` | ký hiệu mặt cắt | `B` = tên (A, B), `KT-00` = số tờ (MC/01, MC/02) | trên mặt bằng | 7 + 7 |
| `GHICHUCHITIET` | gọi chi tiết | `TENCT` (CT-01), `VITRIBANVE` (CT/04) | ngoài khung | 3 |
| `vet cat` | vết cắt (không attribute) | – | layer `Cat 30_KaTa` | 7 |
| `GHICHUCUA` / `1111111111111` | bảng / ký hiệu cửa | `TENCUA`… / `S1` mã cửa, kích thước, cao độ bậu | | 21 / 36 |
| `BLOCK ĐỘ DỐC 2` | độ dốc | `BLOCK` "i=0.5%" | | 8 |

- Kích thước ký hiệu trên giấy: trục Ø 4.05 mm ở 1/100 (scale 0.76); ở 1/30 **2 cỡ** (0.274 → Ø 4.9 mm, 0.391 → Ø 7 mm,
  54 ký hiệu VS/CT) – không đồng nhất. `KI HIEU CODE MB` 1/30: 0.33 (đúng TL) và 0.469 (16 ký hiệu to hơn 42%).
- Mốc cao độ kiểm bằng điểm gốc: MD/01–03, MC/02–03, CT/01–03, VS/03–12 đều đồng nhất (lệch 0 mm);
  **VS/02: −0.050 đặt cao hơn 20 mm** (đọc ra −0.030). Dùng điểm chèn thay vì đỉnh tam giác sẽ thấy 2 "mốc"
  lệch 93.6 mm (1/100) / 28 mm (1/30) ở MỌI mặt đứng → lý do thêm cột "điểm gốc" vào dòng BLOCK.
- Leader: 147 cái, mũi tên mặc định; dimstyle của leader đều là style rác (`Xr…$0$Standard` 63, `JFP_DG 1- 30` 58…),
  layer `1 KÍ HIỆU` 67 / `1-DIM` 63 / `1-GHICHU` 14.

## 4. Dim – quy cách công ty
| Dimstyle | DIMSCALE | DIMLFAC | DIMTXT | DIMASZ | Dùng ở khung | Số dim | Chữ trên giấy |
|---|---|---|---|---|---|---|---|
| DG 1-100 (200) | **0** | 1 | 150 | 60 | 1/100 | 1 431 | 1.5 mm (14 dim override DIMTXT 125 → 1.25) |
| TL 1-60 (120) | 0 | 1 | 120 | 40 | 1/60 | 107 | 2.0 mm |
| DG 1-30 (60) | 0 | 1 | 60 | 20 | 1/30 (+58 dim ở TH/01 1/35 → 1.71 mm) | 1 039 | 2.0 mm |
| DG 1-30 (60) x4 | 0 | **0.25** | 60 | 20 | chi tiết vẽ ×4 trong khung 1/30 (CT/04–11) | 200 | 2.0 mm |
| DG 1-30 (60) x2 | 0 | **0.5** | 60 | 20 | chi tiết vẽ ×2 (CT/12) | 38 | 2.0 mm |

- Textstyle dim `mb tret$0$DIMENSION` (font VNI-Helve-Condense, cao 0), mũi tên `_ArchTick`, DIMDEC 0, DIMTAD 1.
- **Mọi dim có override DSTYLE DIMSCALE = 1** (style = 0) và lặp lại DIMTXT/DIMLFAC của style. DIMSCALE 0 hay 1 trong
  Model như nhau → logic cũ "so DIMSCALE với tỷ lệ khung" báo nhầm **toàn bộ** dim ("TL 1/1 trong khung 1/100").
- Mã 42 (Measurement) **đã nhân DIMLFAC** (dim x4 đo 100 → 42 = 25) → KTDIM/KTKHOP tính giá trị hiển thị = độ dài
  hình học (13/14) × DIMLFAC.
- Tên "DG 1-100 (200)" ghi (200) nhưng DIMTXT = 150 – nên thống nhất (đổi tên hoặc DIMTXT).
- Không dim nào trộn DIMLFAC trong cùng chuỗi (chung điểm chân).

## 5. Chữ
| Textstyle (công ty) | Font | Cao cố định | Dùng cho |
|---|---|---|---|
| 0 ARIAL 2 / 0 ARIAL 2.5 / 0 ARIAL TÊN | arial / arial / arialbd | 200 / 250 / 400 (= 2/2.5/4 mm ở 1/100) | chữ trên bản vẽ, ký hiệu trục, tên hình |
| 0_T_Arial, 0_T_Arial Bold 2 / 2.5, 0_T_Arial 1.2 | arial(bd) | 2 / 2 / 2.5 / 1.2 (đơn vị giấy) | attribute khung tên, COTCAODO, GHICHUCUA |
| Arial, Standard | arial | 0 | ghi chú chi tiết cửa (2.2 mm ở 1/60), chữ tờ bìa |
| mb tret$0$DIMENSION | VNI-Helve-Condense | 0 | chữ dim |
| VHAVANT, bold | .VnAvantH (TCVN3) | 0 | tờ bìa KHUNGT43 |

Chiều cao chữ quy ra giấy (TEXT/MTEXT ngoài block, style công ty): 0.75 mm (tên đồ nội thất, 69), 1.25 (diện tích
phòng, 55), 1.8 (tên phòng, 46), 2.0, 2.2 (ghi chú cửa 1/60, 230), 2.5 (ghi chú 1/30, 90), 3.33 (bảng thống kê cửa),
4.0 / 5.0 (tên hình), 10 (tiêu đề bìa). Chữ ở TH/01 (1/35) dùng cỡ của 1/30 → 2.14 / 4.29 mm.
Các style "cao cố định" chỉ là giá trị mặc định khi gõ; cao thật của TEXT (mã 40) thường khác (vd `0 ARIAL 2` có chữ
75/125/180/200) → KTTEXT xét mã 40; style cao cố định chỉ quyết định cỡ chữ DIM (DIMTXT bị bỏ qua) – KTDIM tính
theo đó; KTTEXT báo `TEXT-STYLECAO` nếu chiều cao cố định của style khác chuẩn.

## 6. Layer
Họ công ty: `0`, `Defpoints` và **`1 <TÊN>`** (có dấu cách): 1 TEXT, 1 DIM, 1 HATCH, 1 TƯỜNG, 1 TRỤC (CENTER),
1 NÉT THẤY/MẢNH/KHUẤT (DASHED2)/CẮT BT, 1 NỘI THẤT, 1 CỬA, 1 CỘT, 1 KÍ HIỆU, 1 GHI CHÚ, 1 KHÔNG IN (plot 0),
1 NET SIÊU MỜ (17 layer, màu/lineweight xem file chuẩn). Khung tên chèn trên `1 TƯỜNG`.

## 7. Rác trong template (leader nên dọn – KTALL báo LOI/CANHBAO đúng)
| Loại | Tên | Ở đâu |
|---|---|---|
| Layer có đối tượng ngoài block (34) | `1-NETTHAY` (535), `1-GHICHU` (147), `1-DIM` (105), `1-TUONG` (87), `1-NETMANH`, `1-NETCATVATLIEU`, `1-HATCH`, `1-NETKHUAT`, `1-CUA_KINH`, `1-BETONG`, `Xr QC chong tham$0$A-Axis`, `DIM`, `TEXT` | CTH/01 (chi tiết chống thấm copy từ file khác) |
| | `TUONG` (157 – **mọi COTCAODO**), `9` (31, MC/02–03), `08. Net Text` (42), `Cat 30_KaTa` (vết cắt), `AUDIT_I_170609120347-0`, `cat go`, `VATLIEU` | ký hiệu, chi tiết |
| | `FF-FURN`, `FF-Plants`, `i_Noithat`, `A-NOITHAT`, `00N-Noi that`, `Net mo`, `Choiconcept_Hatch`, `cua` (35), `B-标注`, `KCS_Plotter` (78, plot 0), `RSA -NOTE`, `H`, `DG_DÂY ĐIỆN`, `TEXT KHUNG TEN` | đồ nội thất / ngoài khung |
| Layer chỉ trong block | `KHUNG`, `KHUNG TEN`, `Khung-HD`, `HPH_*`, `A-Thin`, `A-WIPEOUT`, `树2`, `thay`, `noithat`… (BLOCK-LAYER GOIY) | block nội thất tải về, chính KHUNGTEENA/KHUNGT43 |
| Layer rỗng | `MANH8`, `HATCH THIETBI`, `3`, `77`… | PURGE |
| Dimstyle | `JFP_DG 1- 20` (39 dim, TH/02), `JFP_DG 1- 30`, `JFP_DG 1- 65`, `DIM 35K`, `DIM SN 80A3`, `D60`, `Xr QC chong tham$0$Standard(_m)` | |
| Textstyle | `Xr QC chong tham$0$*` (CTH/01), `CA.JSC1` (CT/04, 07, 11), `TEXT` (TH/02), `ACA-AVH` (chú thích ngoài khung, TCVN3), `VnAvantH`, `TAE1`, `VTD - Iso A3 *` (trong block cửa), `LA-Avant`, `Ghi chu` (uv-abc.shx), `PVT_*`, `vnsimli`, `CHU`, `TK - Arial`, `Text ban ve`, `Text Dim`, `VNCC-Arial`, `TC_Text`, `JFP-Dim` | |
| Block | `A$C…`, `YLD.Studio-*`, `Delco_Section 2`, `Xr QC chong tham$0$*`, `COTS CAO`, `cot HTMB`, `note`, `note Door`, `12312`, `KHUNGDIENNUOC` (khung điện nước dùng cho phối cảnh) | |
| Khác | 2 IMAGE logo trong KHUNGTEENA mất đường dẫn (`..\1. CONG VIEC\…`); 60 đối tượng trên layer 0 (block `dy-T1` 19, `41244`/`1444` 14, `Xr…$0$VIT`…) | |

## 8. Lỗi có thật trong template (KTALL với chuẩn chọn lọc)
KTALL (lispsim, AutoCAD và VinaCAD cho **cùng** kết quả): **124 LOI / 504 CANHBAO / 186 GOIY**. Mọi LOI đều là lỗi có thật:

| Mã | Số | Nội dung |
|---|---:|---|
| LAYER-0 | 60 | đối tượng trên layer 0 trong Model |
| LAYER-LA | 34 | layer rác (mục 7) |
| DIM-GHIDE | 12 | 10 dim JFP (TH/02) ghi đè "141"/"171" ≠ đo 143/173; 2 dim xref ghi "25" (đo 49 m, DIMLFAC 100) |
| TEXT-STYLE | 7 | textstyle rác có chữ ngoài block |
| DIM-STYLE | 3 | `JFP_DG 1- 20` (39 dim), `D60` (1), `Xr…Standard_m` (2) |
| DIM-TYLE / DIM-LFAC | 2 / 2 | 2 dim xref: chữ 0.02 mm giấy, DIMLFAC 100 (CTH/01) |
| ANH-MAT | 2 | logo khung tên mất đường dẫn |
| KHUNG-TRUNGSO | 1 | **C/04 dùng cho 2 tờ** "CHI TIẾT CỬA" (tờ thứ 8 nên là C/08) |
| KHUNG-TYLE | 1 | PC/01 ghi 1:75 nhưng chèn 1/60 |

CANHBAO đáng chú ý (đúng): DIM-TYLE 112 (58 dim style 1/30 ở khung 1/35 – TH/01; 14 override DIMTXT 125; 39 JFP 2.2 mm),
DIM-LFAC 39 (JFP override DIMLFAC 0.5/0.2 thay vì dùng style x2/x5), DIM-LE 129 (đo lẻ do bắt điểm), DIM-CHU/CHUDIM 41,
KHUNG-THAMCHIEU 2 (ký hiệu mặt cắt **A, B** trỏ MC/01, MC/02 nhưng bản vẽ tên "MẶT CẮT 1-1/2-2" – MC/01 lại là
"GHI CHÚ MẶT CẮT"), TEXT-CAO 36 (CTH/01, TH/02), MAU-BYOBJ 126, LINE-TRUNG 13, Z-KHAC0 (5: 2 thật, 3 sai số < 0.001 –
B-T4 của QA, thuộc KT_Clean). Ngoài KTALL: VS/02 cao độ −0.050 lệch 20 mm (VS là "CHI TIẾT", KTKHOP không xét vị trí).

## 9. Thay đổi logic theo quy cách (đã làm)
- **DIM-TYLE** so *chiều cao chữ dim trên giấy* = DIMTXT hiệu dụng (cao cố định của textstyle dim > override > style)
  × (DIMSCALE nếu > 0, không thì 1) / TL khung (hoặc viewport) với `CAO_CHU_DIM` (lệch ≤ 25% → CANHBAO, hơn → LOI);
  thông báo kèm TL trong tên style ("style cho TL 1/30"). DIMSCALE 0 ≡ 1 trong DIM-OVR.
- **DIM-LFAC**: DIMLFAC = chuẩn của style (x2/x4) → hợp lệ; ghi đè DIMLFAC 1/2, 1/2.5, 1/4, 1/5, 1/10, 1/20 →
  CANHBAO (nên dùng style xN); thêm kiểm 2 dim cùng phương chung điểm chân khác DIMLFAC → CANHBAO.
  Giá trị hiển thị = hình học × DIMLFAC (không dùng mã 42) ở KTDIM và KTKHOP.
- **Khung**: nhiều dòng KHUNG (khung chính + tờ bìa không attribute + khung phụ); tag tên `A+B`; vùng khung = viền
  polyline lớn nhất của block (attribute/ảnh tràn ra ngoài không làm khung chồng nhau; VinaCAD = AutoCAD).
  KHUNG-TRUNGTEN bỏ qua bộ nhiều tờ số hiệu liên tiếp (`KHUNG_TRUNGTEN_LIENTIEP`).
- **Trục/cao độ**: tên block so bằng `kt:ukey` (HOA cả chữ có dấu, `\U+XXXX`); dòng BLOCK cột "điểm gốc x,y"
  cho cao độ; 2 hình cùng trục đặt cạnh nhau (6,7 | 6,7) không còn báo KHOP-TRUNGTRUC.
- **KTMAU**: tự đoán KHUNGTEENA (ưu tiên block có attribute ghi tỷ lệ), hỏi tag dòng 2, đề nghị khung phụ
  (KHUNGT43, KHUNGDIENNUOC), vai trò block theo tên bỏ dấu + giá trị attribute (cao độ / số hiệu bản vẽ), tự dò điểm
  gốc cao độ, bỏ tên xref bind `$0$`, thống kê chữ chỉ với style giữ lại (bước 0.05 mm), sinh `CAO_CHU_DIM`;
  sửa B-T1 (LAYOUT rỗng), B-T2 (dimstyle `$0$`), B-T3 (hộp bao IMAGE/WIPEOUT/HATCH/ELLIPSE).
- **Mã hóa tên**: file chuẩn ghi cp1252, ký tự ngoài cp1252 dạng `\U+XXXX` – đúng như AutoLISP ANSI thấy.
  `strcase` chỉ đổi a–z nên `kt:cfg-row`/`kt:ukey` chuẩn hóa thêm chữ có dấu & AutoLISP Unicode (LISPSYS=1).
  Máy Windows codepage 1258 (tiếng Việt): Ă/Đ/Ơ/Ư là 1 byte – `kt:ukey` đổi về mã Unicode nên KTDIM/KTTEXT/
  KTKHUNG/KTKHOP vẫn khớp; riêng KT_Layer/KT_Clean so bằng `strcase` → có thể báo LAYER-LA nhầm cho `1 TƯỜNG`,
  `1 CỘT`… – khi đó chạy lại KTMAU trên máy đó (hoặc chuyển KT_Layer sang `kt:cfg-keys`/`kt:ukey`).
