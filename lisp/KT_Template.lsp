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
  (member (type sym) '(SUBR USUBR EXRXSUBR))
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
             (not (vl-string-search "$" nm))       ; kieu con "ISO-25$0"
             (or (null used) (member (strcase nm) used)))
      (progn
        (setq e  (tblobjname "DIMSTYLE" nm)
              ed (cond ((and e (entget e))) (d))
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
(defun ktmau:khung-cands (/ res nm key it sz nt)
  ;; thong ke block co attribute: (KEY ten soluong kichthuoc-max sotag-max ename)
  (foreach en (kt:ss-all '((0 . "INSERT") (66 . 1)))
    (setq nm (kt:effname en))
    (if (and nm (not (ktmau:xref-blk-p nm)))
      (progn
        (setq key (strcase nm)
              sz  (kt:boxsize en)
              nt  (length (kt:attribs en))
              it  (assoc key res))
        (if it
          (setq res (subst (list key (nth 1 it) (1+ (nth 2 it))
                                 (max sz (nth 3 it)) (max nt (nth 4 it))
                                 (if (> sz (nth 3 it)) en (nth 5 it)))
                           it res))
          (setq res (cons (list key nm 1 sz nt en) res))))))
  res
)

(defun ktmau:khung-guess (cands / pool mx best)
  ;; uu tien block >= 3 tag; trong nhom co kich thuoc >= 50% lon nhat,
  ;; chon block xuat hien nhieu nhat (bang nhau -> lon hon)
  (setq pool (vl-remove-if-not '(lambda (c) (>= (nth 4 c) 3)) cands))
  (if (null pool) (setq pool cands))
  (setq mx 0.0)
  (foreach c pool (setq mx (max mx (nth 3 c))))
  (setq pool (vl-remove-if-not '(lambda (c) (>= (nth 3 c) (* 0.5 mx))) pool))
  (foreach c pool
    (if (or (null best)
            (> (nth 2 c) (nth 2 best))
            (and (= (nth 2 c) (nth 2 best)) (> (nth 3 c) (nth 3 best))))
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
       (if (and ed (= (kt:dxf 0 ed) "INSERT") (= (kt:dxf 66 ed) 1))
         (setq en (car sel) blk (kt:effname en) ok T)
         (princ "\nDoi tuong chon khong phai block co attribute. Chon lai.")))
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

(defun ktmau:sec-khung (/ pk blk en tags tSo tTen tTL f others)
  ;; tra ve (block tagSo tagTen tagTL tylegoc (tag khac...)) hoac nil
  (if (setq pk (ktmau:pick-khung))
    (progn
      (setq blk (car pk) en (cadr pk) tags nil)
      (foreach a (kt:attribs en) (if (not (member (car a) tags)) (setq tags (cons (car a) tags))))
      (setq tags (reverse tags))
      (princ (strcat "\nKhung ten: " blk "\nCac tag: " (kt:join tags ", ")))
      (setq tTen (ktmau:first-match tags '("*TEN*" "*TITLE*" "*NAME*") nil)
            tTL  (ktmau:first-match tags '("*TL*" "*TY*LE*" "*SCALE*") (list tTen))
            tSo  (ktmau:first-match tags '("*SO*" "*KH*" "*SH*" "*NO*" "*SHEET*") (list tTen tTL)))
      (princ "\nXac nhan tag (Enter = dong y goi y, - = khong co, hoac go ten tag):")
      (setq tSo  (ktmau:ask-tag "SO HIEU ban ve" tSo tags)
            tTen (ktmau:ask-tag "TEN ban ve" tTen tags)
            tTL  (ktmau:ask-tag "TY LE" tTL tags))
      (princ "\n(Neu khung ve kich thuoc giay that va scale X block = ty le thi nhap 1;")
      (princ "\n neu khung da ve san o 1/100 voi scale X = 1 thi nhap 100.)")
      (initget 6)
      (setq f (getreal "\nKhung ve o ty le 1:1 kich thuoc giay? (1 = scale X block la ty le) <1>: "))
      (if (null f) (setq f 1.0))
      (foreach tg tags
        (if (not (member tg (list tSo tTen tTL))) (setq others (cons tg others))))
      (list blk tSo tTen tTL (float f) (reverse others))))
)

(defun ktmau:frames (kh / res ed sp bx tsc sc v1 v2)
  ;; cac khung ten cua block kh: (ename space minpt maxpt scale sohieu ten)
  (if kh
    (foreach en (kt:ss-all '((0 . "INSERT") (66 . 1)))
      (if (= (strcase (kt:effname en)) (strcase (car kh)))
        (progn
          (setq ed  (entget en)
                sp  (kt:space ed)
                bx  (kt:box en)
                tsc (if (/= (nth 3 kh) "") (kt:parse-scale (kt:attval en (nth 3 kh))))
                sc  (cond ((/= sp "Model") 1.0)
                          (tsc)
                          (T (* (abs (cond ((kt:dxf 41 ed)) (1.0))) (nth 4 kh))))
                v1  (if (/= (nth 1 kh) "") (kt:attval en (nth 1 kh)))
                v2  (if (/= (nth 2 kh) "") (kt:attval en (nth 2 kh))))
          (if bx
            (setq res (cons (list en sp (car bx) (cadr bx) sc
                                  (cond (v1) ("")) (cond (v2) ("")))
                            res)))))))
  (reverse res)
)

(defun ktmau:frame-at (p sp frames / r)
  (foreach f frames
    (if (and (not r) (= (nth 1 f) sp) (kt:inbox p (nth 2 f) (nth 3 f)))
      (setq r f)))
  r
)

;;; ---------- BLOCK ky hieu ----------
(defun ktmau:blk-role (nm)
  (cond
    ((kt:wcmatch-any nm '("*TRUC*" "*AXIS*" "*GRID*")) "TRUC")
    ((kt:wcmatch-any nm '("*CAODO*" "*CAO*DO*" "*LEVEL*" "*ELEV*" "*COT*")) "CAODO")
    ((kt:wcmatch-any nm '("*CHITIET*" "*CHI*TIET*" "*DETAIL*")) "CHITIET")
    ((kt:wcmatch-any nm '("*MATCAT*" "*MAT*CAT*" "*CAT*" "*SECTION*" "*MAT*")) "MATCAT")
    ((kt:wcmatch-any nm '("*CUA*" "*DOOR*" "*WINDOW*")) "CUA")
    (T "KHAC"))
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

(defun ktmau:sec-block (kblk / grp ed nm key it tags res role)
  ;; block dang duoc chen, co attribute hoac ten la ky hieu -> BLOCK|ten|vai tro|tag chinh
  (foreach en (kt:ss-all '((0 . "INSERT")))
    (setq ed (entget en) nm (kt:effname en))
    (if (and nm (/= nm "") (/= (substr nm 1 1) "*"))
      (progn
        (setq key (strcase nm) it (assoc key grp))
        (cond
          ((and it (null (caddr it)) (= (kt:dxf 66 ed) 1))
           (setq grp (subst (list key nm (mapcar 'car (kt:attribs en))) it grp)))
          ((null it)
           (setq grp (cons (list key nm (if (= (kt:dxf 66 ed) 1) (mapcar 'car (kt:attribs en))))
                           grp)))))))
  (foreach g grp
    (setq nm (nth 1 g) tags (nth 2 g))
    (if (and (/= (car g) (strcase kblk)) (not (ktmau:xref-blk-p nm)))
      (progn
        (if (null tags) (setq tags (ktmau:attdefs nm)))
        (if (or tags
                (kt:wcmatch-any nm '("*TRUC*" "*AXIS*" "*COT*" "*CAODO*" "*LEVEL*" "*CAT*"
                                     "*SECTION*" "*CHITIET*" "*DETAIL*" "*MAT*")))
          (progn
            (setq role (ktmau:blk-role nm))
            (setq res (cons (ktmau:row "BLOCK" (list nm role (ktmau:blk-maintag role tags)))
                            res)))))))
  (ktmau:sort-str res)
)

;;; ---------- LAYOUT ----------
(defun ktmau:layouts (/ r d ed nm lst)
  (if (ktmau:fnok layoutlist)
    (setq r (vl-catch-all-apply 'layoutlist nil)))
  (if (or (null r) (vl-catch-all-error-p r))
    (progn
      (setq r nil)
      (if (setq d (dictsearch (namedobjdict) "ACAD_LAYOUT"))
        (foreach pr d
          (if (and (= (car pr) 350) (= (type (cdr pr)) 'ENAME) (setq ed (entget (cdr pr))))
            (if (and (setq nm (kt:dxf 1 ed)) (/= (strcase nm) "MODEL"))
              (setq lst (cons (list (cond ((kt:dxf 71 ed)) (0)) nm) lst))))))
      (setq r (mapcar 'cadr (ktmau:msort lst '(lambda (a b) (< (car a) (car b))))))))
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
  (foreach x (ktmau:msort (reverse lst) '(lambda (a b) (< (car a) (car b)))))
    (setq res (cons (ktmau:row "DANHMUC" (list (nth 1 x) (nth 2 x))) res)))
  (reverse res)
)

;;; ---------- Thong ke chieu cao chu + ty le ----------
(defun ktmau:rnd-scale (sc / r)
  (setq r (fix (+ sc 0.5)))
  (if (equal sc (float r) 0.01) r sc)
)

(defun ktmau:text-stats (frames / vps scales ed sp p h sc f cnt tot v it res)
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
  (foreach en (kt:ss-all '((0 . "TEXT,MTEXT")))
    (setq ed (entget en)
          sp (kt:space ed)
          h  (kt:dxf 40 ed)
          p  (kt:dxf 10 ed)
          sc nil)
    (if (and h p (> h 0))
      (progn
        (setq p (kt:2d p))
        (cond
          ((/= sp "Model") (setq sc 1.0))
          ((setq f (ktmau:frame-at p sp frames)) (setq sc (nth 4 f)))
          (T (foreach v vps
               (if (and (not sc) (kt:inbox p (nth 3 v) (nth 4 v))) (setq sc (nth 2 v))))))
        (if (and sc (> sc 0))
          (progn
            (setq v (/ (fix (+ (* 2.0 (/ h sc)) 0.5)) 2.0))
            (if (> v 0)
              (progn
                (setq tot (1+ tot) it (assoc v cnt))
                (if it
                  (setq cnt (subst (cons v (1+ (cdr it))) it cnt))
                  (setq cnt (cons (cons v 1) cnt))))))))))
  (foreach c cnt
    (if (> (/ (float (cdr c)) (max tot 1)) 0.05) (setq res (cons (car c) res))))
  (list (ktmau:sort-num res) scales)
)

(defun ktmau:uniq-num (lst / res)
  (foreach x lst
    (if (not (vl-member-if '(lambda (y) (equal x y 1e-6)) res))
      (setq res (cons x res))))
  (reverse res)
)

;;; ---------- SETTING ----------
(defun ktmau:sec-setting (heights scales fonts / hs)
  (setq hs (if heights heights '(1.8 2.0 2.5 3.0 3.5 5.0))
        scales (ktmau:sort-num
                 (ktmau:uniq-num
                   (append (vl-remove-if-not 'numberp scales)
                           '(1 2 5 10 20 25 50 75 100 150 200 250 500)))))
  (list
    "; CAO_CHU_GIAY: chieu cao chu IN TREN GIAY cho phep (mm) = chieu cao that / ty le."
    (strcat ";   " (if heights "Thong ke tu ban ve mau (lam tron 0.5mm, gia tri chiem >5%)."
                               "Khong thong ke duoc -> dung gia tri mac dinh."))
    (ktmau:row "SETTING" (list "CAO_CHU_GIAY" (kt:join (mapcar 'ktmau:fmt hs) ",")))
    "; TY_LE_CHO_PHEP: mau so ty le duoc phep (100 = 1/100). Gom ty le tim thay + ty le thong dung."
    (ktmau:row "SETTING" (list "TY_LE_CHO_PHEP" (kt:join (mapcar 'ktmau:fmt scales) ",")))
    "; LAYER_MAU_BYLAYER: 1 = doi tuong bat buoc mau/linetype ByLayer, 0 = khong kiem."
    "SETTING|LAYER_MAU_BYLAYER|1"
    "; MAX_LOI_MOI_MA: so loi toi da ghi nhan cho moi ma loi (tranh treo may khi file qua ban)."
    "SETTING|MAX_LOI_MOI_MA|300"
    "; DUNG_SAI_KICH_THUOC: dung sai (mm) khi so khop kich thuoc / truc / cao do."
    "SETTING|DUNG_SAI_KICH_THUOC|1"
    "; LAYER_BO_QUA: layer khong kiem tra (wildcard, cach nhau dau phay)."
    "SETTING|LAYER_BO_QUA|DEFPOINTS,KT_CHECK,*|*"
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
    ";;;   KHUNG|ten block|tag so hieu|tag ten ban ve|tag ty le|ty le goc (nhan voi scale X)|tag khac..."
    ";;;   BLOCK|ten block|vai tro (TRUC/CAODO/MATCAT/CHITIET/CUA/KHAC)|tag chinh"
    ";;;   LAYOUT|ten layout"
    ";;;   DANHMUC|so hieu|ten ban ve"
    ";;;   SETTING|KHOA|gia tri"
    ";;; Ten lay tu ban ve giu nguyen (co the co ky tu tieng Viet/\\U+XXXX)."
    ";;; ============================================================")
)

;;; ---------- Lenh chinh ----------
(defun c:KTMAU (/ *error* filt use rl rd rt kh frames rb ro rm st rs lines f ok n)
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
         (setq use (ktmau:try 'ktmau:scan-usage nil))))
     ;; bang ky hieu
     (setq rl (ktmau:try 'ktmau:sec-layer (list (car use)))
           rd (ktmau:try 'ktmau:sec-dimstyle (list (cadr use)))
           rt (ktmau:try 'ktmau:sec-textstyle (list (caddr use) (cdr rd))))
     ;; khung ten (hoi nguoi dung)
     (setq kh (ktmau:try 'ktmau:sec-khung nil))
     (if kh (setq frames (ktmau:try 'ktmau:frames (list kh))))
     (princ "\nDang thu thap block, layout, danh muc, thong ke chu...")
     (setq rb (ktmau:try 'ktmau:sec-block (list (if kh (car kh) "")))
           ro (ktmau:try 'ktmau:layouts nil)
           rm (ktmau:try 'ktmau:sec-danhmuc (list frames))
           st (ktmau:try 'ktmau:text-stats (list frames))
           rs (ktmau:try 'ktmau:sec-setting (list (car st) (cadr st) (cdr rt))))
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
         (if kh
           (list (ktmau:row "KHUNG" (append (list (nth 0 kh) (nth 1 kh) (nth 2 kh) (nth 3 kh) (nth 4 kh))
                                            (nth 5 kh))))
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
                          (list "TEXTSTYLE" (length (car rt))) (list "KHUNG" (if kh 1 0))
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
