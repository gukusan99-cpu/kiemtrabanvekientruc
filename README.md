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
### 3.1 Hộp thoại tổng hợp – lệnh `KT` (hoặc `KTDLG`)
Gõ `KT` để mở hộp thoại gom toàn bộ bộ lisp (AutoCAD và VinaCAD, DCL cơ bản, file `.dcl` tự sinh –
chỉ cần các file `.lsp`):

```
+-- KIEM TRA HO SO BAN VE - KT v1.1 ----------------------------------------------------------+
| +- Module kiem tra --------------+  Muc do:[Tat ca v]  Module:[Tat ca v]  Khong gian:[Tat ca v] |
| | [x] Layer / mau / linetype      |  +- Ket qua (double-click hoac Xem de zoom toi loi) -------+ |
| | [x] Chu / textstyle / font      |  |  STT  MUC      MODULE MA                NOI DUNG        | |
| | [x] Kich thuoc / dimstyle       |  |    1  LOI      LAYER  LAYER-LA          Layer 'ABC-LA'..| |
| | [x] Khung ten / so hieu / DM    |  |    2  LOI      LAYER  LAYER-0           CIRCLE ve tren..| |
| | [x] Khop ban ve: truc/cao do    |  |    4  CANHBAO  TEXT   TEXT-CAO          TEXT cao 400 .. | |
| | [x] Lam sach file               |  |   ...                                                   | |
| | [Chon tat ca]  [Bo chon]        |  +---------------------------------------------------------+ |
| +---------------------------------+  #2 [LOI] LAYER-LAYER-0: CIRCLE ve tren layer 0 ... @Model  |
|           [ KIEM TRA ]               [Xem] [<< Loi truoc] [Loi sau >>] [Xuat CSV] [Xoa danh dau] |
| +- Thong tin ---------------------+  [x] Dung lai sau khi zoom                                 |
| | File chuan: ...ChuanCongTy.txt  |                                                            |
| | Trang thai: DA NAP (8 muc)      |                                                            |
| | Khung ten tim thay: 4           |                                                            |
| | Ket qua: 11 muc (LOI 5, ...)    |                                                            |
| +- Tong hop (module x muc do) ----+                                                            |
| | Module   LOI  CBAO  GOIY  Cong  |                                                            |
| | LAYER      2     0     1     3  |                                                            |
| | ...   TONG 5     4     2    11  |                                                            |
| +---------------------------------+                                                            |
| [Tao chuan tu ban ve mau...] [Nap lai chuan] [Mo file chuan] [Tro giup] [Dong]                  |
| (dong thong bao)                                                                                |
+-----------------------------------------------------------------------------------------------+
```
- Tick module, chọn **Pham vi kiem tra**: *Toan ban ve* (mặc định) hoặc *Chon vung (cua so)* →
  **KIEM TRA** (hộp thoại tạm đóng trong lúc chạy – với *Chon vung* thì chọn 2 góc cửa sổ – rồi tự mở
  lại với kết quả; dòng *Pham vi lan chay* trong khung Thong tin cho biết vùng đã dùng).
- Lọc theo mức độ / module / không gian; **double-click** hoặc **Xem** → zoom tới lỗi; **Loi truoc /
  Loi sau** đi theo danh sách đã lọc. Hộp thoại đóng – zoom – mở lại, giữ nguyên lựa chọn, bộ lọc và
  dòng đang chọn (DCL không cho zoom khi đang mở). Tick *Dung lai sau khi zoom*: CAD chờ Enter rồi mới mở lại.
- Danh sách hiện tối đa 500 dòng (xem đủ bằng **Xuat CSV**). Lựa chọn được nhớ trong phiên CAD.
- **Tao chuan tu ban ve mau** chạy `KTMAU` (hỏi ở dòng lệnh), **Mo file chuan** mở Notepad,
  **Nap lai chuan** = `KTCFG`.
- Nếu CAD không mở được hộp thoại DCL, `KT` tự chuyển sang dòng lệnh: hỏi chạy `KTALL`, xem lỗi bằng `KTN`/`KTP`.

### 3.2 Phạm vi kiểm tra (toàn bản vẽ / vùng)
`KTALL` (và các lệnh được nối qua `kt:cmd`) hỏi `Pham vi kiem tra [Toan ban ve/Vung] <Toan ban ve>:`
– Enter = cả bản vẽ; `V` (hoặc `W`) → chọn 2 góc cửa sổ trong không gian hiện tại (Model hoặc layout;
đang ở trong viewport thì là toạ độ Model). Khi có vùng, tool **vẫn đọc cả bản vẽ** (so khớp giữa các
bản vẽ vẫn đúng) nhưng **chỉ báo lỗi có vị trí nằm trong vùng**; lỗi ngoài vùng và lỗi chung của bản vẽ
bị bỏ, số lượng in ở dòng `(chi bao loi trong vung chon: N muc ngoai vung da bo qua)`. Vùng được vẽ
khung chữ nhật xanh lá trên layer `KT_CHECK` và chỉ áp dụng cho lần chạy đó. ESC tại câu hỏi → không chạy.

### 3.3 Lệnh dòng lệnh
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
`<tenbanve>_KiemTra.csv` mở bằng Excel), `KTX` (xóa đánh dấu). `KTHELP` liệt kê lệnh. `lisp/KT_Dialog.dcl` chỉ là bản tham khảo của file DCL tự sinh.

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
