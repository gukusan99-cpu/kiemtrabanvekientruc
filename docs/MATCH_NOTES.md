# Ghi chú KTKHOP (KT_Match.lsp) & KTKHUNG (KT_Sheet.lsp) – cách vẽ để tool nhận diện

## Giả định chung
- **Model vẽ 1:1, đơn vị mm**: khoảng cách trong Model = kích thước thật. Khung tên trong Model chỉ được *phóng to* theo tỷ lệ (scale X × "tỷ lệ gốc" của dòng KHUNG), hình vẽ không bị thu nhỏ. DIMLFAC coi = 1 (nếu dim có DIMLFAC ≠ 1 thì giá trị hiển thị = đo × DIMLFAC).
- **Một bản vẽ = một khung tên trong Model**, hoặc **một viewport trên layout** (vùng model mà viewport nhìn thấy, mang số hiệu của khung tên trên layout đó). Viewport nhìn vào vùng đã thuộc khung Model / viewport trước → bỏ qua (không đếm 2 lần).
- **Tên bản vẽ (attribute tên trong khung) quyết định loại**: chứa `MAT BANG` → mặt bằng; `MAT DUNG` / `MAT TIEN` / `MAT BEN` / `MAT SAU` → mặt đứng; `MAT CAT` → mặt cắt. So sánh không dấu (Unicode, `\U+XXXX`, CP1258 qua `kt:norm`; font TCVN3/ABC tự nhận), bỏ khoảng trắng. Tên tách 2 tag (`TENBANVE1` + `TENBANVE2`) được gộp. Font VNI chưa hỗ trợ → gõ Unicode hoặc không dấu.

## Trục (KHOP-TRUC / THUTU / TRUNGTRUC / DIMTRUC / TONG)
- Nên khai báo `BLOCK|<ten block truc>|TRUC|<tag ten truc>`. Không khai báo thì tool tự nhận: block có **đúng 1 attribute** giá trị `1`–`999` hoặc `A`–`ZZ` (cho phép `'`), định nghĩa block có **CIRCLE**. Trục kiểu `1A`, `A1` chỉ nhận khi đã khai báo.
- **Điểm chèn block trục phải là tâm vòng tròn, nằm trên đường trục** (tọa độ trục = điểm chèn).
- Ký hiệu trục cùng hàng (cùng Y ± ½ đường kính, hoặc cùng X) tạo thành 1 dãy. Ký hiệu ở 2 đầu trục cùng tên là bình thường. Trục số và trục chữ xét riêng.
- Chỉ bản vẽ MẶT BẰNG / MẶT ĐỨNG / MẶT CẮT tham gia bình chọn (chi tiết vẽ ngắt trục không bị so; `KHOP_TRUC_MOI_BAN_VE=1` để xét tất cả). Bản vẽ có mọi cặp trục = k × bản vẽ khác (k = 2, 2.5, 4, 5, 10, 20…: chi tiết phóng to) → GOIY `KHOP-PHONGTO`, bỏ khỏi bình chọn; dim trong đó so với khoảng cách × DIMLFAC.
- So khoảng cách mọi cặp trục giữa các bản vẽ, bình chọn theo đa số; bản vẽ lệch đa số bị báo trên các cặp liền kề của nó. Chỉ 2 bản vẽ mà khác nhau → báo cả hai.
- 2 bản vẽ đặt cạnh nhau trong 1 khung (kể cả mặt bằng mái chỉ có trục 2..4): tách đúng khi khoảng hở giữa chúng > 1,5 × nhịp trục trung vị; nếu không sẽ báo nhầm TRUNGTRUC.
- Dim trục: chỉ dim thẳng ngang/dọc có điểm 13/14 trùng tọa độ trục (± max(2×dung sai, 5mm)). Giá trị hiển thị so với khoảng cách trục × DIMLFAC (chấp nhận ghi theo m: `3.6`). Lỗi bắt: số ghi đè sai.

## Cao độ (KHOP-CAODO-VITRI / CAODO / CAODO-MB)
- Nên khai báo `BLOCK|<ten block cao do>|CAODO|<tag gia tri>`; giá trị chấp nhận `+3.600`, `3.600`, `3600` (mm), `%%p0.000`, `+3,600`. Không khai báo: tool đọc attribute/TEXT/MTEXT dạng `[+|-|±]x.xxx` (bắt buộc có dấu, hoặc là `0.000`), vd `COS +3.600`.
- **Điểm chèn block cao độ = đỉnh tam giác nằm đúng trên cao độ đó.** TEXT cao độ: mọi text cùng nằm trên vạch 1 khoảng như nhau (tool so text với text, block với block nên khoảng lệch tự triệt tiêu).
- Vị trí: mặc định chỉ xét **block** cao độ (TEXT đặt cách vạch tùy tay → `KHOP_CAODO_TEXT=1` mới xét). Ký hiệu gom theo "mốc ngầm định" Y − 1000×giá trị: cụm chứa ±0.000 là mốc; ký hiệu ngoài cụm mốc = sai vị trí (bắt cả lỗi copy ký hiệu +7.200 xuống sàn +3.600 quên sửa số). Cụm ≥ 2 giá trị lệch mốc > 1 m = hình vẽ khác xếp chồng (không ghi ±0.000) → bỏ qua. Mọi ký hiệu sai cùng hệ số phóng to tròn → GOIY `KHOP-PHONGTO`.
- Giữa các mặt đứng/mặt cắt: cặp giá trị lệch trong (1mm, `CAODO_LECH_NGHI`] mà bản kia không có (vd +7.200 / +7.150) → CANHBAO nếu 1 giá trị có trên mặt bằng (cốt sàn), ngược lại GOIY (bậu cửa, lanh tô, đáy dầm). Cao độ đỉnh khác nhau thường HỢP LỆ (mặt cắt qua tum thang) → chỉ báo GOIY khi `KHOP_CAODO_DINH=1`.
- Cao độ trên mặt bằng không có trên mặt cắt: mặc định chỉ GOIY khi GẦN (≤ `CAODO_LECH_NGHI`) một cao độ mặt cắt (`KHOP_CAODO_MB`: 0 tắt, 1 mặc định, 2 mọi giá trị).

## SETTING mới (tùy chọn)
| Khóa | Mặc định | Ý nghĩa |
|---|---|---|
| `DUNG_SAI_KICH_THUOC` | 1 | mm, so khoảng cách trục/dim |
| `DUNG_SAI_CAO_DO` | 5 | mm, sai lệch vị trí Y ký hiệu cao độ |
| `CAODO_LECH_NGHI` | 0.1 | m, ngưỡng nghi 2 cao độ là "cùng 1 tầng ghi khác" |
| `KHUNG_TAG_BO_QUA` | – | wildcard tag khung được để trống, vd `GHICHU,SUA*` |
| `KHOP_TRUC_MOI_BAN_VE` | 0 | 1 = mọi bản vẽ (cả chi tiết) bình chọn khoảng cách trục |
| `KHOP_CAODO_TEXT` | 0 | 1 = kiểm vị trí cả TEXT/MTEXT cao độ |
| `KHOP_CAODO_DINH` | 0 | 1 = GOIY khi cao độ đỉnh các mặt đứng/cắt khác nhau |
| `KHOP_CAODO_MB` | 1 | 0 tắt / 1 chỉ giá trị gần cao độ mặt cắt / 2 mọi giá trị |

## KTKHUNG – lưu ý cách vẽ
- Danh mục bản vẽ: TABLE có ô bắt đầu "DANH MUC"/"BANG DANH MUC", hoặc TEXT/MTEXT tiêu đề như vậy (ghi chú "XEM DANH MUC..." không tính) và các dòng TEXT/MTEXT trong cùng khung (không có khung: vùng dưới tiêu đề). Số hiệu trong danh mục phải **cùng tiền tố** với số hiệu khung (KT-01 = KT.01 = KT 01); số hiệu chỉ có chữ số (01, 02) không hỗ trợ (GOIY). Ô đơn: tên = ô hợp lệ cùng hàng GẦN NHẤT theo X (danh mục 2 cột cạnh nhau). Tên khớp khi giống nhau hoặc 1 tên chứa tên kia. > ½ danh mục không có khung (hồ sơ tách file) → 1 dòng GOIY.
- Ký hiệu mặt cắt/chi tiết: `BLOCK|<ten>|MATCAT|<tag ky hieu>|<tag so hieu ban ve>` (cột 4 tùy chọn; thiếu thì lấy tag tên khớp `*BV*,*SHEET*,*KH*,*SO*BV*`). Mặt cắt `1-1` cần có khung tên hoặc TEXT tiêu đề chứa "MAT CAT 1-1".
- KHUNG-THIEU: tag số hiệu/tên/tỷ lệ trống → LOI; tag khác trống chỉ CANHBAO khi ≥ ½ khung khác đã điền (ô tùy chọn trống ở mọi khung không báo).
- KHUNG-NHAYSO là GOIY (hồ sơ tách file); số hiệu ≥ 3 chữ số (A-101/A-201) xét riêng từng trăm.
- KHUNG-THAMCHIEU: chỉ xét số hiệu cùng tiền tố khung (KC-.., D-.. bỏ qua); có trong danh mục = có. Không có: trong khoảng số của file → CANHBAO, ngoài → GOIY.
- KHUNG-NGOAI chỉ xét khi có khung trong Model; vùng "trong" = khung Model + vùng model mà viewport nhìn thấy. Đếm theo điểm DXF 10 (HATCH, INSERT ngoài vùng: tâm hộp bao), gom theo ô lưới = kích thước khung trung bình; báo 20 ô đông nhất + 1 dòng tổng.

## Kiểm thử
`python3 tests/sim_match.py` – mô phỏng thuật toán gom trục / bình chọn / dim / cao độ (2 mặt bằng + mặt cắt + mặt đứng; cố ý lệch trục B 100mm, cao độ +3.600 thấp 50mm, dim ghi đè, mái khác, trục trùng, đổi thứ tự; và bộ hồ sơ đúng phải không báo gì).
