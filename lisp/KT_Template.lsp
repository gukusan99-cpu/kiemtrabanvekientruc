;;; ============================================================
;;; KT_Template.lsp  -  Lenh KTMAU: trich CHUAN CONG TY tu ban ve mau
;;; ------------------------------------------------------------
;;; Cach dung:
;;;   1. Mo ban ve mau cong ty (vd "Nha Chi Hanh (Gia Loc)") trong AutoCAD/VinaCAD.
;;;   2. Nap KT_Load.lsp, go lenh KTMAU, tra loi cac cau hoi.
;;;   3. Lenh ghi file KT_ChuanCongTy.txt (duong dan (kt:cfg-file)); file cu
;;;      (neu co) duoc sao luu thanh KT_ChuanCongTy.bak.
;;;   4. MO FILE TXT DE RA SOAT (vai tro BLOCK, tag KHUNG, CAO_CHU_GIAY...).
;;;
;;; Muc trich: LAYER, DIMSTYLE, TEXTSTYLE, KHUNG, BLOCK, LAYOUT, DANHMUC, SETTING.
;;; Chi doc ban ve, KHONG sua ban ve. Chi ghi file txt.
;;; Can KT_Core.lsp nap truoc.
;;; ============================================================

;;; ---------- Tien ich ----------
(defun ktmau:try (fn args / r m)
  ;; goi (fn args...) an toan; loi -> in thong bao, tra ve nil. ESC -> thoat lenh.
  (setq r (vl-catch-all-apply fn args))
  (if (vl-catch-all-error-p r)
    (progn
      (setq m (vl-catch-all-error-message r))
      (if (wcmatch (strcase m) "*CANCEL*,*QUIT*,*EXIT*")
        (exit))
      (princ (strcat "\n[KTMAU] Loi khi chay " (kt:str fn) ": " m))
      nil)
    r)
)

(defun ktmau:fnok (sym)
  (if (and sym (not (member (type sym) '(STR INT REAL ENAME PICKSET FILE)))) T nil)   ; khong so ten kieu
)

(defun ktmau:clean (s / i c res)
  ;; truong du lieu: doi '|' -> '/', ky tu dieu khien -> ' '. Giu nguyen ky tu khac
  ;; (ten layer/block/tag phai trung khop chinh xac voi ban ve).
  (setq s (kt:str s) res "" i 1)
  (while (<= i (strlen s))
    (setq c (substr s i 1))
    (cond ((= c "|") (setq c "/"))
          ((< (ascii c) 32) (setq c " ")))
    (setq res (strcat res c) i (1+ i)))
  (kt:trim res)
)

(defun ktmau:ascii (s / i c res)
  ;; chi dung cho dong ghi chu: ky tu ngoai ASCII -> '?'
  (setq s (kt:str s) res "" i 1)
  (while (<= i (strlen s))
    (setq c (substr s i 1))
    (if (or (< (ascii c) 32) (> (ascii c) 126)) (setq c "?"))
    (setq res (strcat res c) i (1+ i)))
  res
)

(defun ktmau:fmt (x / s r)
  ;; so -> chuoi gon: 100.0 -> "100", 2.50 -> "2.5"
  (cond
    ((null x) "")
    ((= (type x) 'INT) (itoa x))
    ((= (type x) 'REAL)
     (setq r (fix (+ x (if (minusp x) -0.5 0.5))))
     (if (equal x (float r) 1e-6)
       (itoa r)
       (progn
         (setq s (rtos x 2 6))
         (if (vl-string-search "." s)
           (progn
             (while (= (substr s (strlen s) 1) "0") (setq s (substr s 1 (1- (strlen s)))))
             (if (= (substr s (strlen s) 1) ".") (setq s (substr s 1 (1- (strlen s)))))))
         (cond ((= (substr s 1 1) ".") (setq s (strcat "0" s)))
               ((and (> (strlen s) 1) (= (substr s 1 2) "-.")) (setq s (strcat "-0" (substr s 2)))))
         s)))
    (T (kt:str x)))
)

(defun ktmau:row (sec fields)
  ;; tao 1 dong "SEC|f1|f2|..."
  (kt:join (cons sec (mapcar '(lambda (x) (if (numberp x) (ktmau:fmt x) (ktmau:clean x))) fields)) "|")
)

(defun ktmau:adduniq (x lst)
  ;; them chuoi x (viet HOA) vao lst neu chua co
  (if (and x (= (type x) 'STR) (/= x "") (not (member (strcase x) lst)))
    (cons (strcase x) lst)
    lst)
)

(defun ktmau:merge (a b cmp / res)
  (while (and a b)
    (if (apply cmp (list (car b) (car a)))
      (setq res (cons (car b) res) b (cdr b))
      (setq res (cons (car a) res) a (cdr a))))
  (append (reverse res) a b)
)

(defun ktmau:msort (lst cmp / a n i)
  ;; merge sort on dinh, KHONG xoa phan tu trung (khac vl-sort)
  (if (or (null lst) (null (cdr lst)))
    lst
    (progn
      (setq n (/ (length lst) 2) i 0)
      (while (< i n)
        (setq a (cons (car lst) a) lst (cdr lst) i (1+ i)))
      (ktmau:merge (ktmau:msort (reverse a) cmp) (ktmau:msort lst cmp) cmp)))
)

(defun ktmau:sort-str (lst)
  (ktmau:msort lst '(lambda (a b) (< (strcase a) (strcase b))))
)

(defun ktmau:sort-num (lst)
  (ktmau:msort lst '(lambda (a b) (< a b)))
)

(defun ktmau:pad0 (s n)
  (while (< (strlen s) n) (setq s (strcat "0" s)))
  s
)

(defun ktmau:natkey (s / i c num res)
  ;; khoa sap xep "tu nhien": KT-2 < KT-10 (day so duoc dem 0 ben trai)
  (setq s (strcase (kt:str s)) i 1 res "" num "")
  (while (<= i (strlen s))
    (setq c (substr s i 1))
    (if (wcmatch c "#")
      (setq num (strcat num c))
      (progn
        (if (/= num "") (setq res (strcat res (ktmau:pad0 num 8)) num ""))
        (setq res (strcat res c))))
    (setq i (1+ i)))
  (if (/= num "") (setq res (strcat res (ktmau:pad0 num 8))))
  res
)

(defun ktmau:first-match (tags pats excl / r)
  ;; tag dau tien khop mau (uu tien theo thu tu mau), bo qua cac tag trong excl
  (foreach p pats
    (foreach tg tags
      (if (and (not r) (not (member tg excl)) (wcmatch tg p))
        (setq r tg))))
  r
)

(defun ktmau:guess-tags (atts / tags val tTen tTL tSo bad)
  ;; atts = ((TAG . gia tri) ...) cua khung mau -> (tagSo tagTen tagTL)
  ;; uu tien mau ten cu the; tag ty le phai co gia tri doc duoc "1/100"
  (setq tags (mapcar 'car atts)
        bad  '("*CONG*TRINH*" "*CT" "*_CT*" "*DU*AN*" "*HANG*MUC*" "*CHU*DAU*TU*" "*CDT*"
               "*KHACH*" "*NGUOI*" "*THIET*KE*" "*KIEM*" "*DIA*DIEM*" "*NGAY*" "*DATE*"
               "*PROJECT*" "*CLIENT*" "*SO*TO*" "*TONG*" "*SO*LUONG*"))
  (defun val (tg) (cdr (assoc tg atts)))
  ;; TY LE: tag co gia tri la ty le, uu tien ten
  (setq tTL (ktmau:first-match
              (vl-remove-if-not '(lambda (tg) (kt:parse-scale (val tg))) tags)
              '("*TY*LE*" "*TYLE*" "*SCALE*" "TL" "TL*" "*_TL*" "*TL" "*") nil))
  (if (null tTL)
    (setq tTL (ktmau:first-match tags '("*TY*LE*" "*TYLE*" "*SCALE*" "TL" "TL_*" "*_TL") nil)))
  ;; TEN BAN VE
  (setq tTen (ktmau:first-match tags '("*TEN*BAN*VE*" "*TENBV*" "*TEN*BV*" "*BAN*VE*" "*TITLE*"
                                       "*DRAW*NAME*" "*DWG*NAME*" "*TEN*HINH*") (list tTL)))
  (if (null tTen)
    (setq tTen (ktmau:first-match
                 (vl-remove-if '(lambda (tg) (kt:wcmatch-any tg bad)) tags)
                 '("*TEN*" "*NAME*") (list tTL))))
  ;; SO HIEU: ten cu the truoc; tag chung chi nhan khi gia tri ngan va co chu so (KT-01, A101)
  (setq tSo (ktmau:first-match tags '("*SO*HIEU*" "*SOHIEU*" "*SO*BV*" "*SO*BAN*VE*" "*KY*HIEU*BV*"
                                      "*KH*BV*" "*MA*BV*" "*SHEET*NO*" "*DWG*NO*" "*DRAW*NO*" "*SHEET*")
                               (list tTen tTL)))
  (if (null tSo)
    (setq tSo (ktmau:first-match
                (vl-remove-if-not
                  '(lambda (tg) (and (val tg) (<= (strlen (val tg)) 12) (wcmatch (val tg) "*#*")
                                     (not (kt:parse-scale (val tg)))
                                     (not (kt:wcmatch-any tg bad))))
                  tags)
                '("*SO*" "*SH*" "*KH*" "*NO*" "*BV*" "*MA*") (list tTen tTL))))
  (list tSo tTen tTL)
)

(defun ktmau:xref-blk-p (nm / bd)
  ;; T neu block la xref (70 bit 4) hoac phu thuoc xref
  (and nm
       (or (wcmatch nm "*|*")
           (and (setq bd (tblsearch "BLOCK" nm))
                (/= 0 (logand 4 (cond ((kt:dxf 70 bd)) (0)))))))
)

(defun ktmau:blk-ents (nm / e ed res)
  ;; danh sach ename trong dinh nghia block nm (bo qua xref)
  (if (and nm (not (ktmau:xref-blk-p nm)) (setq e (tblobjname "BLOCK" nm)))
    (progn
      (setq e (entnext e))
      (while e
        (setq ed (entget e))
        (if (or (null ed) (= (kt:dxf 0 ed) "ENDBLK"))
          (setq e nil)
          (setq res (cons e res) e (entnext e))))))
  (reverse res)
)

(defun ktmau:attdefs (nm / res ed)
  ;; tag ATTDEF trong dinh nghia block
  (foreach e (ktmau:blk-ents nm)
    (setq ed (entget e))
    (if (= (kt:dxf 0 ed) "ATTDEF")
      (setq res (ktmau:adduniq (kt:dxf 2 ed) res))))
  (reverse res)
)

(defun ktmau:tblent (tbl nm / e)
  ;; entget day du cua ban ghi bang (nil neu khong co)
  (if (and nm (setq e (tblobjname tbl nm))) (entget e))
)

;;; ---------- Quet doi tuong dang dung ----------
(defun ktmau:scan-usage (/ todo done en ed bd typ nm e lays dims stys)
  ;; tra ve (layers dimstyles textstyles) dang duoc dung (VIET HOA)
  ;; gom doi tuong model + layout + noi dung cac block dang duoc chen (de quy)
  (setq todo (kt:ss->list (ssget "_X")))
  (while todo
    (setq en (car todo) todo (cdr todo))
    (if (and en (setq ed (entget en)))
      (progn
        (setq typ  (kt:dxf 0 ed)
              lays (ktmau:adduniq (kt:dxf 8 ed) lays))
        (if (member typ '("TEXT" "MTEXT" "ATTDEF" "ATTRIB"))
          (setq stys (ktmau:adduniq (kt:dxf 7 ed) stys)))
        (if (member typ '("DIMENSION" "ARC_DIMENSION" "LARGE_RADIAL_DIMENSION" "LEADER" "TOLERANCE"))
          (setq dims (ktmau:adduniq (kt:dxf 3 ed) dims)))
        (if (= typ "INSERT")
          (progn
            (if (= (kt:dxf 66 ed) 1)
              (progn
                (setq e (entnext en))
                (while (and e (setq bd (entget e)) (= (kt:dxf 0 bd) "ATTRIB"))
                  (setq todo (cons e todo) e (entnext e)))))
            (setq nm (kt:dxf 2 ed))
            (if (and nm (not (member (strcase nm) done)))
              (setq done (cons (strcase nm) done)
                    todo (append (ktmau:blk-ents nm) todo))))))))
  (list lays dims stys)
)

;;; ---------- LAYER ----------
(defun ktmau:sec-layer (used / d nm ed res)
  ;; used = list ten layer dang dung (nil = lay het)
  (setq d (tblnext "LAYER" T))
  (while d
    (setq nm (kt:dxf 2 d))
    (if (and nm (/= nm "")
             (not (wcmatch nm "*|*"))
             (not (member (strcase nm) '("KT_CHECK" "CHECK_DIM_OVERLAP")))
             (or (null used) (member (strcase nm) used)))
      (progn
        (setq ed (cond ((ktmau:tblent "LAYER" nm)) (d)))
        (setq res (cons (ktmau:row "LAYER"
                          (list nm
                                (abs (cond ((kt:dxf 62 ed)) (7)))
                                (cond ((kt:dxf 6 ed)) ("Continuous"))
                                (cond ((kt:dxf 370 ed)) (-3))
                                (if (= (kt:dxf 290 ed) 0) 0 1)))
                        res))))
    (setq d (tblnext "LAYER")))
  (ktmau:sort-str res)
)

;;; ---------- DIMSTYLE ----------
(defun ktmau:annot (en / r xd vals)
  ;; doc XData AcadAnnotative: (1000 "AnnotativeData") (1002 "{") (1070 1) (1070 co) ...
  (setq r (vl-catch-all-apply 'entget (list en '("AcadAnnotative"))))
  (if (and r (not (vl-catch-all-error-p r)) (setq xd (cdr (assoc -3 r))))
    (progn
      (foreach a (cdr (car xd))
        (if (= (car a) 1070) (setq vals (cons (cdr a) vals))))
      (setq vals (reverse vals))
      (if (= (cadr vals) 1) 1 0))
    0)
)

(defun ktmau:dim-tstyle (ed / v ted)
  ;; ten textstyle cua dimstyle (340 = ename hoac handle)
  (setq v (kt:dxf 340 ed))
  (if (= (type v) 'STR) (setq v (handent v)))
  (if (and (= (type v) 'ENAME) (setq ted (entget v)) (kt:dxf 2 ted))
    (kt:dxf 2 ted)
    "Standard")
)

(defun ktmau:sec-dimstyle (used / d nm ed e ts res tss)
  ;; tra ve (rows . textstyles dung boi cac dimstyle duoc lay)
  (setq d (tblnext "DIMSTYLE" T))
  (while d
    (setq nm (kt:dxf 2 d))
    (if (and nm (/= nm "")
             (not (wcmatch nm "*|*"))
             (not (wcmatch nm "*`$#"))             ; kieu con "ISO-25$0" (khong bo xref bind "Xr$0$..")
             (or (null used) (member (strcase nm) used)))
      (progn
        (setq e  (tblobjname "DIMSTYLE" nm)
              ed (cond ((if e (entget e))) (d))
              ts (ktmau:dim-tstyle ed)
              tss (ktmau:adduniq ts tss))
        (setq res (cons (ktmau:row "DIMSTYLE"
                          (list nm
                                (cond ((kt:dxf 40 ed)) (1.0))
                                (cond ((kt:dxf 144 ed)) (1.0))
                                (cond ((kt:dxf 140 ed)) (2.5))
                                (cond ((kt:dxf 41 ed)) (2.5))
                                ts
                                (cond ((kt:dxf 271 ed)) (2))
                                (if e (ktmau:annot e) 0)))
                        res))))
    (setq d (tblnext "DIMSTYLE")))
  (cons (ktmau:sort-str res) tss)
)

;;; ---------- TEXTSTYLE ----------
(defun ktmau:sec-textstyle (used dimts / d nm ed res fonts f)
  ;; used = textstyle dang dung (nil = lay het); dimts = textstyle cua dimstyle
  ;; tra ve (rows . fonts)
  (setq d (tblnext "STYLE" T))
  (while d
    (setq nm (kt:dxf 2 d))
    (if (and nm (/= nm "")
             (= 0 (logand 1 (cond ((kt:dxf 70 d)) (0))))   ; bo shape file
             (not (wcmatch nm "*|*"))
             (or (null used) (member (strcase nm) used) (member (strcase nm) dimts)))
      (progn
        (setq ed (cond ((ktmau:tblent "STYLE" nm)) (d)))
        (foreach f (list (kt:dxf 3 ed) (kt:dxf 4 ed))
          (setq fonts (ktmau:adduniq f fonts)))
        (setq res (cons (ktmau:row "TEXTSTYLE"
                          (list nm
                                (cond ((kt:dxf 3 ed)) (""))
                                (cond ((kt:dxf 4 ed)) (""))
                                (cond ((kt:dxf 40 ed)) (0.0))
                                (cond ((kt:dxf 41 ed)) (1.0))))
                        res))))
    (setq d (tblnext "STYLE")))
  (cons (ktmau:sort-str res) (ktmau:sort-str fonts))
)

;;; ---------- KHUNG TEN ----------
(defun ktmau:fsize (en / b)
  ;; kich thuoc lon nhat cua vung khung (vien block, du phong hop bao)
  (if (setq b (kt:frame-box en))
    (max (- (car (cadr b)) (car (car b))) (- (cadr (cadr b)) (cadr (car b))))
    0.0)
)

(defun ktmau:khung-cands (/ raw spmax res nm key it sz nt sp r ed)
  ;; thong ke block co attribute (ca xref / block khong attribute cung dua vao, uu tien thap):
  ;; (KEY ten soluong kichthuoc-max sotag-max ename tyle-kichthuoc-max)
  ;; tyle-kichthuoc = kich thuoc / block lon nhat CUNG KHONG GIAN (khung o layout don vi giay
  ;; nho hon ky hieu o Model ve 1/100 -> khong so kich thuoc giua 2 khong gian)
  (foreach en (kt:ss-all '((0 . "INSERT") (66 . 1)))
    (setq nm (kt:effname en))
    (if (and nm (not (ktmau:xref-blk-p nm)))
      (setq ed (entget en)
            sp (kt:space ed)
            sz (ktmau:fsize en)
            raw (cons (list (strcase nm) nm sp sz (length (kt:attribs en)) en) raw)
            it (assoc sp spmax)
            spmax (if it
                    (subst (cons sp (max sz (cdr it))) it spmax)
                    (cons (cons sp sz) spmax)))))
  (foreach x raw
    (setq key (car x) nm (nth 1 x) sz (nth 3 x) nt (nth 4 x)
          r   (/ sz (max 1e-9 (cdr (assoc (nth 2 x) spmax))))
          it  (assoc key res))
    (if it
      (setq res (subst (list key (nth 1 it) (1+ (nth 2 it))
                             (max sz (nth 3 it)) (max nt (nth 4 it))
                             (if (> r (nth 6 it)) (nth 5 x) (nth 5 it))
                             (max r (nth 6 it)))
                       it res))
      (setq res (cons (list key nm 1 sz nt (nth 5 x) r) res))))
  res
)

(defun ktmau:khung-guess (cands / pool best)
  ;; khung ten = block co attribute LON NHAT trong khong gian cua no (>= 50%),
  ;; uu tien >= 3 tag; trong nhom chon block xuat hien nhieu nhat, roi nhieu tag hon
  ;; uu tien block co attribute ghi ty le doc duoc ("1:100") - khung ten that; ky hieu goi chi tiet
  ;; co hinh hoc lech xa diem chen (hop bao lon) khong lan at duoc khung
  (setq pool (vl-remove-if-not
               '(lambda (c) (and (>= (nth 4 c) 3) (vl-some '(lambda (a) (kt:parse-scale (cdr a)))
                                                          (kt:attribs (nth 5 c)))))
               cands))
  (if (null pool)
    (setq pool (vl-remove-if-not '(lambda (c) (and (>= (nth 4 c) 3) (>= (nth 6 c) 0.5))) cands)))
  (if (null pool) (setq pool (vl-remove-if-not '(lambda (c) (>= (nth 6 c) 0.5)) cands)))
  (foreach c pool
    (if (or (null best)
            (> (nth 2 c) (nth 2 best))
            (and (= (nth 2 c) (nth 2 best)) (> (nth 4 c) (nth 4 best)))
            (and (= (nth 2 c) (nth 2 best)) (= (nth 4 c) (nth 4 best)) (> (nth 6 c) (nth 6 best))))
      (setq best c)))
  best
)

(defun ktmau:ask-tag (label guess tags / s r ok)
  ;; Enter = giu goi y, "-" = khong co, hoac go ten tag
  (if (null guess) (setq guess ""))
  (while (not ok)
    (setq s (strcase (kt:trim (getstring (strcat "\n  Tag " label " <"
                                                  (if (= guess "") "-" guess) ">: ")))))
    (cond ((= s "") (setq r guess ok T))
          ((= s "-") (setq r "" ok T))
          ((member s tags) (setq r s ok T))
          (T (princ (strcat "\n  Khong co tag " s " trong khung. Go lai (Enter = giu, - = khong co).")))))
  r
)

(defun ktmau:pick-khung (/ cands guess sel ed blk en ok kw)
  ;; tra ve (ten-block ename) hoac nil
  (setq cands (ktmau:khung-cands)
        guess (ktmau:khung-guess cands))
  (while (not ok)
    (setq sel (entsel "\nChon 1 KHUNG TEN (block co attribute) tren ban ve <Enter = tu doan>: "))
    (cond
      (sel
       (setq ed (entget (car sel)))
       (cond
         ((and ed (= (kt:dxf 0 ed) "INSERT") (= (kt:dxf 66 ed) 1))
          (setq en (car sel) blk (kt:effname en) ok T))
         ((and ed (= (kt:dxf 0 ed) "INSERT"))
          ;; khung khong co attribute (chu thuong) / xref: van nhan dien duoc vung + ty le
          (setq en (car sel) blk (kt:effname en) ok T)
          (princ "\nBlock khong co attribute: chi nhan dien vung khung + ty le (khong doc so hieu/ten)."))
         (T (princ "\nDoi tuong chon khong phai block. Chon lai."))))
      ((null guess)
       (princ "\nKhong tim thay block co attribute nao -> bo qua muc KHUNG.")
       (setq blk nil ok T))
      (T
       (princ (strcat "\nTu doan khung ten: " (nth 1 guess) "  (" (itoa (nth 2 guess)) " ban, "
                      (itoa (nth 4 guess)) " tag, kich thuoc " (ktmau:fmt (nth 3 guess)) ")"))
       (initget "Co Khong Bo")
       (setq kw (getkword "\nDung block nay? [Co/Khong/Bo] (Bo = bo qua muc KHUNG) <Co>: "))
       (cond ((or (null kw) (= kw "Co")) (setq blk (nth 1 guess) en (nth 5 guess) ok T))
             ((= kw "Bo") (setq blk nil ok T))))))
  (if (and blk en) (list blk en))
)

(defun ktmau:sec-khung (/ pk blk en tags tSo tTen tTL f others g ed tsc sx fd g2 t2)
  ;; tra ve (block tagSo tagTen tagTL tylegoc (tag khac...)) hoac nil
  (if (setq pk (ktmau:pick-khung))
    (progn
      (setq blk (car pk) en (cadr pk) tags nil)
      (foreach a (kt:attribs en) (if (not (member (car a) tags)) (setq tags (cons (car a) tags))))
      (setq tags (reverse tags))
      (princ (strcat "\nKhung ten: " blk "\nCac tag: " (kt:join tags ", ")))
      (setq g    (ktmau:guess-tags (kt:attribs en))
            tSo  (nth 0 g) tTen (nth 1 g) tTL (nth 2 g))
      (princ "\nXac nhan tag (Enter = dong y goi y, - = khong co, hoac go ten tag):")
      (setq tSo  (ktmau:ask-tag "SO HIEU ban ve" tSo tags)
            tTen (ktmau:ask-tag "TEN ban ve" tTen tags)
            tTL  (ktmau:ask-tag "TY LE" tTL tags))
      ;; goi y he so goc = ty le ghi / scale X (khung o Model co ghi ty le)
      (setq ed  (entget en)
            sx  (abs (cond ((kt:dxf 41 ed)) (1.0)))
            tsc (if (/= tTL "") (kt:parse-scale (kt:attval en tTL)))
            fd  (if (and tsc (= (kt:space ed) "Model") (> sx 0))
                  (ktmau:rnd-scale (/ tsc sx)) 1))
      (princ "\n(Ty le goc: khung ve kich thuoc giay that, scale X block = ty le -> 1;")
      (princ "\n khung da ve san o 1/100 voi scale X = 1 -> 100. Khung o layout -> 1.)")
      (if (and tsc (= (kt:space ed) "Model"))
        (princ (strcat "\n Khung mau: scale X = " (ktmau:fmt sx) ", ghi ty le 1/" (ktmau:fmt tsc)
                       " -> goi y " (ktmau:fmt fd))))
      (initget 6)
      (setq f (getreal (strcat "\nTy le goc (he so nhan voi scale X block) <" (ktmau:fmt fd) ">: ")))
      (if (null f) (setq f fd))
      ;; dong 2 cua ten ban ve (vd TEN_BAN_VE "MAT BANG CONG NANG" + TEN_CONG_TRINH "TANG 1 & TANG 2"):
      ;; tag co gia tri THAY DOI giua cac khung (ten cong trinh that thi giong nhau o moi khung)
      (setq g2 (ktmau:guess-sub blk tags (list tSo tTen tTL)))
      (if (and g2 (/= tTen ""))
        (progn
          (setq t2 (ktmau:ask-tag "DONG 2 cua ten ban ve (noi sau tag ten, vd TANG 1)" g2 tags))
          (if (and (/= t2 "") (/= t2 tTen)) (setq tTen (strcat tTen "+" t2)))))
      (foreach tg tags
        (if (not (member tg (append (list tSo tTL) (kt:split tTen "+")))) (setq others (cons tg others))))
      (list blk tSo tTen tTL (float f) (reverse others))))
)

(defun ktmau:guess-sub (blk tags excl / best vals n nd)
  ;; tag (khac excl) co ten *TEN* va >= 2 gia tri khac nhau giua cac khung blk
  (foreach tg tags
    (if (and (not best) (not (member tg excl)) (wcmatch tg "*TEN*"))
      (progn
        (setq vals nil)
        (foreach en (kt:ss-all '((0 . "INSERT") (66 . 1)))
          (if (= (strcase (kt:str (kt:effname en))) (strcase blk))
            (progn
              (setq n (kt:attval en tg))
              (if (and n (/= n "") (not (member n vals))) (setq vals (cons n vals))))))
        (setq nd (length vals))
        (if (>= nd 2) (setq best tg)))))
  best
)

;;; ---------- Khung phu (to bia / khung cung kho giay) ----------
(defun ktmau:border-wh (nm / b)
  ;; (rong cao) vien khung cua block nm (kt:blk-border) ; nil neu khong co
  (if (setq b (kt:blk-border nm))
    (list (- (car (cadr b)) (car (car b))) (- (cadr (cadr b)) (cadr (car b))))))

(defun ktmau:extra-khungs (kh / mwh pw seen nm wh fac ok sx ed atts rows tg2 kw others)
  ;; block khac khung chinh, vien cung ti le canh va moi lan chen co ty le thuc tron (>= 1)
  ;; (to bia hang muc KHUNGT43, khung phoi canh KHUNGDIENNUOC...) -> hoi nguoi dung
  (if (and kh (setq mwh (ktmau:border-wh (car kh))) (> (cadr mwh) 0))
    (progn
      (setq pw (/ (car mwh) (nth 4 kh)))                 ; chieu rong giay (mm)
      (foreach en (kt:ss-all '((0 . "INSERT")))
        (setq nm (kt:effname en) ed (entget en))
        (if (and nm (= (kt:space ed) "Model") (/= (substr nm 1 1) "*")
                 (/= (strcase nm) (strcase (car kh))) (not (member (strcase nm) seen))
                 (not (ktmau:xref-blk-p nm)))
          (progn
            (setq seen (cons (strcase nm) seen) ok nil)
            (if (and (setq wh (ktmau:border-wh nm)) (> (cadr wh) 0)
                     (<= (abs (- (/ (/ (car wh) (cadr wh)) (/ (car mwh) (cadr mwh))) 1.0)) 0.01))
              (progn
                (setq fac (/ (car wh) pw) ok T)
                (if (equal fac (float (fix (+ fac 0.5))) 0.01) (setq fac (float (fix (+ fac 0.5)))))
                (foreach e2 (kt:ss-all (list '(0 . "INSERT") (cons 2 (kt:wcesc nm))))
                  (setq sx (* fac (abs (cond ((kt:dxf 41 (entget e2))) (1.0)))))
                  (if (or (< sx 0.99) (> (abs (- sx (fix (+ sx 0.5)))) 0.01)) (setq ok nil)))))
            (if ok
              (progn
                (setq atts (mapcar 'car (kt:attribs en)))
                (princ (strcat "\nKhung phu: " nm " (vien cung kho giay voi " (car kh) ", ty le goc "
                               (ktmau:fmt fac) (if atts (strcat ", tag: " (kt:join atts ",")) ", khong attribute") ")"))
                (initget "Co Khong")
                (setq kw (getkword "\nThem block nay vao muc KHUNG? [Co/Khong] <Co>: "))
                (if (/= kw "Khong")
                  (progn
                    (setq others nil
                          tg2 (if (and (/= (nth 1 kh) "") (member (nth 1 kh) atts)) T))
                    (if tg2
                      (foreach tg atts
                        (if (not (member tg (append (list (nth 1 kh) (nth 3 kh)) (kt:split (nth 2 kh) "+"))))
                          (setq others (cons tg others)))))
                    (setq rows (cons (if tg2
                                       (list nm (nth 1 kh) (nth 2 kh) (if (member (nth 3 kh) atts) (nth 3 kh) "")
                                             fac (reverse others))
                                       (list nm "" "" "" fac nil))
                                     rows)))))))))))
  (reverse rows)
)

(defun ktmau:frames (kh / raw res ed sp bx tsc sct v1 v2 agree disagree)
  ;; cac khung ten cua block kh: (ename space minpt maxpt scale sohieu ten)
  ;; scale: giong kt:frames - ty le thuc (|scale X| x he so goc), tru khi da so khung lech ty le ghi
  (setq agree 0 disagree 0)
  (if kh
    (foreach en (kt:ss-all '((0 . "INSERT")))
      (if (= (strcase (kt:str (kt:effname en))) (strcase (car kh)))
        (progn
          (setq ed  (entget en)
                sp  (kt:space ed)
                bx  (kt:frame-box en)
                tsc (if (/= (nth 3 kh) "") (kt:parse-scale (kt:attval en (nth 3 kh))))
                sct (* (abs (cond ((kt:dxf 41 ed)) (1.0))) (nth 4 kh))
                v1  (if (/= (nth 1 kh) "") (kt:attval en (nth 1 kh)))
                v2  (if (/= (nth 2 kh) "") (kt:attval en (nth 2 kh))))
          (if (and tsc (= sp "Model"))
            (if (equal tsc sct (* 0.01 tsc)) (setq agree (1+ agree)) (setq disagree (1+ disagree))))
          (if bx
            (setq raw (cons (list en sp (car bx) (cadr bx) sct
                                  (cond (v1) ("")) (cond (v2) ("")) tsc)
                            raw)))))))
  (foreach f raw
    (setq res (cons (list (nth 0 f) (nth 1 f) (nth 2 f) (nth 3 f)
                          (cond ((/= (nth 1 f) "Model") 1.0)
                                ((and (nth 7 f) (> disagree agree)) (nth 7 f))
                                (T (nth 4 f)))
                          (nth 5 f) (nth 6 f))
                    res)))
  res
)

(defun ktmau:frame-at (p sp frames / r)
  (foreach f frames
    (if (and (not r) (= (nth 1 f) sp) (kt:inbox p (nth 2 f) (nth 3 f)))
      (setq r f)))
  r
)

;;; ---------- BLOCK ky hieu ----------
(defun ktmau:blk-role (nm has-att / u)
  ;; ten co dau ("TR\\U+1EE4C" = TRUC, "M\\U+0110..." ) -> bo dau truoc khi so mau
  (setq u (kt:unaccent nm))
  (cond
    ((kt:wcmatch-any u '("*TRUC*" "*AXIS*" "*GRID*")) "TRUC")
    ((kt:wcmatch-any u '("*CAODO*" "*CAO*DO*" "*LEVEL*" "*ELEV*" "*COS*")) "CAODO")
    ((kt:wcmatch-any u '("*CHITIET*" "*CHI*TIET*" "*DETAIL*")) "CHITIET")
    ((kt:wcmatch-any u '("*MATCAT*" "*MAT*CAT*" "*SECTION*" "KH*CAT*" "*_CAT*" "CAT*" "*VET*CAT*")) "MATCAT")
    ;; "COT"/"CODE" = cot (cao do) hoac cot (cot nha) -> chi coi la cao do khi block co attribute
    ((and has-att (kt:wcmatch-any u '("*COT*" "*CODE*"))) "CAODO")
    ((kt:wcmatch-any u '("*CUA*" "*DOOR*" "*WINDOW*")) "CUA")
    (T "KHAC"))
)

(defun ktmau:lvlike (v)
  ;; gia tri attribute dang cao do: +3.600 -0.450 %%p0.000 0.000
  (and (= (type v) 'STR)
       (wcmatch (strcase (kt:trim v)) "[+-]#*.###,[+-] #*.###,%%P#*.###,0.000,[+-]#*,###"))
)

(defun ktmau:shlike (v sheets)
  ;; gia tri la so hieu ban ve co trong file (MC/02, KT-03)
  (and (= (type v) 'STR) (/= v "") (member (kt:norm v) sheets))
)

(defun ktmau:refpt (nm / segs ed pts a b len mx grp it singles p sol)
  ;; diem goc ky hieu cao do trong block = DINH TAM GIAC (nam tren vach cao do):
  ;; dinh cac SOLID (neu co), khong thi dau mut cac doan LINE/LWPOLYLINE ngan (< 1/2 doan dai nhat);
  ;; gom theo y: nhom chi co 1 diem = dinh nhon. Tra "x,y"; nil neu khong ro hoac dinh = diem chen.
  (foreach e (ktmau:blk-ents nm)
    (setq ed (entget e) pts nil)
    (cond ((= (kt:dxf 0 ed) "SOLID")
           (foreach c '(10 11 12 13)
             (if (and (kt:dxf c ed) (not (vl-member-if '(lambda (q) (equal q (kt:2d (kt:dxf c ed)) 1e-6)) sol)))
               (setq sol (cons (kt:2d (kt:dxf c ed)) sol)))))
          ((= (kt:dxf 0 ed) "LINE") (setq pts (list (kt:dxf 10 ed) (kt:dxf 11 ed))))
          ((= (kt:dxf 0 ed) "LWPOLYLINE")
           (foreach g ed (if (= (car g) 10) (setq pts (append pts (list (cdr g))))))))
    (while (cdr pts)
      (setq a (kt:2d (car pts)) b (kt:2d (cadr pts)) pts (cdr pts) len (distance a b)
            segs (cons (list len a b) segs) mx (max len (cond (mx) (0.0))))))
  (if (null sol)
    (foreach sg segs
      (if (< (car sg) (* 0.5 mx))
        (foreach q (cdr sg)
          (if (not (vl-member-if '(lambda (r) (equal r q 1e-6)) sol)) (setq sol (cons q sol)))))))
  (foreach q sol
    (if (setq it (vl-member-if '(lambda (g) (equal (car g) (cadr q) (* 0.01 (max 1.0 (cond (mx) (1.0)))))) grp))
      (setq grp (subst (cons (car (car it)) (cons q (cdr (car it)))) (car it) grp))
      (setq grp (cons (list (cadr q) q) grp))))
  (setq singles (vl-remove-if-not '(lambda (g) (null (cddr g))) grp))
  (if (and (= (length singles) 1) (cdr grp))
    (progn
      (setq p (cadr (car singles)))
      (if (not (equal p '(0.0 0.0) 1e-6))
        (strcat (ktmau:fmt (/ (fix (+ (* (car p) 100.0) (if (minusp (car p)) -0.5 0.5))) 100.0)) ","
                (ktmau:fmt (/ (fix (+ (* (cadr p) 100.0) (if (minusp (cadr p)) -0.5 0.5))) 100.0))))))
)

(defun ktmau:blk-maintag (role tags / r)
  (setq r (ktmau:first-match tags
            (cond ((= role "TRUC")  '("*TEN*" "*TRUC*" "*SO*" "*NAME*" "*NO*" "*AXIS*"))
                  ((= role "CAODO") '("*CAO*" "*COT*" "*LEVEL*" "*ELEV*" "*GIA*TRI*" "*VAL*"))
                  ((member role '("MATCAT" "CHITIET"))
                   '("*KY*HIEU*" "*KH*" "*TEN*" "*SO*" "*NO*" "*NAME*"))
                  ((= role "CUA")   '("*KY*HIEU*" "*KH*" "*MA*" "*TEN*" "*NAME*"))
                  (T nil))
            nil))
  (cond (r) ((car tags)) (""))
)

(defun ktmau:sec-block (kblks sheets / grp ed nm key it tags res role vals nlv nsh mt rt rp atts)
  ;; block dang duoc chen, co attribute hoac ten la ky hieu ->
  ;;   BLOCK|ten|vai tro|tag chinh|tag phu (so ban ve tham chieu)|diem goc x,y (CAODO)
  ;; kblks: ten block khung (HOA); sheets: so hieu ban ve (kt:norm) de nhan ky hieu tham chieu
  ;; grp: (KEY ten tags so-gia-tri gia-tri-cao-do gia-tri-so-hieu)
  (foreach en (kt:ss-all '((0 . "INSERT")))
    (setq ed (entget en) nm (kt:effname en))
    (if (and nm (/= nm "") (/= (substr nm 1 1) "*"))
      (progn
        (setq key (strcase nm) it (assoc key grp)
              atts (if (= (kt:dxf 66 ed) 1) (kt:attribs en)))
        (if (null it)
          (setq it (list key nm nil 0 0 0) grp (cons it grp)))
        (setq tags (cond ((nth 2 it)) ((mapcar 'car atts)))
              nlv (+ (nth 4 it) (if (vl-some '(lambda (a) (ktmau:lvlike (cdr a))) atts) 1 0))
              nsh (+ (nth 5 it) (if (vl-some '(lambda (a) (ktmau:shlike (cdr a) sheets)) atts) 1 0)))
        (setq grp (subst (list key nm tags (+ (nth 3 it) (if atts 1 0)) nlv nsh) it grp)))))
  (foreach g grp
    (setq nm (nth 1 g) tags (nth 2 g))
    (if (and (not (member (car g) kblks)) (not (ktmau:xref-blk-p nm)))
      (progn
        (if (null tags) (setq tags (ktmau:attdefs nm)))
        (setq role (if (or tags (/= (ktmau:blk-role nm nil) "KHAC")) (ktmau:blk-role nm (if tags T nil))))
        ;; vai tro theo gia tri: >= 80% lan chen co gia tri cao do -> CAODO; co so hieu ban ve -> MATCAT/CHITIET
        (if (and role (= role "KHAC") (> (nth 3 g) 0))
          (cond ((and (null (cdr tags)) (>= (nth 4 g) (* 0.8 (nth 3 g)))) (setq role "CAODO"))
                ((and (cdr tags) (>= (nth 5 g) (* 0.5 (nth 3 g)))) (setq role "MATCAT"))))
        (if role
          (progn
            (setq mt (ktmau:blk-maintag role tags)
                  rt (if (member role '("MATCAT" "CHITIET"))
                       (ktmau:first-match (vl-remove mt tags)
                                          '("*VITRI*" "*SO*BV*" "*BV*" "*BAN*VE*" "*SHEET*" "*KT*" "*") nil))
                  rp (if (= role "CAODO") (ktmau:refpt nm)))
            (setq res (cons (ktmau:row "BLOCK" (append (list nm role mt)
                                                       (cond (rp (list (cond (rt) ("")) rp)) (rt (list rt)))))
                            res)))))))
  (ktmau:sort-str res)
)

;;; ---------- LAYOUT ----------
(defun ktmau:layouts (/ r d ed nm lst)
  ;; ten layout theo THU TU TAB (DXF 71 cua LAYOUT); du phong layoutlist
  (if (setq d (dictsearch (namedobjdict) "ACAD_LAYOUT"))
    (foreach pr d
      (if (and (= (car pr) 350) (= (type (cdr pr)) 'ENAME) (setq ed (entget (cdr pr))))
        ;; ma 1 dau tien thuoc AcDbPlotSettings (ten page setup) -> lay sau (100 . "AcDbLayout")
        (progn
          (setq ed (cond ((member '(100 . "AcDbLayout") ed)) (ed)))
          (if (and (setq nm (kt:dxf 1 ed)) (/= nm "") (/= (strcase nm) "MODEL"))
            (setq lst (cons (list (cond ((kt:dxf 71 ed)) (0)) nm) lst)))))))
  (if lst
    (setq r (mapcar 'cadr (ktmau:msort (reverse lst) '(lambda (a b) (< (car a) (car b)))))))
  (if (and (null r) (ktmau:fnok layoutlist))
    (progn
      (setq r (vl-catch-all-apply 'layoutlist nil))
      (if (vl-catch-all-error-p r) (setq r nil))))
  (vl-remove-if '(lambda (x) (= (strcase x) "MODEL")) r)
)

;;; ---------- DANH MUC ----------
(defun ktmau:sec-danhmuc (frames / seen k lst res)
  (foreach f frames
    (if (or (/= (nth 5 f) "") (/= (nth 6 f) ""))
      (progn
        (setq k (strcat (strcase (nth 5 f)) "|" (strcase (nth 6 f))))
        (if (not (member k seen))
          (setq seen (cons k seen)
                lst  (cons (list (ktmau:natkey (nth 5 f)) (nth 5 f) (nth 6 f)) lst))))))
  (foreach x (ktmau:msort (reverse lst) '(lambda (a b) (< (car a) (car b))))
    (setq res (cons (ktmau:row "DANHMUC" (list (nth 1 x) (nth 2 x))) res)))
  (reverse res)
)

;;; ---------- Thong ke chieu cao chu + ty le ----------
(defun ktmau:rnd-scale (sc / r)
  (setq r (fix (+ sc 0.5)))
  (if (equal sc (float r) 0.01) r sc)
)

(defun ktmau:text-stats (frames stys / vps scales ed sp p h sc f cnt tot v it res)
  ;; tra ve (list chieu-cao-giay ty-le-tim-thay)
  (kt:reset-cache)
  (setq vps (ktmau:try 'kt:viewports nil))
  (foreach f frames
    (if (and (= (nth 1 f) "Model") (nth 4 f) (> (nth 4 f) 0))
      (setq scales (cons (ktmau:rnd-scale (nth 4 f)) scales))))
  (foreach v vps
    (if (and (nth 2 v) (> (nth 2 v) 0))
      (setq scales (cons (ktmau:rnd-scale (nth 2 v)) scales))))
  (setq tot 0)
  (foreach en (kt:ss-all '((0 . "TEXT,MTEXT") (-4 . "<NOT") (8 . "KT_CHECK") (-4 . "NOT>")))
    (setq ed (entget en)
          sp (kt:space ed)
          h  (kt:dxf 40 ed)
          p  (kt:dxf 10 ed)
          sc nil)
    (if (and h p (> h 0)
             ;; chi chu dung textstyle duoc chon (bo chu rac copy tu file khac)
             (or (null stys) (member (strcase (cond ((kt:dxf 7 ed)) ("STANDARD"))) stys))
             (not (and (= (kt:dxf 0 ed) "MTEXT") (vl-string-search "\\H" (kt:txt ed)))))
      (progn
        (setq p (kt:2d p))
        (cond
          ((/= sp "Model") (setq sc 1.0))
          ((setq f (ktmau:frame-at p sp frames)) (setq sc (nth 4 f)))
          (T (foreach v vps
               (if (and (not sc) (kt:inbox p (nth 3 v) (nth 4 v))) (setq sc (nth 2 v))))))
        (if (and sc (> sc 0))
          (progn
            ;; lam tron 0.05mm (0.1mm lam 0.75 -> 0.8, 1.25 -> 1.3: KTTEXT dung sai 3% se bao nham)
            (setq v (/ (fix (+ (* 20.0 (/ h sc)) 0.5)) 20.0))
            (if (> v 0)
              (progn
                (setq tot (1+ tot) it (assoc v cnt))
                (if it
                  (setq cnt (subst (cons v (1+ (cdr it))) it cnt))
                  (setq cnt (cons (cons v 1) cnt))))))))))
  ;; gia tri chiem > 5%, hoac >= 1% va >= 5 chu (ban ve mau lon: chu dien tich, ten do noi that...)
  (foreach c cnt
    (if (or (> (/ (float (cdr c)) (max tot 1)) 0.05)
            (and (>= (cdr c) 5) (>= (/ (float (cdr c)) (max tot 1)) 0.01)))
      (setq res (cons (car c) res))))
  (list (ktmau:sort-num res) scales)
)

(defun ktmau:ovr (en / x l r)
  ;; override dimstyle (XData ACAD DSTYLE) -> ((ma . gia tri) ...)
  (setq x (vl-catch-all-apply 'entget (list en '("ACAD"))))
  (if (not (vl-catch-all-error-p x))
    (setq l (cdr (assoc "ACAD" (cdr (assoc -3 x))))))
  (while (and l (/= (car (car l)) 1002)) (setq l (cdr l)))
  (setq l (cdr l))
  (while (and l (cdr l) (/= (car (car l)) 1002))
    (if (= (car (car l)) 1070) (setq r (cons (cons (cdr (car l)) (cdr (cadr l))) r)))
    (setq l (cddr l)))
  r
)

(defun ktmau:dim-stats (frames dstys / ed st ov ds tx f sc v cnt tot it res)
  ;; chieu cao chu dim quy ra giay (mm) = DIMTXT hieu dung x (DIMSCALE neu > 0, khong thi 1) / TL khung
  ;; chi dim dung dimstyle duoc chon; tra ve cac gia tri chiem >= 5%
  (setq tot 0)
  (foreach en (kt:ss-all '((0 . "DIMENSION")))
    (setq ed (entget en))
    (if (and (= (kt:space ed) "Model")
             (or (null dstys) (member (strcase (cond ((kt:dxf 3 ed)) (""))) dstys))
             (setq st (tblsearch "DIMSTYLE" (cond ((kt:dxf 3 ed)) ("STANDARD"))))
             (setq f (ktmau:frame-at (kt:2d (kt:dxf 10 ed)) "Model" frames))
             (setq sc (nth 4 f)) (> sc 0))
      (progn
        (setq ov (ktmau:ovr en)
              ds (cond ((cdr (assoc 40 ov))) ((kt:dxf 40 st)) (1.0))
              tx (cond ((cdr (assoc 140 ov))) ((kt:dxf 140 st)) (2.5))
              v  (/ (fix (+ (* 20.0 (/ (* tx (if (> ds 0) ds 1.0)) sc)) 0.5)) 20.0))
        (if (> v 0)
          (setq tot (1+ tot) it (assoc v cnt)
                cnt (if it (subst (cons v (1+ (cdr it))) it cnt) (cons (cons v 1) cnt)))))))
  (foreach c cnt
    (if (>= (/ (float (cdr c)) (max tot 1)) 0.05) (setq res (cons (car c) res))))
  (ktmau:sort-num res)
)

(defun ktmau:nojunk (lst)
  ;; bo ten rac: xref bind ("Xr...$0$...") - giu nguyen danh sach neu bo het
  (cond ((vl-remove-if '(lambda (x) (wcmatch x "*$0$*,*|*")) lst))
        (T lst))
)

(defun ktmau:uniq-num (lst / res)
  (foreach x lst
    (if (not (vl-member-if '(lambda (y) (equal x y 1e-6)) res))
      (setq res (cons x res))))
  (reverse res)
)

;;; ---------- SETTING ----------
(defun ktmau:sec-setting (heights scales fonts dhs / hs)
  (setq hs (if heights heights '(1.8 2.0 2.5 3.0 3.5 5.0))
        scales (ktmau:sort-num
                 (ktmau:uniq-num
                   (append (vl-remove-if-not '(lambda (x) (= (type x) 'INT)) scales)
                           '(1 2 5 10 20 25 50 75 100 150 200 250 500)))))
  (list
    "; CAO_CHU_GIAY: chieu cao chu IN TREN GIAY cho phep (mm) = chieu cao that / ty le."
    (strcat ";   " (if heights "Thong ke tu ban ve mau (lam tron 0.1mm, gia tri chiem >5%)."
                               "Khong thong ke duoc -> dung gia tri mac dinh."))
    (ktmau:row "SETTING" (list "CAO_CHU_GIAY" (kt:join (mapcar 'ktmau:fmt hs) ",")))
    "; CAO_CHU_DIM: chieu cao chu DIM tren giay (mm) = DIMTXT x (DIMSCALE neu > 0, khong thi 1) / TL khung."
    (if dhs
      (ktmau:row "SETTING" (list "CAO_CHU_DIM" (kt:join (mapcar 'ktmau:fmt dhs) ",")))
      ";   (khong thong ke duoc - KTDIM suy tu muc DIMSTYLE)")
    "; TY_LE_CHO_PHEP: mau so ty le duoc phep (100 = 1/100). Gom ty le tim thay + ty le thong dung."
    (ktmau:row "SETTING" (list "TY_LE_CHO_PHEP" (kt:join (mapcar 'ktmau:fmt scales) ",")))
    "; LAYER_MAU_BYLAYER: 1 = doi tuong bat buoc mau/linetype ByLayer, 0 = khong kiem."
    "SETTING|LAYER_MAU_BYLAYER|1"
    "; MAX_LOI_MOI_MA: so loi toi da ghi nhan cho moi ma loi (tranh treo may khi file qua ban)."
    "SETTING|MAX_LOI_MOI_MA|300"
    "; DUNG_SAI_KICH_THUOC: dung sai (mm) khi so khop kich thuoc / truc / cao do."
    "SETTING|DUNG_SAI_KICH_THUOC|1"
    "; LAYER_BO_QUA: layer khong kiem tra (wildcard, cach nhau dau phay)."
    ";   *|* = moi layer xref (KT_Core noi lai phan sau dau | cua gia tri SETTING)."
    "SETTING|LAYER_BO_QUA|DEFPOINTS,KT_CHECK,CHECK_DIM_OVERLAP,*|*"
    "; MAU_BYOBJ_BO_QUA: loai doi tuong duoc gan mau rieng (vd HATCH,DIM,TEXT). Bo ';' de dung."
    ";SETTING|MAU_BYOBJ_BO_QUA|HATCH"
    "; FONT_CHO_PHEP: file font (.shx/.ttf) duoc phep dung trong textstyle."
    (ktmau:row "SETTING" (list "FONT_CHO_PHEP" (kt:join fonts ","))))
)

;;; ---------- Ghi file ----------
(defun ktmau:copy (src dst / fi fo ln)
  (setq fi (open src "r"))
  (if fi
    (progn
      (setq fo (open dst "w"))
      (if fo
        (progn
          (while (setq ln (read-line fi)) (write-line ln fo))
          (close fo)))
      (close fi)
      (if fo T nil)))
)

(defun ktmau:bakname (f)
  (if (and (> (strlen f) 4) (= (strcase (substr f (- (strlen f) 3))) ".TXT"))
    (strcat (substr f 1 (- (strlen f) 4)) ".bak")
    (strcat f ".bak"))
)

(defun ktmau:write (f lines / fh bak)
  ;; sao luu file cu -> .bak, ghi file moi. T neu thanh cong
  (if (findfile f)
    (progn
      (setq bak (ktmau:bakname f))
      (if (ktmau:copy f bak)
        (princ (strcat "\nDa sao luu file cu: " bak))
        (progn
          (princ (strcat "\n[KTMAU] Khong sao luu duoc " bak))
          (initget "Co Khong")
          (if (/= (getkword "\nVan ghi de file chuan? [Co/Khong] <Khong>: ") "Co")
            (setq f nil))))))
  (if (and f (setq fh (open f "w")))
    (progn
      (foreach l lines (write-line l fh))
      (close fh)
      T))
)

(defun ktmau:header (/ d)
  (setq d (itoa (fix (getvar "CDATE"))))
  (if (>= (strlen d) 8)
    (setq d (strcat (substr d 1 4) "-" (substr d 5 2) "-" (substr d 7 2))))
  (list
    ";;; ============================================================"
    ";;; KT_ChuanCongTy.txt - CHUAN CONG TY cho bo kiem tra ban ve KT"
    (strcat ";;; Sinh boi lenh KTMAU ngay " d " tu ban ve: " (ktmau:ascii (getvar "DWGNAME")))
    ";;; Hay RA SOAT va sua tay neu can (Notepad, luu dang ANSI/ASCII)."
    ";;; ------------------------------------------------------------"
    ";;; Dinh dang: moi dong  MUC|truong1|truong2|...   ; dong bat dau ';' la ghi chu"
    ";;;   LAYER|ten|mau(1-255)|linetype|lineweight(1/100mm, -3=mac dinh)|plot(1/0)"
    ";;;   DIMSTYLE|ten|dimscale|dimlfac|dimtxt|dimasz|textstyle|dimdec|annotative(1/0)"
    ";;;   TEXTSTYLE|ten|font|bigfont|chieu cao co dinh(0=khong co dinh)|width factor"
    ";;;   KHUNG|ten block|tag so hieu|tag ten ban ve(+tag dong 2)|tag ty le|ty le goc (nhan voi scale X)|tag khac..."
    ";;;   BLOCK|ten block|vai tro (TRUC/CAODO/MATCAT/CHITIET/CUA/KHAC)|tag chinh|tag so ban ve tham chieu|diem goc x,y"
    ";;;   LAYOUT|ten layout"
    ";;;   DANHMUC|so hieu|ten ban ve"
    ";;;   SETTING|KHOA|gia tri"
    ";;; Ten lay tu ban ve giu nguyen nhu AutoLISP thay: ky tu thuoc codepage = 1 byte, ky tu ngoai"
    ";;; codepage = \\U+XXXX (vd TRUC co dau = TR\\U+1EE4C). Khong luu lai file bang UTF-8."
    ";;; ============================================================")
)

;;; ---------- Lenh chinh ----------
(defun c:KTMAU (/ *error* filt use rl rd rt kh khs frames rb ro rm st rs lines f ok n dst)
  (defun *error* (m)
    (if (not (wcmatch (strcase m) "*CANCEL*,*QUIT*,*EXIT*"))
      (princ (strcat "\n[KTMAU] Loi: " m))
      (princ "\n[KTMAU] Da huy, chua ghi file."))
    (princ))
  (cond
    ((not (ktmau:fnok kt:cfg-file))
     (princ "\n[KTMAU] Chua nap KT_Core.lsp. Hay nap KT_Load.lsp truoc."))
    (T
     (princ "\n=== KTMAU: trich chuan cong ty tu ban ve dang mo ===")
     (initget "Co Khong")
     (setq filt (/= (getkword "\nChi lay layer/dimstyle/textstyle DANG CO doi tuong (chuan sach)? [Co/Khong] <Co>: ")
                    "Khong"))
     (if filt
       (progn
         (princ "\nDang quet doi tuong dang dung...")
         (setq use (ktmau:try 'ktmau:scan-usage nil))
         ;; bo layer/dimstyle rac xref bind ("Xr QC$0$..."); textstyle cua dimstyle duoc giu van giu
         (if use (setq use (list (ktmau:nojunk (car use)) (ktmau:nojunk (cadr use))
                                 (ktmau:nojunk (caddr use)))))))
     ;; bang ky hieu
     (setq rl (ktmau:try 'ktmau:sec-layer (list (car use)))
           rd (ktmau:try 'ktmau:sec-dimstyle (list (cadr use)))
           rt (ktmau:try 'ktmau:sec-textstyle (list (caddr use) (cdr rd))))
     ;; khung ten (hoi nguoi dung)
     (setq kh (ktmau:try 'ktmau:sec-khung nil))
     ;; khung phu (to bia, khung cung kho giay khac ten) -> nhieu dong KHUNG
     (setq khs (if kh (cons kh (ktmau:try 'ktmau:extra-khungs (list kh)))))
     (foreach k khs (setq frames (append frames (ktmau:try 'ktmau:frames (list k)))))
     (princ "\nDang thu thap block, layout, danh muc, thong ke chu...")
     (setq dst (mapcar '(lambda (r) (strcase (car (kt:split (substr r 10) "|")))) (car rd)))
     (setq rb (ktmau:try 'ktmau:sec-block
                         (list (mapcar '(lambda (k) (strcase (car k))) khs)
                               (vl-remove "" (mapcar '(lambda (f) (kt:norm (nth 5 f))) frames))))
           ro (ktmau:try 'ktmau:layouts nil)
           rm (ktmau:try 'ktmau:sec-danhmuc (list frames))
           st (ktmau:try 'ktmau:text-stats
                         (list frames (if filt (mapcar '(lambda (r) (strcase (car (kt:split (substr r 11) "|")))) (car rt)))))
           rs (ktmau:try 'ktmau:sec-setting
                         (list (car st) (cadr st) (cdr rt) (ktmau:try 'ktmau:dim-stats (list frames dst)))))
     ;; ghep noi dung
     (setq lines
       (append
         (ktmau:header)
         (list "" "; ---------- SETTING ----------") rs
         (list "" "; ---------- LAYER: ten|mau|linetype|lineweight|plot ----------") rl
         (list "" "; ---------- DIMSTYLE: ten|dimscale|dimlfac|dimtxt|dimasz|textstyle|dimdec|annotative ----------")
         (car rd)
         (list "" "; ---------- TEXTSTYLE: ten|font|bigfont|cao co dinh|width ----------") (car rt)
         (list "" "; ---------- KHUNG: block|tag so hieu|tag ten|tag ty le|ty le goc|tag khac... ----------")
         (if khs
           (mapcar '(lambda (k) (ktmau:row "KHUNG" (append (list (nth 0 k) (nth 1 k) (nth 2 k) (nth 3 k) (nth 4 k))
                                                           (nth 5 k))))
                   khs)
           (list "; (chua xac dinh khung ten - hay them tay dong KHUNG|...)"))
         (list "" "; ---------- BLOCK: ten|vai tro|tag chinh  (KIEM TRA LAI vai tro) ----------") rb
         (list "" "; ---------- LAYOUT ----------")
         (mapcar '(lambda (x) (ktmau:row "LAYOUT" (list x))) ro)
         (list "" "; ---------- DANHMUC: so hieu|ten ban ve ----------") rm))
     (setq f (kt:cfg-file))
     (setq ok (ktmau:write f lines))
     (if ok
       (progn
         ;; nap lai chuan moi cho cac module
         (setq *KT:CFG* nil)
         (kt:reset-cache)
         (kt:cfg-load)
         (princ "\n=== KTMAU: hoan tat ===")
         (foreach x (list (list "LAYER" (length rl)) (list "DIMSTYLE" (length (car rd)))
                          (list "TEXTSTYLE" (length (car rt))) (list "KHUNG" (length khs))
                          (list "BLOCK" (length rb)) (list "LAYOUT" (length ro))
                          (list "DANHMUC" (length rm)))
           (princ (strcat "\n  " (car x) ": " (itoa (cadr x)))))
         (setq n (length frames))
         (if kh
           (princ (strcat "\n  Khung ten '" (car kh) "': tim thay " (itoa n) " ban; tag so="
                          (nth 1 kh) " ten=" (nth 2 kh) " tyle=" (nth 3 kh))))
         (princ (strcat "\n  CAO_CHU_GIAY: " (kt:cfg-val "CAO_CHU_GIAY" "")))
         (princ (strcat "\n  Loc doi tuong dang dung: " (if filt "Co" "Khong")))
         (princ (strcat "\nDa ghi: " f))
         (princ "\n>> HAY MO FILE TXT TREN DE RA SOAT (vai tro BLOCK, tag KHUNG, CAO_CHU_GIAY, DANHMUC)")
         (princ "\n>> Sua xong go KTCFG de nap lai."))
       (princ (strcat "\n[KTMAU] KHONG ghi duoc file " (kt:str f)
                      " (file dang mo / khong co quyen ghi?)")))))
  (princ)
)

(princ "\nKT_Template da nap. Lenh: KTMAU")
(princ)
