# Bộ KT – Kiểm tra hồ sơ bản vẽ kỹ thuật thi công kiến trúc

Bộ AutoLISP giúp leader soát nhanh bản vẽ của nhân viên theo **quy cách bản vẽ mẫu của công ty**.
Chạy trên **AutoCAD** (khuyến nghị 2018 trở lên) và **VinaCAD**. Tool **chỉ đọc**: không sửa bản vẽ,
mọi đánh dấu nằm trên layer riêng `KT_CHECK` (xóa bằng `KTX`).

## 1. Cài đặt (1 lần)
1. Chép cả thư mục `lisp/` vào máy, ví dụ `D:\KT_Tool\` (đường dẫn **không dấu**).
2. AutoCAD: `OPTIONS` → *Files* → *Support File Search Path* → thêm `D:\KT_Tool`;
   AutoCAD 2014+: thêm cả vào *Trusted Locations*.
   VinaCAD: mục tương đương trong Tùy chọn (Options) → đường dẫn hỗ trợ.
3. `APPLOAD` → chọn `KT_Load.lsp` → thêm vào **Startup Suite** để tự nạp mỗi lần mở CAD.
4. Lần đầu trên VinaCAD: gõ `KTPROBE` – nếu có dòng `THIEU:` hãy gửi kết quả cho người phát triển.

## 2. Tạo chuẩn công ty từ bản vẽ mẫu (1 lần, làm lại khi đổi mẫu)
1. Mở bản vẽ mẫu (Nhà Chị Hạnh – Gia Lộc).
2. Gõ `KTMAU` → trả lời các câu hỏi (chọn khung tên, xác nhận tag số hiệu / tên bản vẽ / tỷ lệ).
3. Tool sinh `KT_ChuanCongTy.txt` cạnh `KT_Load.lsp`. **Mở file này rà lại** (layer, dimstyle,
   textstyle, khung tên, ký hiệu trục/cao độ/mặt cắt, các SETTING). Sửa tay được, rồi gõ `KTCFG` để nạp lại.
   Tham khảo `KT_ChuanCongTy.mau.txt` để biết ý nghĩa từng dòng.

## 3. Kiểm tra bản vẽ nhân viên
| Lệnh | Kiểm tra |
|---|---|
| `KTALL` | Chạy tất cả, in bảng tổng hợp |
| `KTLAYER` | Layer lạ, sai màu/linetype, đối tượng trên layer 0 / DEFPOINTS, màu gán ByObject, layer trong block |
| `KTDIM` | Dimstyle lạ, **tỷ lệ dim sai so với khung/viewport**, DIMLFAC sai, chữ dim ghi đè sai số đo, dim lẻ, dim trùng/chồng (thuật toán CDO) |
| `KTTEXT` | Textstyle/font sai, chiều cao chữ quy ra giấy sai, font thiếu |
| `KTKHUNG` | Khung tên thiếu thông tin, trùng / nhảy số hiệu, tỷ lệ ghi sai, so với bảng danh mục, ký hiệu mặt cắt/chi tiết trỏ tới bản vẽ không có |
| `KTKHOP` | **Khớp giữa các bản vẽ**: khoảng cách trục, thứ tự trục, dim trục, kích thước tổng, vị trí & giá trị cao độ giữa mặt đứng/mặt cắt |
| `KTSACH` | Xref/ảnh mất, Z≠0, line/block copy chồng, block/layer rác, hatch không liên kết |

Xem kết quả: `KTN` (lỗi tiếp theo – tự chuyển layout & zoom), `KTP` (lỗi trước), `KTBC` (xuất
`<tenbanve>_KiemTra.csv` mở bằng Excel), `KTX` (xóa đánh dấu). `KTHELP` liệt kê lệnh.

Mức độ: **LOI** (đỏ) – phải sửa · **CANHBAO** (vàng) – nên xem · **GOIY** (xanh) – tham khảo.

## 4. Quy ước vẽ để tool nhận diện đúng
- Model vẽ 1:1 theo mm; khung tên chèn ở Model được scale theo tỷ lệ (hoặc dùng Layout + viewport).
- Tên bản vẽ trong khung tên chứa `MAT BANG` / `MAT DUNG` / `MAT CAT` để `KTKHOP` phân loại.
- Ký hiệu trục, cao độ, mặt cắt nên là block khai báo trong mục `BLOCK` của file chuẩn;
  điểm chèn trục = tâm vòng tròn, điểm chèn cao độ = mũi tam giác. Chi tiết: `docs/MATCH_NOTES.md`.

## 5. Điều chỉnh độ nhạy (trong `KT_ChuanCongTy.txt`)
`CAO_CHU_GIAY`, `TY_LE_CHO_PHEP`, `DUNG_SAI_KICH_THUOC`, `DIM_BUOC_CHAN` (đặt 0.5 nếu dùng tường 105),
`LAYER_BO_QUA`, `MAX_LOI_MOI_MA`, `KIEM_DIM_ASSOC`… Thay đổi tạm cho dim: `KTDIMSET`.

## 6. Cấu trúc & phát triển
`docs/ARCHITECTURE.md` (kiến trúc, API), `docs/RESEARCH.md` (phương án, tương thích VinaCAD),
`docs/QA_REVIEW.md` / `docs/QA_RUNTIME.md` (nhật ký kiểm tra), `tools/lisplint.py` (soát lỗi tĩnh),
`tools/lispsim/` (giả lập chạy LISP), `tests/`. Lisp gốc CDO giữ ở `lisp/legacy/`.
