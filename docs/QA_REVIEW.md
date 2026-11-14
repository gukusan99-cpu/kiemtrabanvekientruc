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

## Reviewer 1 - KT_Core.lsp, KT_Template.lsp, KT_Load.lsp, KT_Menu.lsp, KT_Layer.lsp, KT_ChuanCongTy.mau.txt

Kiem: `python3 tools/lisplint.py lisp/` -> 0 ERROR. Cac ham chuoi/ty le/hinh hoc thuan cua loi + `ktmau:guess-tags`,
`ktmau:blk-role` chay thu tren `tools/lispsim` (split, parse-scale, csvq, msort, unaccent/ascii voi CP1252 + CP1258,
norm MTEXT, xform, pts-box) -> dung ket qua mong doi. Phan can CSDL ban ve (entget/ssget/entmake) chua chay duoc.

### Bug da sua
| # | Muc | File / ham | Van de | Cach sua |
|---|---|---|---|---|
| 1 | CAO | Core `kt:dir` | KT_Load khong nam trong Support path -> `findfile "KT_Core.lsp"` nil -> thu muc = DWGPREFIX: KTMAU ghi file chuan canh ban ve mau, ban ve o thu muc khac khong tim thay chuan | Uu tien `*KT:HOME*` (KT_Load da dat), roi Support path, roi DWGPREFIX; `kt:path` noi duong dan khong nhan doi `\` (goc o "C:\") |
| 2 | CAO | Core KTBC `kt:report-file` | Ten DWG co dau tren LISP ANSI tra "Nh\U+00E0..." -> dau `\` trong ten file = thu muc -> `open` that bai; thu muc chi doc / file dang mo Excel -> khong co du phong | Ten file qua `kt:fname-safe` (bo dau, ky tu cam -> _); that bai -> ten co thoi diem, thu DWGPREFIX / thu muc tool / %TEMP% |
| 3 | CAO | Core `kt:viewports` | Bo qua 17 (target) va 51 (twist): VP xoay / DVIEW -> vung model sai (KTKHOP gan nham ban ve, scale-at sai) | Goc DCS = target, xoay -twist, hop bao 4 goc; VP khong phai plan -> khong xoay (gan dung). Them kiem 40>0 va 12 ton tai |
| 4 | CAO | Core `kt:frames` | Duyet MOI INSERT + effname ActiveX (ban ve 100k cham); scale uu tien ty le GHI (khung ghi sai -> lech chieu cao chu toan khung) | Loc ssget `(2 . "<ten escape>,`*U*")`; scale = ty le THUC (|X| x he so goc), chi dung ty le ghi khi DA SO khung trong ban ve lech (he so goc trong file chuan sai). Truong 7 van la ty le ghi |
| 5 | CAO (bao nham) | Template `text-stats` | Lam tron chieu cao 0.5mm: chu 1.8 -> 2.0, CAO_CHU_GIAY khong co 1.8 -> KTTEXT (dung sai 3%) bao nham moi chu 1.8 | Lam tron 0.1mm |
| 6 | TB | Core `kt:effname` | VinaCAD khong ActiveX: dynamic block tra "*U12" -> khong nhan khung ten/ky hieu dong | Du phong DXF: BLOCK -> 330 BLOCK_RECORD -> XData `AcDbBlockRepBTag` 1005 -> ten goc |
| 7 | TB | Core `kt:box` | Khong ActiveX: hop bao = 1 diem (DXF 10) -> moi khung ten suy bien, `kt:frame-at` khong bao gio khop | `kt:box-dxf`: INSERT (extents dinh nghia block, cache, scale/xoay, long 4 cap), TEXT (textbox+xoay), MTEXT, CIRCLE/ARC, cac diem 10-15 |
| 8 | TB | Core `kt:cfg-load` | Notepad luu UTF-8 co BOM -> dong dau hong ten muc; dong "LAYER" khong truong -> dong nil -> `kt:cfg-names` strcase nil loi ca module; append O(n^2) | Bo BOM; bo dong khong co truong; cons roi dao |
| 9 | TB | Core `kt:csvq` | Nhay kep doi thanh '' (khong chuan); xuong dong trong o | Nhan doi `""` (RFC4180), CR/LF -> cach |
| 10 | TB | Core KTBC | Excel may vung VN (list separator ';') mo CSV dau ',' thanh 1 cot; X/Y "12.50" co the thanh ngay | Dong dau `sep=,`; X/Y lam tron so nguyen; Noi dung qua `kt:ascii` (bo dau, giu hoa/thuong) |
| 11 | TB | Core `kt:goto` | Dang o trong viewport (MSPACE layout) -> zoom vao viewport thay vi giay; `setvar CTAB` layout da xoa -> loi dung lenh; `kt:zoom` goi `vlax-get-acad-object` NGOAI vl-catch-all-apply (CAD khong ActiveX -> loi) | `_.PSPACE` khi CVPORT/=1; setvar trong catch; zoom ActiveX trong lambda, du phong `_.ZOOM _C` voi CMDECHO 0 |
| 12 | TB | Core `kt:add`/`kt:mark` | Loi cap ban ve (khong doi tuong) ve vong tron o (0,0); doi tuong rat lon -> vong tron khong lo; DIMSCALE=0 -> ban kinh 0 -> entmake CIRCLE that bai | pt nil + ens nil -> khong ve (KTN in "loi chung cua ban ve", CSV de trong X/Y); ban kinh <= 20 x mac dinh; ban kinh mac dinh luon > 0 |
| 13 | TB (hieu nang) | Core `kt:finish` | Moi module xoa + ve lai TOAN BO danh dau: KTALL 6 module x hang nghin loi -> hang tram nghin entmake | Chi ve lai toan bo khi module nay co loi cu bi thay hoac so danh dau khong khop (undo/xoa tay); nguoc lai chi ve loi moi. Tom tat ghi "(chi ghi N - MAX_LOI_MOI_MA)" khi bi cat |
| 14 | TB | Core `kt:mklayer` | Layer KT_CHECK bi tat/dong bang/khoa -> danh dau khong thay, entdel that bai | Bat, tan bang, mo khoa layer KT_CHECK (layer cua tool) |
| 15 | TB | Core `kt:space` | ATTRIB/VERTEX khong co 410 -> "Model" du thuoc layout -> danh dau sai khong gian | Lay 410 cua INSERT/POLYLINE chu (330) |
| 16 | TB | Core `kt:parse-scale` | "1 / 100", "TL: 1 : 50" khong doc duoc (khoang trang); "11/100" doc thanh 1/100 | Bo khoang trang, ':' -> '/', bo "1/" dung sau chu so |
| 17 | TB | Template KHUNG `khung-cands/guess` | So kich thuoc giua khong gian: khung o layout (420 don vi) nho hon ky hieu o Model 1/100 -> khung bi loai khoi goi y | Ty le kich thuoc / block lon nhat CUNG khong gian; chon so luong -> so tag -> ty le |
| 18 | TB | Template doan tag | `*TEN*` khop TENCONGTRINH truoc TENBANVE; `*TL*` khop TITLE; `*SO*` khop SOTO | `ktmau:guess-tags`: mau cu the truoc, loai tag cong trinh/ngay/nguoi; tag ty le phai co gia tri doc duoc; tag so hieu chung chi nhan gia tri ngan co chu so |
| 19 | TB | Template he so goc | Mac dinh 1 -> khung ve san 1/100 (X=1) cho ty le 1 cho moi ban ve | Goi y = ty le ghi / scale X cua khung mau |
| 20 | TB (bao nham) | Template `blk-role`/`sec-block` | `*COT*` (cot nha) -> CAODO; `*MAT*`, `*CAT*` (LOCATION...) -> MATCAT; block cot khong attribute van vao muc BLOCK | `*COT*` chi CAODO khi co attribute; bo `*MAT*`/`*CAT*` chung; them `*COS*` |
| 21 | THAP | Template KHUNG | Khung khong attribute / xref khung bi tu choi | Cho chon, bao chi nhan dien vung + ty le |
| 22 | THAP | Template LAYOUT | layoutlist khong theo thu tu tab | Doc ACAD_LAYOUT sap theo DXF 71, layoutlist du phong |
| 23 | THAP | Template SETTING | TY_LE_CHO_PHEP nhan ty le le cua VP (37.31) | Chi ty le nguyen; them LAYER_BO_QUA CHECK_DIM_OVERLAP + goi y MAU_BYOBJ_BO_QUA |
| 24 | TB (bao nham) | Layer LAYER-0 | Khung ten chen o layer 0 tren layout (cach lam pho bien) -> LOI moi layout | Bo qua INSERT khung ten; doi tuong layer 0 tren layout -> CANHBAO |
| 25 | THAP | Layer | Layer `CHECK_DIM_OVERLAP` cua lisp CDO bi LAYER-LA; LAYER-TAT bo qua LAYER_BO_QUA | Them vao ignored; LAYER-TAT dung `ktlay:ignored` |
| 26 | THAP | Layer BLOCK-LAYER | Dynamic block chen dang *U -> "block khong duoc chen truc tiep" sai | Doi *U sang effname khi tim INSERT dai dien |
| 27 | THAP | Core `kt:split`/`kt:str`/`kt:attribs`/`kt:attval`/`kt:ss-all`/`kt:trim`/`kt:inbox` | split nil loi, phan cach >1 ky tu sai; kt:str ename da xoa -> nil (strcat nil); attribs khong kiem 66 / INSERT; attval tag nil; ss-all nil filter; trim so | Them bao ve; attribs doc ca nhom 3 (attribute nhieu dong) |
| 28 | THAP | Core KTCFG | Khong xoa cache viewport | `kt:reset-cache` |
| 29 | THAP | Menu KTHELP | Thieu KTPROBE | Them |

### API loi moi / thay doi (tuong thich nguoc, da grep lisp/)
- MOI: `kt:scales-at p sp` (moi ty le ung vien: khung + VP - de nghi Reviewer 2 #3), `kt:unaccent` `kt:ascii` `kt:hex` `kt:uchar`
  `kt:plain s nl` `kt:norm` `kt:txt` `kt:msort lst f` `kt:merge` `kt:uniq` `kt:wcesc` `kt:path` `kt:box-dxf` `kt:effname-dxf`.
  Ban sao `ktsh:*`/`ktmat:*`/`ktmau:msort` GIU NGUYEN, chu module tu chuyen. Luu y: `kt:uchar` xu ly dung CP1258
  (Ư=0xDD/ư=0xFD -> U, dau to hop 0xCC D2 DE EC F2 -> bo), ban sao trong ktsh/ktmat doi 221/253 -> "Y" va 204/210/236/242 -> I/O (sai khi Windows dat vung Viet Nam).
- `kt:scale-at`: nhieu VP khac ty le nhin thay diem -> ty le LON NHAT (truoc: VP dau tien). Model co khung -> ty le khung (nay la ty le thuc).
- `kt:frames` truong 4 = ty le thuc (truoc: ty le ghi). Truong 7 khong doi.
- Ban ghi loi: diem (nth 5) co the nil = loi cap ban ve (khi goi `kt:add` voi ens nil va pt nil). Khong module nao doc nth 5 cua *KT:ISSUES*.
- `kt:clear-module` tra T/nil; `kt:viewports` thu tu theo ban ve.
- ARCHITECTURE.md (khong thuoc pham vi sua) can bo sung cac ham tren.

### Con ngo / can thu tren CAD that
- Dau xoay twist: dua theo "UCS theo duong 30 do -> PLAN -> VIEWTWIST=330" => DCS X = goc -twist trong WCS. Can 1 VP xoay de xac nhan.
- DXF 69=1 co dung cho VP giay cua layout CHUA kich hoat khong; VP tat (68=0) van duoc tinh (xem Reviewer 2 #2).
- `kt:box-dxf`: block chua HATCH/SPLINE/POLYLINE cu chi lay diem 10-15; ATTDEF bo qua; ECS (extrusion am) khong xu ly.
- `kt:effname-dxf`: XData AcDbBlockRepBTag tren VinaCAD/ODA co giu khong - chua kiem.
- File chuan UTF-8 co dau: LISP ANSI doc byte UTF-8 -> ten layer co dau khong khop. Khuyen luu ANSI / khong dau (da ghi trong file mau).
- `sep=,` : Excel doc dung; LibreOffice/Power Query hien dong "sep=," nhu du lieu.
- KTMAU: DIMSTYLE entget co the bo nhom co gia tri mac dinh -> mac dinh ISO (2.5) duoc ghi; ban ve mau imperial se sai.
- LAYER-0/MAU-BYOBJ/LAYER-LA co the cung bao 1 doi tuong (3 dong) - co chu y, moi ma 1 y nghia.
- KT_Load: nap qua APPLOAD tu thu muc ngoai Support path va khong dat *KT:HOME* -> hoi duong dan moi lan mo ban ve (Startup Suite).
