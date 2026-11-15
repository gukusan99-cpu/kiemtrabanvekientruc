# Kiến trúc bộ KT – Kiểm Tra bản vẽ kiến trúc (AutoCAD + VinaCAD)

## Thư mục
```
lisp/
  KT_Load.lsp        nạp toàn bộ (APPLOAD file này / thêm vào Startup Suite)
  KT_Core.lsp        thư viện lõi (QUẢN LÝ viết – module KHÔNG sửa, cần thêm hàm thì báo)
  KT_Template.lsp    KTMAU   : trích chuẩn từ bản vẽ mẫu công ty -> KT_ChuanCongTy.txt
  KT_Layer.lsp       KTLAYER : layer / màu / linetype
  KT_Dim.lsp         KTDIM   : dimstyle, tỷ lệ dim, ghi đè chữ, dim không liên kết, chồng lấn (CDO)
  KT_Text.lsp        KTTEXT  : textstyle, font, chiều cao chữ theo tỷ lệ
  KT_Sheet.lsp       KTKHUNG : khung tên, số hiệu/tên bản vẽ, danh mục, ký hiệu tham chiếu
  KT_Match.lsp       KTKHOP  : khớp trục, khớp cao độ, khớp kích thước giữa các bản vẽ
  KT_Clean.lsp       KTSACH  : xref/ảnh mất, Z≠0, đối tượng rác/trùng, block chưa purge
  KT_Menu.lsp        KTALL (chạy tất cả), KTHELP
  KT_Dialog.lsp      KT/KTDLG: hộp thoại DCL tổng hợp (prefix ktdlg:, .dcl tự sinh lúc chạy;
                     KT_Dialog.dcl chỉ để tham khảo). Biến phiên *KT:DLG-...*
  KT_ChuanCongTy.txt file chuẩn công ty (sinh bởi KTMAU, sửa tay được)
  legacy/CheckDimOverlap.lsp  lisp CDO gốc (giữ nguyên)
tools/lisplint.py    kiểm tra tĩnh (bắt buộc sạch ERROR trước khi giao)
```

## Quy ước code (bắt buộc)
- Tiền tố hàm riêng mỗi module: `ktlay:` `ktdim:` `kttxt:` `ktsh:` `ktmat:` `ktcl:` `ktmau:`. Lệnh: `c:KTxxx`.
- Mọi biến cục bộ khai báo sau `/`. Biến toàn cục dạng `*KT:...*`.
- Prompt/thông báo **tiếng Việt không dấu**, ASCII.
- Chỉ dùng hàm có trong KT_Core hoặc AutoLISP/Visual LISP cơ bản. Mọi `vla-*` bọc `vl-catch-all-apply` + có phương án dự phòng DXF. Không dùng `acet-*`, `dos_*`, `getpropertyvalue`, reactor.
- Không sửa bản vẽ của nhân viên (chỉ đọc + vẽ đánh dấu trên layer KT_CHECK). Riêng KTMAU được ghi file txt.
- Mỗi lệnh kiểm tra: `(kt:cfg-ok)` → `(kt:begin "MODULE")` → nhiều `(kt:add ...)` → `(kt:finish "MODULE")` → `(princ)`.
  Lõi mỗi kiểm tra con bọc `vl-catch-all-apply` để 1 lỗi không làm hỏng cả lệnh.
- Mỗi module có thêm hàm `(<prefix>run)` không hỏi người dùng (dùng cho KTALL) và lệnh `c:` gọi lại hàm đó.

## API lõi (KT_Core.lsp)
| Hàm | Mô tả |
|---|---|
| `(kt:cfg-ok)` | nạp file chuẩn nếu chưa; T nếu có |
| `(kt:cfg "SEC")` | danh sách dòng (mỗi dòng = list chuỗi, đã bỏ tên mục) |
| `(kt:cfg-names "SEC")` | list trường 1 viết HOA |
| `(kt:cfg-row "SEC" name)` | dòng có trường 1 = name |
| `(kt:cfg-val key def)` `(kt:cfg-num key def)` `(kt:cfg-list key)` | đọc `SETTING|KEY|giatri` |
| `(kt:ss-all filter)` | list ename theo ssget "_X" |
| `(kt:dxf code ed)` `(kt:2d p)` `(kt:3d p)` | tiện ích |
| `(kt:space ed)` `(kt:cur-space)` | "Model" / tên layout |
| `(kt:box en)` `(kt:cen en)` `(kt:boxsize en)` `(kt:inbox p mn mx)` | hình học |
| `(kt:effname en)` `(kt:attribs en)` `(kt:attval en tag)` | block |
| `(kt:split s "|")` `(kt:join lst ",")` `(kt:trim s)` `(kt:num s)` `(kt:str x)` `(kt:wcmatch-any s pats)` | chuỗi |
| `(kt:parse-scale "1/100")` → 100.0 | |
| `(kt:frames)` | list khung tên: `(ename space minpt maxpt scale-thuc sohieu ten scale-ghi-trong-khung)` |
| `(kt:frame-at p space)` | khung chứa điểm |
| `(kt:viewports)` | `(ename layout scale model-min model-max)` |
| `(kt:scale-at p space)` | tỷ lệ tại điểm (100.0 cho 1/100), layout → 1.0, nil nếu không rõ |
| `(kt:scales-at p space)` | moi ty le ung vien tai diem (khung + cac viewport nhin thay) |
| `(kt:unaccent s)` `(kt:ascii s)` `(kt:norm s)` `(kt:plain s nl)` `(kt:wcesc s)` | bo dau (CP1252/CP1258/\U+), chuan hoa, bo ma MTEXT, escape wildcard cho ssget |
| `(kt:msort lst f)` `(kt:uniq lst)` | sap xep on dinh (thay vl-sort), loai trung |
| `(kt:box-dxf en)` `(kt:effname-dxf en)` | du phong khong ActiveX (VinaCAD) |
| `(kt:begin mod)` `(kt:add mod code sev msg ens pt r)` `(kt:finish mod)` | ghi lỗi. sev = "LOI" / "CANHBAO" / "GOIY". `ens` = ename hoặc list; pt/r có thể nil |

Lệnh chung trong lõi: KTN, KTP (xem lỗi kế/trước), KTX (xóa đánh dấu), KTBC (xuất CSV), KTCFG (nạp lại chuẩn).

## File chuẩn công ty `KT_ChuanCongTy.txt`
Mỗi dòng `MUC|truong1|truong2|...`, dòng `;` là ghi chú. Các mục:
```
SETTING|KEY|value
LAYER|ten|mau|linetype|lineweight(1/100mm, -3=default)|plot(1/0)
DIMSTYLE|ten|dimscale|dimlfac|dimtxt|dimasz|dimtxsty|dimdec|annotative(1/0)
TEXTSTYLE|ten|font file|bigfont|chieu cao co dinh|width factor
KHUNG|ten block|tag so hieu|tag ten ban ve|tag ty le|ty le goc (he so nhan voi scale X block)|tag khac...
BLOCK|ten block chuan (ky hieu truc, cao do, mat cat, chi tiet...)|vai tro (TRUC/CAODO/MATCAT/CHITIET/CUA/...)|tag chinh
LAYOUT|ten layout trong mau
DANHMUC|so hieu|ten ban ve   (danh muc ban ve chuan cua bo ho so)
```
SETTING quan trọng: `CAO_CHU_GIAY` (vd `1.8,2.0,2.5,3.5,5.0` mm giấy), `TY_LE_CHO_PHEP` (`20,25,50,100,200`), `LAYER_MAU_BYLAYER` (1 = bắt buộc màu ByLayer), `MAX_LOI_MOI_MA`, `DUNG_SAI_KICH_THUOC` (mm), `LAYER_BO_QUA` (wildcard, vd `DEFPOINTS,KT_CHECK,*|*`).
