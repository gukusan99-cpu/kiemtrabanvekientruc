# Ghi chú KTKHOP (KT_Match.lsp) & KTKHUNG (KT_Sheet.lsp) – cách vẽ để tool nhận diện

## Giả định chung
- **Model vẽ 1:1, đơn vị mm**: khoảng cách trong Model = kích thước thật. Khung tên trong Model chỉ được *phóng to* theo tỷ lệ (scale X × "tỷ lệ gốc" của dòng KHUNG), hình vẽ không bị thu nhỏ. DIMLFAC coi = 1 (nếu dim có DIMLFAC ≠ 1 thì giá trị hiển thị = đo × DIMLFAC).
- **Một bản vẽ = một khung tên trong Model**, hoặc **một viewport trên layout** (vùng model mà viewport nhìn thấy, mang số hiệu của khung tên trên layout đó). Viewport nhìn vào vùng đã thuộc khung Model / viewport trước → bỏ qua (không đếm 2 lần).
- **Tên bản vẽ (attribute tên trong khung) quyết định loại**: chứa `MAT BANG` → mặt bằng; `MAT DUNG` / `MAT TIEN` / `MAT BEN` / `MAT SAU` → mặt đứng; `MAT CAT` → mặt cắt. So sánh không dấu (bỏ dấu `\U+XXXX`/Unicode), bỏ khoảng trắng. Font TCVN3/VNI không bỏ dấu được → nên gõ Unicode hoặc không dấu.

## Trục (KHOP-TRUC / THUTU / TRUNGTRUC / DIMTRUC / TONG)
- Nên khai báo `BLOCK|<ten block truc>|TRUC|<tag ten truc>`. Không khai báo thì tool tự nhận: block có **đúng 1 attribute** giá trị `1`–`999` hoặc `A`–`ZZ` (cho phép `'`), định nghĩa block có **CIRCLE**. Trục kiểu `1A`, `A1` chỉ nhận khi đã khai báo.
- **Điểm chèn block trục phải là tâm vòng tròn, nằm trên đường trục** (tọa độ trục = điểm chèn).
- Ký hiệu trục cùng hàng (cùng Y ± ½ đường kính, hoặc cùng X) tạo thành 1 dãy. Ký hiệu ở 2 đầu trục cùng tên là bình thường. Trục số và trục chữ xét riêng.
- So khoảng cách mọi cặp trục giữa các bản vẽ, bình chọn theo đa số; bản vẽ lệch đa số bị báo trên các cặp liền kề của nó. Chỉ 2 bản vẽ mà khác nhau → báo cả hai.
- 2 bản vẽ đặt cạnh nhau trong 1 khung: tách đúng khi khoảng hở giữa chúng > 1,5 × nhịp trục trung vị; nếu không sẽ báo nhầm TRUNGTRUC.
- Dim trục: chỉ dim thẳng ngang/dọc có điểm 13/14 trùng tọa độ trục (± max(2×dung sai, 5mm)). Lỗi thường gặp mà nó bắt: số ghi đè, DIMLFAC sai.

## Cao độ (KHOP-CAODO-VITRI / CAODO / CAODO-MB)
- Nên khai báo `BLOCK|<ten block cao do>|CAODO|<tag gia tri>`; giá trị chấp nhận `+3.600`, `3.600`, `3600` (mm), `%%p0.000`, `+3,600`. Không khai báo: tool đọc attribute/TEXT/MTEXT dạng `[+|-|±]x.xxx` (bắt buộc có dấu, hoặc là `0.000`), vd `COS +3.600`.
- **Điểm chèn block cao độ = đỉnh tam giác nằm đúng trên cao độ đó.** TEXT cao độ: mọi text cùng nằm trên vạch 1 khoảng như nhau (tool so text với text, block với block nên khoảng lệch tự triệt tiêu).
- Mốc = ký hiệu giá trị 0 (nhiều mặt đứng xếp chồng trong 1 khung → mỗi mặt có 1 mốc ±0.000 riêng); không có 0 thì lấy ký hiệu nhỏ nhất.
- Giữa các mặt đứng/mặt cắt: báo khi cao độ đỉnh khác nhau, hoặc có cặp giá trị lệch nhau trong khoảng (1mm, `CAODO_LECH_NGHI`] mà bản kia không có (vd +7.200 / +7.150).
- Cao độ ghi trên mặt bằng không có trên mặt cắt (không có mặt cắt → mặt đứng) → GOIY.

## SETTING mới (tùy chọn)
| Khóa | Mặc định | Ý nghĩa |
|---|---|---|
| `DUNG_SAI_KICH_THUOC` | 1 | mm, so khoảng cách trục/dim |
| `DUNG_SAI_CAO_DO` | 5 | mm, sai lệch vị trí Y ký hiệu cao độ |
| `CAODO_LECH_NGHI` | 0.1 | m, ngưỡng nghi 2 cao độ là "cùng 1 tầng ghi khác" |
| `KHUNG_TAG_BO_QUA` | – | wildcard tag khung được để trống, vd `GHICHU,SUA*` |

## KTKHUNG – lưu ý cách vẽ
- Danh mục bản vẽ: TABLE có ô chứa "DANH MUC", hoặc TEXT/MTEXT tiêu đề "DANH MUC..." và các dòng TEXT/MTEXT trong cùng khung (không có khung: vùng dưới tiêu đề). Số hiệu trong danh mục phải **cùng tiền tố** với số hiệu khung (KT-01); số hiệu chỉ có chữ số (01, 02) không hỗ trợ.
- Ký hiệu mặt cắt/chi tiết: `BLOCK|<ten>|MATCAT|<tag ky hieu>|<tag so hieu ban ve>` (cột 4 tùy chọn; thiếu thì lấy tag tên khớp `*BV*,*SHEET*,*KH*,*SO*BV*`). Mặt cắt `1-1` cần có khung tên hoặc TEXT tiêu đề chứa "MAT CAT 1-1".
- KHUNG-NGOAI chỉ xét khi có khung trong Model; đếm theo điểm DXF 10 (HATCH: tâm hộp bao), gom theo ô lưới = kích thước khung trung bình.

## Kiểm thử
`python3 tests/sim_match.py` – mô phỏng thuật toán gom trục / bình chọn / dim / cao độ (2 mặt bằng + mặt cắt + mặt đứng; cố ý lệch trục B 100mm, cao độ +3.600 thấp 50mm, dim ghi đè, mái khác, trục trùng, đổi thứ tự; và bộ hồ sơ đúng phải không báo gì).
