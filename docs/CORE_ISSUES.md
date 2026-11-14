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
