# QA REVIEW - bo KT

Moi reviewer ghi vao muc rieng cua minh, khong ghi de muc khac.

## Reviewer 2 - KT_Text.lsp, KT_Clean.lsp, KT_Dim.lsp, tests/test_ktdim.py

Kiem: `python3 tools/lisplint.py lisp/` -> 0 ERROR; `python3 -I tests/test_ktdim.py` -> OK (them 14 ca bao nham).
Doi chieu CDO goc (legacy/CheckDimOverlap.lsp): cac ham hinh hoc `ktdim:dimtext/textquad/mkquad/dimline/record/
proj/sat/lineover/dup/rad/pair` va vong quet X giong tung dong (chi doi prefix, `vl-sort` -> merge sort on dinh,
`*CDO:TOLR*/GAPR*` -> SETTING DIM_DUNG_SAI_TL / DIM_HO_CHU). Khac biet co chu y: (a) quet rieng tung khong gian,
pad/maxh tinh theo tung khong gian; (b) Enter = moi khong gian (CDO: khong gian hien tai); (c) dim tren
LAYER_BO_QUA (mac dinh DEFPOINTS) khong tham gia chong lan. Ket qua tren 1 khong gian tuong duong CDO.

### Bug / bao nham da sua
| # | Muc | File / ham | Van de | Cach sua |
|---|---|---|---|---|
| 1 | CAO (bao nham LOI) | KT_Dim `check1` DIM-GHIDE | Chu ghi de kieu cao do `+3.600` (dim ordinate / dim cao tang) bi so voi gia tri do -> LOI "Ghi +3.600 nhung do 3600" | Tach `ktdim:ghide`: so co dau +/- -> CANHBAO "chu cao do"; khong so voi do |
| 2 | CAO (bao nham LOI) | KT_Dim DIM-GHIDE | Ghi tay theo m/cm (`3.60`, `360` tren dim 3600) -> LOI | Khop x1000 / x10 trong dung sai -> CANHBAO "doi don vi bang tay" |
| 3 | CAO (bao nham hang loat) | KT_Dim DIM-LE | Dim hien m/cm bang DIMLFAC 0.001/0.01, hoac chi tiet ve phong to x5 (DIMLFAC 0.2): xet "le" tren gia tri hien thi (3.6 -> lech 0.4) -> CANHBAO moi dim | `ktdim:lex`: neu DIMLFAC<1 va 1/DIMLFAC nguyen -> xet tren gia tri do goc (mm) |
| 4 | CAO (bao nham LOI) | KT_Dim DIM-TYLE | Chi so voi 1 ty le (khung/VP dau tien). Hinh chi tiet 1/20 trong khung/VP 1/100 -> LOI moi dim chi tiet | Chap nhan neu DIMSCALE khop BAT KY VP nao nhin thay diem; neu DIMSCALE thuoc TY_LE_CHO_PHEP va nho hon TL khung -> CANHBAO kem loi giai thich |
| 5 | TB | KT_Dim DIM-LFAC | (a) so DIMLFAC tho (am o Model van bi bao du khong co tac dung); (b) chi tiet phong to (khung 1/100, DIMLFAC 0.2) bi LOI | So gia tri HIEU DUNG; neu DIMLFAC x TL khung thuoc TY_LE_CHO_PHEP -> CANHBAO "chi tiet phong to? TL that 1/20" |
| 6 | TB (bao trung) | KT_Dim DIM-OVR | Override DIMSCALE/DIMLFAC bao 2 lan (DIM-TYLE/LFAC + DIM-OVR) | Bo ma da bao o TYLE/LFAC khoi DIM-OVR cua dim do |
| 7 | TB (on) | KT_Dim DIM-STYLE | 1 LOI / dim (ca mat bang dung style la -> 300 dong) | Gom 1 dong / style (dem so dim, chon toi da 10 dim) nhu TEXT-STYLE |
| 8 | THAP (kieu) | KT_Dim check1 | `fix` tren DIMDEC/DIMSCALE/DIMLFAC/42 khong kiem kieu (XData hong -> loi ca dim) ; DIMDEC lon -> `rtos` qua dai | Kiem `numberp`, chan DIMDEC 0..8, DIMLFAC=0 coi nhu 1 |
| 9 | CAO (bao nham) | KT_Text TEXT-CAO | Chu ghi chu cua hinh chi tiet 1/20 trong khung 1/100 (h=50 -> 0.5mm) -> CANHBAO hang loat | Xet them moi VP chua chu; neu khop 1 TY_LE_CHO_PHEP nho hon TL khung -> GOIY "neu la chu chi tiet thi bo qua" |
| 10 | TB (bao nham) | KT_Text TEXT-CAO | Chu annotative: DXF 40 khong phai chieu cao giay x TL | Doc XData AcadAnnotative, bo qua chu annotative |
| 11 | TB | KT_Text scan | Khong ap LAYER_BO_QUA (chu tren DEFPOINTS/KT_CHECK/xref-bind van bi bao) ; filter 8 khong escape | Ap LAYER_BO_QUA; escape ten layer bang ` |
| 12 | THAP | KT_Text stylefont | `(entget (tblobjname ...))` khong kiem nil | Kiem nil |
| 13 | THAP (hieu nang) | KT_Text scan | `kt:cfg-row "TEXTSTYLE"` (strcase toan muc) cho MOI TEXT | Cache width chuan theo style (*KT:TXWID*) |
| 14 | THAP | KT_Text chk-fonts | Thong diep "style chua dung cho chu nao" sai khi style dung trong block/dim | Doi thanh "khong co TEXT/MTEXT ngoai block dung style nay" |
| 15 | TB (bao trung) | KT_Clean | TEXT-RONG bao o ca SACH va TEXT -> KTALL ra 2 dong cho 1 chu | Bo TEXT-RONG khoi SACH (TEXT da kiem ca TEXT + MTEXT) |
| 16 | TB (bao nham LOI) | KT_Clean XREF-MAT | Xref long (ten `A|B`) co duong dan tuong doi theo file cha -> findfile tu DWGPREFIX that bai -> LOI du xref van hien | Bo qua xref co 70 bit 32 (CAD da resolve) |
| 17 | TB (on) | KT_Clean HATCH-KLK | 1 GOIY / hatch (ban ve VN rat nhieu hatch mat lien ket sau copy/mirror) | Gom 1 dong / khong gian, chon toi da 50 hatch |
| 18 | THAP (hieu nang) | KT_Clean LAYER-RONG | `ssget "_X"` cho moi layer truoc khi loc layer dung trong block | Loc theo block truoc, chi ssget layer con lai |

### Da kiem, khong thay loi
- XData DSTYLE: doc dung cap (1070 ma, 1040/1070/1005/1000 gia tri), dung o `}`; ma 271 tra 1070.
- Loai dim `70 & 7` (bit 32/64/128 la co); dim thang 0/1 cho duong dim; 2/5 goc khong so so; 6 ordinate.
- MTEXT `ktdim:plain`: vi tri `vl-string-search` 0-base vs `substr` 1-base dung; `\S..;` `\f..;` `\H..;` bo dung.
- `ssget` filter: TEXT/Clean deu escape `#@.*?~[]-,`` bang `` ` ``; `-4 <NOT/NOT>` dung cu phap.
- Khong co `/` 2 so nguyen nguy hiem (`row`/`col` MTEXT la chia nguyen co chu dich nhu CDO).
- So sanh real: dung sai tuong doi 1e-6 (DIMLFAC), 1% (ty le), 3% (chieu cao chu).

### Con ngo / chua kiem duoc (can chay that tren AutoCAD 2018 / VinaCAD)
- DIM-LE buoc mac dinh DIM_BUOC_CHAN=1: tuong 105 truc giua -> mep 52.5 se bi CANHBAO. Neu cong ty dung tuong
  105/ op 15 nen dat `SETTING|DIM_BUOC_CHAN|0.5`. Thang bo 3600/13=276.92 cung bi bao (dung, nhung de nham).
- TEXT-CAO: CAO_CHU_GIAY trong file mau chi den 5.0 - tieu de hinh 7mm se bi CANHBAO -> KTMAU nen trich ca chieu cao tieu de.
- Xref unload (khong resolve) co con giu bit 32 khong? Neu con thi xref mat file ma dang unload se khong bi bao.
- Chu annotative: dang bo qua han; co the tinh h giay = 40 / CANNOSCALE nhung chua chac DXF 40 tra ve ban the nao.
- ARC_DIMENSION / dim ban kinh gay (jogged): `ssget (0 . "DIMENSION")` co lay khong va 70&7 la gi - chua xac nhan.
- KTDIM hieu nang: 3 lan entget / dim + `kt:scale-at` + `ktdim:vp-at` / dim -> 10k dim on; 100k dim chua do.
- Loi nhan core (kt:frames cham, VP tat, scale-at 1 ung vien) ghi o docs/CORE_ISSUES.md muc Reviewer 2.
