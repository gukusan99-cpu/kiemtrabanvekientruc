# Van de cua KT_Core.lsp (cac module bao cho QUAN LY)

## [Lap trinh vien B - KT_Layer/KT_Text/KT_Clean]
1. **SETTING LAYER_BO_QUA vi du `DEFPOINTS,KT_CHECK,*|*` bi tach sai**: `kt:cfg-load` tach dong theo `|` nen
   `kt:cfg-val "LAYER_BO_QUA"` tra ve `DEFPOINTS,KT_CHECK,*` -> mau `*` khop MOI layer. KT_Layer tam thoi bo mau `*`
   don le va tu bo qua layer co `|`. De nghi: `kt:cfg-val` noi lai cac truong con lai bang `|` (hoac doi vi du trong
   ARCHITECTURE.md bo `*|*`).
2. `kt:add` goi `(kt:cfg-num "MAX_LOI_MOI_MA" 300)` o MOI lan goi (duyet muc SETTING + strcase). Voi ban ve 100k doi tuong,
   cac ma loi theo tung doi tuong (LAYER-0, MAU-BYOBJ, Z-KHAC0...) co the goi hang chuc nghin lan. De nghi cache gia tri cap
   trong `kt:begin`.
3. `kt:wcmatch-any` / `kt:cfg-row` goi `strcase` tren tham so -> loi neu tham so nil. Module da tu kiem nil truoc khi goi;
   de nghi lop bao ve trong loi.

## [QUAN LY - da xu ly]
- (1) `kt:cfg-val` noi lai cac truong bang `|` (bo truong rong cuoi) -> `*|*` dung duoc. `kt:join` sua loi phan tu dau rong.
- (2) cap MAX_LOI_MOI_MA cache trong `kt:begin` (*KT:CAP*).
- (3) `kt:wcmatch-any`, `kt:cfg-row` chiu duoc nil.

## [Lap trinh vien A - KT_Template/KT_Load/KT_Menu]
1. `kt:dir` fallback `(getvar "DWGPREFIX")` da co `\` cuoi -> `kt:cfg-file` tao `...\\KT_ChuanCongTy.txt` (2 dau `\`).
   Windows chap nhan nhung nen bo `\` cuoi.
2. `kt:frames` chi tinh lai khi `*KT:FRAMES*` = nil; ban ve khong co khung -> quet lai moi lan goi `kt:frame-at`
   (cham neu goi trong vong lap moi doi tuong). De nghi danh dau 'NONE nhu `kt:viewports`.

- (4) `kt:dir` bo dau \ cuoi; (5) `kt:frames` cache ca truong hop khong co khung.

## [Lap trinh vien D - KT_Sheet/KT_Match]
1. De nghi dua vao loi cac ham chuoi dang bi chep lai o 2 module (ktsh:/ktmat:): bo dau tieng Viet `\U+XXXX`
   (`*:unaccent`, `*:uchar`, `*:hex`), bo ma dinh dang MTEXT (`*:plain`), chuan hoa so sanh (`*:norm`, chi giu A-Z 0-9),
   doc noi dung MTEXT dai (nhom 3 + 1: `*:txt`), merge sort on dinh (`*:msort` - vl-sort xoa phan tu trung).
2. `kt:viewports` tinh vung model tu DXF 12 (tam view theo DCS), bo qua 17 (view target) va 51 (twist):
   viewport xoay / UCS khac WCS cho vung model sai -> KTKHOP gan doi tuong nham ban ve. Nen dung them 17 va 51.
3. `kt:frames` (Model) uu tien ty le GHI trong khung (`tsc`) cho truong 4 `scale`; KTKHUNG tu tinh ty le thuc
   (|41| x ty le goc) de so. Neu module khac dung `kt:scale-at` cho chieu cao chu thi khung ghi sai ty le se lam
   lech ket qua cua module do (co the nen uu tien ty le thuc).

## [Reviewer 2 - QA KT_Text/KT_Clean/KT_Dim]
1. `kt:frames` duyet MOI INSERT (`kt:ss-all '((0 . "INSERT"))`) va goi `kt:effname` (ActiveX) + `kt:cfg-row` cho tung cai:
   ban ve 100k doi tuong nhieu block -> cham ngay lan dau goi `kt:scale-at`. De nghi loc ssget theo ten:
   `(2 . "<ten khung escape>,`*U*")` roi moi goi effname.
2. `kt:viewports` lay ca viewport dang TAT (DXF 68 = 0; -1 la VP bat nhung khong active, van giu) -> co the dua ty le cua VP an vao `kt:scale-at`.
   De nghi bo VP co 68 = 0 - NHUNG can kiem truoc: VP tren layout chua mo co the cung tra 68 = 0
   (chua xac nhan) -> thu tren AutoCAD 2018 truoc khi sua.
3. `kt:scale-at` (Model) chi tra 1 ty le (khung truoc, roi VP dau tien chua diem). Ban ve VN thuong co
   hinh chi tiet 1/20 nam trong khung/VP 1/100 -> module tu xet them moi VP chua diem (ktdim:vp-at,
   kttxt:vp-at). Nen co ham loi `kt:scales-at` tra ve TAT CA ty le ung vien.
4. (da duoc Reviewer 1 sua trong luc review) `kt:cp1258-p` tung goi `eql` - AutoLISP khong co ham nay.
