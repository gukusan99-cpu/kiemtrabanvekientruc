;;; ============================================================
;;; KT_Dim.lsp  -  Module "DIM": kiem tra kich thuoc (DIMENSION)
;;; ------------------------------------------------------------
;;; Can KT_Core.lsp nap truoc.
;;; Lenh:
;;;   KTDIM    : kiem tra dim (pham vi: toan ban ve / vung cua so)
;;;   KTDIMSET : doi tam thoi cac SETTING cua module trong phien (khong ghi file)
;;; Ham cho KTALL: (ktdim:run)  - kiem tra tat ca dim, khong hoi
;;;
;;; Ma loi:
;;;   DIM-STYLE  (LOI)     dimstyle khong co trong muc DIMSTYLE chuan (1 dong/style)
;;;   DIM-TYLE   (LOI/CANHBAO) chieu cao chu dim QUY RA GIAY khong thuoc CAO_CHU_DIM:
;;;                        hp = DIMTXT hieu dung x (DIMSCALE neu > 0, khong thi 1) / TL khung (hoac viewport)
;;;                        DIMTXT hieu dung = chieu cao co dinh cua textstyle dim (neu > 0) > override > style.
;;;                        Lech <= 25% gia tri chuan gan nhat -> CANHBAO, hon -> LOI. Dung cho ca quy cach
;;;                        "DIMSCALE = TL" (1-100: dimscale 100, dimtxt 2) lan "DIMSCALE = 0, DIMTXT theo don vi
;;;                        ban ve" (DG 1-100 (200): dimscale 0, dimtxt 150). DIMSCALE 0 trong Model = 1.
;;;   DIM-LFAC   (LOI/CANHBAO) DIMLFAC hieu dung khac chuan cua style
;;;                        (CANHBAO neu 1/DIMLFAC = 2, 2.5, 4, 5, 10, 20: chi tiet phong to ghi de DIMLFAC
;;;                        thay vi dung dimstyle "x2/x4"; hoac DIMLFAC x TL khung thuoc TY_LE_CHO_PHEP)
;;;              (CANHBAO) 2 dim cung phuong chung diem chan nhung khac DIMLFAC (vd dim style x4 cua chi
;;;                        tiet phong to noi tiep dim thuong) -> 1 trong 2 hien sai so
;;;   DIM-GHIDE  (LOI/CANHBAO) chu dim bi ghi de (so sai / van ban)
;;;   DIM-LE     (CANHBAO) gia tri do le so voi boi so chan (bat diem sai)
;;;   DIM-ASSOC  (GOIY)    dim khong lien ket (mac dinh tat: KIEM_DIM_ASSOC|1)
;;;   DIM-OVR    (CANHBAO) override dimstyle (XData ACAD DSTYLE) khac style
;;;   DIM-NHO    (GOIY)    dim gia tri 0 hoac rat nho (<1)
;;;   DIM-TRUNG  (LOI)     2 dim trung hoan toan            (thuat toan CDO)
;;;   DIM-DUONG  (LOI)     2 dim thang hang, duong dim chong (thuat toan CDO)
;;;   DIM-CHU    (CANHBAO) chu 2 dim de len nhau             (thuat toan CDO)
;;;   DIM-CHUDIM (CANHBAO) chu dim de len duong dim khac     (thuat toan CDO)
;;;
;;; SETTING dung (KT_ChuanCongTy.txt, muc SETTING):
;;;   CAO_CHU_DIM (mm giay; khong co -> suy tu muc DIMSTYLE: dimtxt neu dimscale > 0,
;;;   dimtxt / TL trong ten "1-100" neu dimscale = 0; khong suy duoc -> CAO_CHU_GIAY)
;;;   DIM_DUNG_SAI_TL (0.1)  DIM_HO_CHU (0.0)  DIM_BUOC_CHAN (1)
;;;   DIM_LECH_LE (0.05)  DUNG_SAI_KICH_THUOC (1)  KIEM_DIM_ASSOC (0)  TY_LE_CHO_PHEP
;;;   LAYER_BO_QUA (dim tren cac layer nay bo qua)
;;;
;;; Gia dinh: ban ve 2D, dim trong WCS, don vi mm.
;;; ============================================================

; lisplint: extern kt:cfg-keys kt:ukey kt:msort kt:parse-scale
;;; lisplint: extern kt:cfg-ok kt:begin kt:add kt:finish kt:cfg kt:cfg-row kt:cfg-names kt:cfg-num kt:cfg-list kt:ss-all kt:ss->list kt:dxf kt:2d kt:space kt:scale-at kt:viewports kt:trim kt:num kt:wcmatch-any kt:join kt:inbox

(vl-load-com)

;;; ---------- Tham so (doc tu SETTING moi lan chay) ----------
(defun ktdim:params ()
  (setq *KT:DIM-TOLR*  (kt:cfg-num "DIM_DUNG_SAI_TL" 0.1)
        *KT:DIM-GAPR*  (kt:cfg-num "DIM_HO_CHU" 0.0)
        *KT:DIM-STEP*  (kt:cfg-num "DIM_BUOC_CHAN" 1.0)
        *KT:DIM-LECH*  (kt:cfg-num "DIM_LECH_LE" 0.05)
        *KT:DIM-TOL*   (kt:cfg-num "DUNG_SAI_KICH_THUOC" 1.0)
        *KT:DIM-ASSOC* (= (fix (kt:cfg-num "KIEM_DIM_ASSOC" 0)) 1)
        *KT:DIM-SKIP*  (kt:cfg-list "LAYER_BO_QUA")
        *KT:DIM-CFGSTY* (kt:cfg-keys "DIMSTYLE")
        *KT:DIM-TLCP*  (vl-remove-if '(lambda (x) (or (null x) (<= x 0)))
                                       (mapcar 'kt:num (kt:cfg-list "TY_LE_CHO_PHEP")))
        *KT:DIM-HS*    (ktdim:std-heights)
        *KT:DIM-STY*   nil
        *KT:DIM-BADSTY* nil
        *KT:DIM-LFL*   nil
        *KT:DIM-SCERR* nil)
  (if (<= *KT:DIM-STEP* 0) (setq *KT:DIM-STEP* 1.0))
  (if (< *KT:DIM-TOLR* 0) (setq *KT:DIM-TOLR* 0.1))
  (if (< *KT:DIM-GAPR* 0) (setq *KT:DIM-GAPR* 0.0))
  T
)

;;; ---------- Chieu cao chu dim chuan (mm giay) ----------
(defun ktdim:namescale (nm)
  ;; ty le ghi trong ten dimstyle: "DG 1-30 (60) x4" -> 30, "JFP_DG 1- 20" -> 20, "1-100" -> 100
  (kt:parse-scale (vl-string-translate "-" "/" (kt:str nm)))
)

(defun ktdim:std-heights (/ res ds tx ns h)
  ;; SETTING CAO_CHU_DIM, khong co thi suy tu cac dong DIMSTYLE chuan, cuoi cung CAO_CHU_GIAY
  (setq res (vl-remove-if '(lambda (x) (or (null x) (<= x 0)))
                          (mapcar 'kt:num (kt:cfg-list "CAO_CHU_DIM"))))
  (if (null res)
    (foreach r (kt:cfg "DIMSTYLE")
      (setq ds (kt:num (nth 1 r)) tx (kt:num (nth 3 r)) ns (ktdim:namescale (car r)) h nil)
      (cond ((and ds tx (> ds 0)) (setq h tx))
            ((and tx ns (> tx 0)) (setq h (/ tx ns))))
      (if (and h (> h 0) (not (vl-member-if '(lambda (x) (equal x h 1e-6)) res)))
        (setq res (cons h res)))))
  (if (null res)
    (setq res (vl-remove-if '(lambda (x) (or (null x) (<= x 0)))
                            (mapcar 'kt:num (kt:cfg-list "CAO_CHU_GIAY")))))
  res
)

(defun ktdim:hdev (hp / best d)
  ;; do lech tuong doi nho nhat cua hp so voi *KT:DIM-HS* (0 = khop)
  (foreach h *KT:DIM-HS*
    (setq d (/ (abs (- hp h)) h))
    (if (or (null best) (< d best)) (setq best d)))
  (cond ((null best) nil) ((<= best 0.03) 0.0) (T best))
)

(defun ktdim:tsheight (v / ted)
  ;; chieu cao co dinh cua textstyle (340 = ename/handle), 0 neu khong co
  (if (= (type v) 'STR) (setq v (vl-catch-all-apply 'handent (list v))))
  (if (and (= (type v) 'ENAME) (setq ted (entget v)) (numberp (kt:dxf 40 ted)))
    (kt:dxf 40 ted)
    0.0)
)

;;; ---------- Tien ich so ----------
(defun ktdim:roundto (x step / q i f)
  ;; lam tron x ve boi so gan nhat cua step (khong dung fix -> khong tran so)
  (setq q (/ x step)
        f (rem q 1.0)
        i (- q f))
  (cond ((>= f 0.5) (setq i (+ i 1.0)))
        ((<= f -0.5) (setq i (- i 1.0))))
  (* i step)
)

(defun ktdim:fmt2 (x / s)
  ;; so -> chuoi toi da 2 so le, bo 0 cuoi: 1.50 -> "1.5", 2.0 -> "2", 1.714 -> "1.71"
  (setq s (rtos x 2 2))
  (if (vl-string-search "." s)
    (setq s (vl-string-right-trim "." (vl-string-right-trim "0" s))))
  s
)

(defun ktdim:fmt (x)
  ;; so -> chuoi gon: 50.0 -> "50", 12.5 -> "12.500"
  (if (equal x (ktdim:roundto x 1.0) 1e-6)
    (rtos x 2 0)
    (rtos x 2 3))
)

(defun ktdim:neq (a b)
  ;; 2 so khac nhau (sai so tuong doi 1e-6)
  (and a b (> (abs (- a b)) (* 1e-6 (max 1.0 (abs a) (abs b)))))
)

;;; ---------- Sap xep (merge sort tu viet, khong phu thuoc vl-sort) ----------
;;; lst: list (khoa . gia tri), sap tang theo khoa so
(defun ktdim:merge (a b / res)
  (while (and a b)
    (if (<= (car (car a)) (car (car b)))
      (setq res (cons (car a) res) a (cdr a))
      (setq res (cons (car b) res) b (cdr b))))
  (append (reverse res) a b)
)

(defun ktdim:msort (lst / runs nxt)
  (setq runs (mapcar 'list lst))
  (while (cdr runs)
    (setq nxt nil)
    (while runs
      (if (cdr runs)
        (setq nxt  (cons (ktdim:merge (car runs) (cadr runs)) nxt)
              runs (cddr runs))
        (setq nxt  (cons (car runs) nxt)
              runs nil)))
    (setq runs (reverse nxt)))
  (car runs)
)

;;; ---------- XData ----------
(defun ktdim:xapp (ed app)
  ;; noi dung XData cua ung dung app (bo ten app), nil neu khong co
  (cdr (assoc app (cdr (assoc -3 ed))))
)

(defun ktdim:dstyle (xd / on res)
  ;; XData ACAD -> ((ma . gia tri) ...) cua nhom DSTYLE
  (while xd
    (cond
      ((and (null on) (equal (car xd) '(1000 . "DSTYLE"))) (setq on 1))
      ((and (= on 1) (equal (car xd) '(1002 . "{"))) (setq on 2))
      ((and (= on 2) (equal (car xd) '(1002 . "}"))) (setq on nil xd nil))
      ((and (= on 2) (= (car (car xd)) 1070) (cadr xd))
       (setq res (cons (cons (cdr (car xd)) (cdr (cadr xd))) res)
             xd  (cdr xd))))
    (setq xd (cdr xd)))
  res
)

(defun ktdim:annop (xd / on vals)
  ;; XData AcadAnnotative: (1000 . "AnnotativeData") { 1070 ver, 1070 flag } -> T neu flag = 1
  (while xd
    (cond
      ((equal (car xd) '(1000 . "AnnotativeData")) (setq on T))
      ((and on (equal (car xd) '(1002 . "}"))) (setq on nil xd nil))
      ((and on (= (car (car xd)) 1070)) (setq vals (cons (cdr (car xd)) vals))))
    (setq xd (cdr xd)))
  (setq vals (reverse vals))
  (and (cadr vals) (= (cadr vals) 1))
)

;;; ---------- Thong tin dimstyle (cache theo ten) ----------
;;; -> (row ds lf dec txt asz anno tsh nsc)   row = dong DIMSTYLE chuan (nil neu khong co)
;;;    tsh = chieu cao co dinh textstyle dim (0 = khong), nsc = TL trong ten style
(defun ktdim:style (nm / key c te ed row dec anno res)
  (setq key (strcase nm))
  (if (setq c (assoc key *KT:DIM-STY*))
    (cdr c)
    (progn
      (setq te  (tblobjname "DIMSTYLE" nm)
            ed  (if te (entget te '("AcadAnnotative")))
            row (kt:cfg-row "DIMSTYLE" nm)
            dec (cond ((kt:dxf 271 ed))
                      ((and row (kt:num (nth 6 row))) (fix (kt:num (nth 6 row))))
                      (T 0))
            anno (or (and row (kt:num (nth 7 row)) (= (fix (kt:num (nth 7 row))) 1))
                     (ktdim:annop (ktdim:xapp ed "AcadAnnotative"))))
      (setq res (list row
                      (cond ((kt:dxf 40 ed)) (1.0))
                      (cond ((kt:dxf 144 ed)) (1.0))
                      dec
                      (kt:dxf 140 ed)
                      (kt:dxf 41 ed)
                      anno
                      (if ed (ktdim:tsheight (kt:dxf 340 ed)) 0.0)
                      (ktdim:namescale nm)))
      (setq *KT:DIM-STY* (cons (cons key res) *KT:DIM-STY*))
      res))
)

(defun ktdim:eff (ovr code def / c)
  ;; gia tri hieu dung: override neu co, khong thi def
  (if (setq c (assoc code ovr)) (cdr c) def)
)

;;; ---------- Chu ghi de ----------
(defun ktdim:plain (s / i n c d res p)
  ;; bo ma dinh dang MTEXT co ban: {} \A1; \H2.5; \P \L ...
  (setq i 1 n (strlen s) res "")
  (while (<= i n)
    (setq c (substr s i 1))
    (cond
      ((member c '("{" "}")) (setq i (1+ i)))
      ((and (= c "\\") (< i n))
       (setq d (substr s (1+ i) 1))
       (cond
         ((member d '("\\" "{" "}")) (setq res (strcat res d) i (+ i 2)))
         ((member d '("P" "X" "~")) (setq res (strcat res " ") i (+ i 2)))
         ((member d '("L" "l" "O" "o" "K" "k")) (setq i (+ i 2)))
         ((member d '("A" "C" "F" "f" "H" "Q" "T" "W" "S" "p"))
          (if (setq p (vl-string-search ";" s i))
            (setq i (+ p 2))
            (setq i (1+ n))))
         (T (setq res (strcat res c) i (1+ i)))))
      (T (setq res (strcat res c) i (1+ i)))))
  (kt:trim res)
)

(defun ktdim:numstr-p (s / i ok dig c)
  ;; chuoi chi gom chu so, dau cham, dau +/- va co it nhat 1 chu so
  (setq i 1 ok T)
  (while (and ok (<= i (strlen s)))
    (setq c (substr s i 1) i (1+ i))
    (cond ((member c '("0" "1" "2" "3" "4" "5" "6" "7" "8" "9")) (setq dig T))
          ((member c '("." "+" "-")) nil)
          (T (setq ok nil))))
  (and ok dig)
)

(defun ktdim:txtnum (s typ / u)
  ;; chu -> so neu la so thuan (cho phep tien to R / %%C voi dim ban kinh / duong kinh)
  (setq u (strcase s))
  (if (member typ '(3 4))
    (cond ((= (substr u 1 3) "%%C") (setq s (substr s 4)))
          ((= (substr u 1 1) "R") (setq s (substr s 2)))))
  (setq s (kt:trim s))
  (if (ktdim:numstr-p s)
    (kt:num s))
)

;;; ---------- Lien ket (DIMASSOC) ----------
(defun ktdim:assocp (ed / on ok o)
  (foreach g ed
    (cond
      ((equal g '(102 . "{ACAD_REACTORS")) (setq on T))
      ((and on (= (car g) 102)) (setq on nil))
      ((and on (= (car g) 330) (not ok))
       (if (and (setq o (entget (cdr g))) (= (kt:dxf 0 o) "DIMASSOC"))
         (setq ok T)))))
  ok
)

;;; ---------- Ty le tai diem (bao ve loi trong loi) ----------
(defun ktdim:scale (pt sp / r)
  (setq r (vl-catch-all-apply 'kt:scale-at (list pt sp)))
  (if (vl-catch-all-error-p r)
    (progn (setq *KT:DIM-SCERR* (vl-catch-all-error-message r)) nil)
    r)
)

(defun ktdim:vp-scale-p (lf sp / ok vps)
  ;; lf trung ty le 1 viewport tren layout sp (dim do xuyen viewport)
  (setq vps (vl-catch-all-apply 'kt:viewports nil))
  (if (vl-catch-all-error-p vps) (setq vps nil))
  (foreach v vps
    (if (and (listp v) (= (nth 1 v) sp) (numberp (nth 2 v))
             (< (abs (- lf (nth 2 v))) (* 0.01 (nth 2 v))))
      (setq ok T)))
  ok
)

;;; 2 ty le "bang nhau" (lech < 1%)
(defun ktdim:sceq (a b)
  (and (numberp a) (numberp b) (> b 0) (< (abs (- a b)) (* 0.01 b)))
)

(defun ktdim:vp-at (p / res vps)
  ;; ty le cac viewport (moi layout) nhin thay diem model p
  (setq vps (vl-catch-all-apply 'kt:viewports nil))
  (if (vl-catch-all-error-p vps) (setq vps nil))
  (foreach v vps
    (if (and (listp v) (numberp (nth 2 v)) (nth 3 v) (nth 4 v)
             (kt:inbox p (nth 3 v) (nth 4 v)))
      (setq res (cons (nth 2 v) res))))
  res
)

(defun ktdim:allowed-p (x / ok)
  ;; x thuoc TY_LE_CHO_PHEP
  (foreach c *KT:DIM-TLCP* (if (ktdim:sceq x c) (setq ok T)))
  ok
)

(defun ktdim:intstep-p (x)
  ;; x gan so nguyen >= 1
  (and (>= x 0.999) (< (abs (- x (ktdim:roundto x 1.0))) 1e-6))
)

;;; ============================================================
;;; Hinh hoc chong lan - sao chep tu CheckDimOverlap (CDO), doi prefix
;;; *CDO:TOLR* -> *KT:DIM-TOLR*, *CDO:GAPR* -> *KT:DIM-GAPR*
;;; ============================================================
(defun ktdim:2d (p) (list (float (car p)) (float (cadr p))))
(defun ktdim:v+ (a b) (list (+ (car a) (car b)) (+ (cadr a) (cadr b))))
(defun ktdim:v- (a b) (list (- (car a) (car b)) (- (cadr a) (cadr b))))
(defun ktdim:v* (a s) (list (* (car a) s) (* (cadr a) s)))
(defun ktdim:dot (a b) (+ (* (car a) (car b)) (* (cadr a) (cadr b))))
(defun ktdim:perp (v) (list (- (cadr v)) (car v)))
(defun ktdim:unit (v / l)
  (setq l (distance '(0.0 0.0) v))
  (if (> l 1e-12) (list (/ (car v) l) (/ (cadr v) l)) '(1.0 0.0))
)
(defun ktdim:mid (a b) (ktdim:v* (ktdim:v+ a b) 0.5))
(defun ktdim:cen (pts)
  (list (/ (apply '+ (mapcar 'car pts)) (length pts))
        (/ (apply '+ (mapcar 'cadr pts)) (length pts)))
)
(defun ktdim:aabb (pts / xs ys)
  (setq xs (mapcar 'car pts) ys (mapcar 'cadr pts))
  (list (apply 'min xs) (apply 'min ys) (apply 'max xs) (apply 'max ys))
)
(defun ktdim:peq (a b tol)
  (or (and (null a) (null b))
      (and a b (< (distance (ktdim:2d a) (ktdim:2d b)) tol)))
)

;;; Tim chu (MTEXT/TEXT) trong block cua dim
(defun ktdim:dimtext (en / blk e ed res)
  (setq blk (cdr (assoc 2 (entget en))))
  (if (and blk (setq e (tblobjname "BLOCK" blk)))
    (progn
      (setq e (entnext e))
      (while (and e (not res))
        (setq ed (entget e))
        (cond ((= (cdr (assoc 0 ed)) "ENDBLK") (setq e nil))
              ((member (cdr (assoc 0 ed)) '("MTEXT" "TEXT")) (setq res ed)))
        (if e (setq e (entnext e))))))
  res
)

;;; Khung chu nhat xoay: (pts u v h)
(defun ktdim:mkquad (bl u v w h / g)
  (setq g  (* *KT:DIM-GAPR* h)
        bl (ktdim:v- bl (ktdim:v+ (ktdim:v* u g) (ktdim:v* v g))))
  (list (list bl
              (ktdim:v+ bl (ktdim:v* u (+ w g g)))
              (ktdim:v+ (ktdim:v+ bl (ktdim:v* u (+ w g g))) (ktdim:v* v (+ h g g)))
              (ktdim:v+ bl (ktdim:v* v (+ h g g))))
        u v h)
)

(defun ktdim:textquad (ed / typ ins w h u v a col row bl ang tb)
  (setq typ (cdr (assoc 0 ed)))
  (cond
    ((= typ "MTEXT")
     ;; 42/43 (khung chu thuc) AutoCAD luon ghi; DXF tu phan mem khac co the thieu -> uoc luong
     (setq ins (ktdim:2d (cdr (assoc 10 ed)))
           h   (cond ((cdr (assoc 43 ed))) ((cdr (assoc 40 ed))))
           w   (cond ((cdr (assoc 42 ed)))
                     ((numberp h) (* 0.75 h (max 1 (strlen (ktdim:plain (cond ((cdr (assoc 1 ed))) (""))))))))
           a   (cond ((cdr (assoc 71 ed))) (5)))
     (setq u (cond ((assoc 11 ed) (ktdim:unit (ktdim:2d (cdr (assoc 11 ed)))))
                   ((assoc 50 ed) (list (cos (cdr (assoc 50 ed))) (sin (cdr (assoc 50 ed)))))
                   (T '(1.0 0.0))))
     (if (and w h a (> w 0) (> h 0))
       (progn
         (setq v   (ktdim:perp u)
               col (rem (1- a) 3)
               row (/ (1- a) 3)
               bl  (ktdim:v- (ktdim:v- ins (ktdim:v* u (* col w 0.5)))
                             (ktdim:v* v (* (- 2 row) h 0.5))))
         (ktdim:mkquad bl u v w h))))
    ((= typ "TEXT")
     (if (setq tb (textbox ed))
       (progn
         (setq ins (ktdim:2d (cdr (assoc 10 ed)))
               ang (cond ((cdr (assoc 50 ed))) (0.0))
               u   (list (cos ang) (sin ang))
               v   (ktdim:perp u)
               w   (- (car (cadr tb)) (car (car tb)))
               h   (- (cadr (cadr tb)) (cadr (car tb)))
               bl  (ktdim:v+ ins (ktdim:v+ (ktdim:v* u (car (car tb))) (ktdim:v* v (cadr (car tb))))))
         (if (and (> w 0) (> h 0)) (ktdim:mkquad bl u v w h))))))
)

;;; Duong dim (chi dim thang: rotated / aligned) -> (e1 e2 u)
(defun ktdim:dimline (ed / typ p10 p13 p14 ang u e1 e2)
  (setq typ (logand (cdr (assoc 70 ed)) 7))
  (if (member typ '(0 1))
    (progn
      (setq p10 (ktdim:2d (cdr (assoc 10 ed)))
            p13 (ktdim:2d (cdr (assoc 13 ed)))
            p14 (ktdim:2d (cdr (assoc 14 ed))))
      (setq u (if (= typ 0)
                (progn (setq ang (cond ((cdr (assoc 50 ed))) (0.0)))
                       (list (cos ang) (sin ang)))
                (if (> (distance p13 p14) 1e-9) (ktdim:unit (ktdim:v- p14 p13)))))
      (if u
        (progn
          (setq e1 (ktdim:v+ p10 (ktdim:v* u (ktdim:dot (ktdim:v- p13 p10) u)))
                e2 (ktdim:v+ p10 (ktdim:v* u (ktdim:dot (ktdim:v- p14 p10) u))))
          (if (> (distance e1 e2) 1e-9) (list e1 e2 u))))))
)

;;; Ban ghi 1 dim: (ename ed textquad h line aabb)
(defun ktdim:record (en / ed td tq h ln pts)
  (setq ed (entget en))
  (if (setq td (ktdim:dimtext en)) (setq tq (ktdim:textquad td)))
  (setq h  (if tq (nth 3 tq) 0.0)
        tq (if tq (list (car tq) (cadr tq) (caddr tq))))
  (setq ln (ktdim:dimline ed))
  (setq pts (append (if tq (car tq))
                    (if ln (list (car ln) (cadr ln)))
                    (list (ktdim:2d (cdr (assoc 10 ed))))))
  (list en ed tq h ln (ktdim:aabb pts))
)

;;; Separating Axis Theorem
(defun ktdim:proj (pts ax / d)
  (setq d (mapcar '(lambda (p) (ktdim:dot p ax)) pts))
  (list (apply 'min d) (apply 'max d))
)
(defun ktdim:sat (p1 a1 p2 a2 tol / ok r1 r2)
  (setq ok T)
  (foreach ax (append a1 a2)
    (if ok
      (progn
        (setq r1 (ktdim:proj p1 ax) r2 (ktdim:proj p2 ax))
        (if (<= (- (min (cadr r1) (cadr r2)) (max (car r1) (car r2))) tol)
          (setq ok nil)))))
  ok
)

;;; 2 duong dim thang hang & chong nhau -> (diem giua doan chong, nua chieu dai) / nil
(defun ktdim:lineover (l1 l2 tol / u1 u2 o s2 s3 s4 lo hi)
  (setq u1 (caddr l1) u2 (caddr l2) o (car l1))
  (if (and (< (abs (- (* (car u1) (cadr u2)) (* (cadr u1) (car u2)))) 1e-6)
           (< (abs (ktdim:dot (ktdim:v- (car l2) o) (ktdim:perp u1))) tol))
    (progn
      (setq s2 (ktdim:dot (ktdim:v- (cadr l1) o) u1)
            s3 (ktdim:dot (ktdim:v- (car l2) o) u1)
            s4 (ktdim:dot (ktdim:v- (cadr l2) o) u1)
            lo (max (min 0.0 s2) (min s3 s4))
            hi (min (max 0.0 s2) (max s3 s4)))
      (if (> (- hi lo) tol)
        (list (ktdim:v+ o (ktdim:v* u1 (* 0.5 (+ lo hi)))) (* 0.5 (- hi lo))))))
)

(defun ktdim:dup (a b tol / ea eb)
  (setq ea (nth 1 a) eb (nth 1 b))
  (and (= (logand (cdr (assoc 70 ea)) 7) (logand (cdr (assoc 70 eb)) 7))
       (or (and (ktdim:peq (cdr (assoc 13 ea)) (cdr (assoc 13 eb)) tol)
                (ktdim:peq (cdr (assoc 14 ea)) (cdr (assoc 14 eb)) tol))
           (and (ktdim:peq (cdr (assoc 13 ea)) (cdr (assoc 14 eb)) tol)
                (ktdim:peq (cdr (assoc 14 ea)) (cdr (assoc 13 eb)) tol)))
       (if (and (nth 4 a) (nth 4 b))
         (ktdim:lineover (nth 4 a) (nth 4 b) tol)
         (and (ktdim:peq (cdr (assoc 10 ea)) (cdr (assoc 10 eb)) tol)
              (ktdim:peq (cdr (assoc 15 ea)) (cdr (assoc 15 eb)) tol))))
)

(defun ktdim:rad (half h)
  (cond ((> h 0) (max half (* 1.5 h))) ((> half 0) half) (T 1.0))
)

(defun ktdim:segaxes (ln) (list (caddr ln) (ktdim:perp (caddr ln))))

;;; Kiem tra 1 cap -> (loai enA enB tam bankinh) / nil
(defun ktdim:pair (a b / tqa tqb la lb h tol lo)
  (setq tqa (nth 2 a) tqb (nth 2 b) la (nth 4 a) lb (nth 4 b)
        h   (max (nth 3 a) (nth 3 b))
        tol (max (* *KT:DIM-TOLR* h) 1e-6))
  (cond
    ((ktdim:dup a b tol)
     (setq lo (if (and la lb) (ktdim:lineover la lb tol)))
     (list "TRUNG" (car a) (car b)
           (if lo (car lo) (ktdim:2d (cdr (assoc 10 (nth 1 a)))))
           (ktdim:rad (if lo (cadr lo) 0.0) h)))
    ((and la lb (setq lo (ktdim:lineover la lb tol)))
     (list "DUONG" (car a) (car b) (car lo) (ktdim:rad (cadr lo) h)))
    ((and tqa tqb (ktdim:sat (car tqa) (cdr tqa) (car tqb) (cdr tqb) 0.0))
     (list "CHU" (car a) (car b) (ktdim:mid (ktdim:cen (car tqa)) (ktdim:cen (car tqb))) (ktdim:rad 0.0 h)))
    ((and tqa lb (ktdim:sat (car tqa) (cdr tqa) (list (car lb) (cadr lb)) (ktdim:segaxes lb) -1e-9))
     (list "CHU-DIM" (car a) (car b) (ktdim:cen (car tqa)) (ktdim:rad 0.0 h)))
    ((and tqb la (ktdim:sat (car tqb) (cdr tqb) (list (car la) (cadr la)) (ktdim:segaxes la) -1e-9))
     (list "CHU-DIM" (car a) (car b) (ktdim:cen (car tqb)) (ktdim:rad 0.0 h))))
)

(defun ktdim:overlap-add (x / k)
  ;; x = (loai enA enB tam bankinh) -> kt:add
  (setq k (car x))
  (cond
    ((= k "TRUNG")
     (kt:add "DIM" "DIM-TRUNG" "LOI" "2 dim trung nhau hoan toan (copy chong len nhau) - xoa 1 dim"
             (list (nth 1 x) (nth 2 x)) (nth 3 x) (nth 4 x)))
    ((= k "DUONG")
     (kt:add "DIM" "DIM-DUONG" "LOI" "2 dim thang hang, duong dim chong len nhau"
             (list (nth 1 x) (nth 2 x)) (nth 3 x) (nth 4 x)))
    ((= k "CHU")
     (kt:add "DIM" "DIM-CHU" "CANHBAO" "Chu cua 2 dim de len nhau - doi vi tri chu"
             (list (nth 1 x) (nth 2 x)) (nth 3 x) (nth 4 x)))
    ((= k "CHU-DIM")
     (kt:add "DIM" "DIM-CHUDIM" "CANHBAO" "Chu dim de len duong dim cua dim khac"
             (list (nth 1 x) (nth 2 x)) (nth 3 x) (nth 4 x))))
)

;;; Quet theo truc X (nhu CDO) tren 1 nhom ban ghi cung khong gian -> so cap loi
(defun ktdim:overlap (recs / maxh pad a b rest iss n)
  (setq maxh 0.0 n 0)
  (foreach r recs (setq maxh (max maxh (nth 3 r))))
  (setq pad  (max (* *KT:DIM-TOLR* maxh) 1e-6)
        recs (mapcar 'cdr (ktdim:msort (mapcar '(lambda (r) (cons (car (nth 5 r)) r)) recs))))
  (while recs
    (setq a (car recs) recs (cdr recs) rest recs)
    (while rest
      (setq b (car rest))
      (if (> (car (nth 5 b)) (+ (caddr (nth 5 a)) pad))
        (setq rest nil)
        (progn
          (if (and (<= (cadr (nth 5 b)) (+ (cadddr (nth 5 a)) pad))
                   (<= (cadr (nth 5 a)) (+ (cadddr (nth 5 b)) pad))
                   (setq iss (vl-catch-all-apply 'ktdim:pair (list a b)))
                   (not (vl-catch-all-error-p iss)))
            (progn
              (vl-catch-all-apply 'ktdim:overlap-add (list iss))
              (setq n (1+ n))))
          (setq rest (cdr rest))))))
  n
)

;;; ============================================================
;;; Kiem tra 1 dim (khong phai chong lan)
;;; rec = ban ghi ktdim:record (co the nil)
;;; ============================================================
(defun ktdim:badsty (sty en / up rec)
  ;; gom dim dung style khong chuan: ((STYLEHOA ten so-luong (ename...)) ...)
  (setq up (strcase sty))
  (if (setq rec (assoc up *KT:DIM-BADSTY*))
    (setq *KT:DIM-BADSTY*
           (subst (list up (nth 1 rec) (1+ (nth 2 rec))
                        (if (< (length (nth 3 rec)) 10) (cons en (nth 3 rec)) (nth 3 rec)))
                  rec *KT:DIM-BADSTY*))
    (setq *KT:DIM-BADSTY* (cons (list up sty 1 (list en)) *KT:DIM-BADSTY*)))
)

(defun ktdim:ghide (txt typ val dec / pl num disp u)
  ;; phan loai chu ghi de -> nil / (muc thongdiep)
  (cond
    ((or (= txt "") (= txt "<>")) nil)
    ((vl-string-search "<>" txt) nil)
    ((= (kt:trim txt) "")
     (list "CANHBAO" (strcat "Chu dim bi an (ghi de bang khoang trang)"
                             (if val (strcat ", do " (ktdim:fmt val)) ""))))
    ((= (ktdim:plain txt) "")
     (list "CANHBAO" "Chu dim bi an (ghi de bang ma dinh dang rong)"))
    (T
     (setq pl  (ktdim:plain txt)
           u   (substr pl 1 1)
           num (if (member typ '(0 1 3 4 6)) (ktdim:txtnum pl typ))
           disp (if val (ktdim:roundto val (expt 10.0 (- dec)))))
     (cond
       ;; ghi kem dau +/- : chu cao do (vd +3.600) -> khong so voi gia tri do
       ((and num (member u '("+" "-")))
        (list "CANHBAO" (strcat "Chu ghi de cao do '" pl "' (kiem tra lai bang ky hieu cao do)")))
       ((and num disp (<= (abs (- num disp)) *KT:DIM-TOL*)) nil)
       ;; ghi theo don vi m / cm trong ban ve mm
       ((and num disp (or (<= (abs (- (* num 1000.0) disp)) *KT:DIM-TOL*)
                          (<= (abs (- (* num 10.0) disp)) *KT:DIM-TOL*)))
        (list "CANHBAO" (strcat "Chu ghi de '" pl "' (dung so do " (rtos disp 2 dec)
                                " nhung doi don vi bang tay - nen dung DIMLFAC/style rieng)")))
       ((and num disp)
        (list "LOI" (strcat "Ghi " pl " nhung do " (rtos disp 2 dec))))
       (T
        (list "CANHBAO" (strcat "Chu ghi de '" pl "'"
                                (if (and disp (member typ '(0 1 3 4 6)))
                                  (strcat " (do " (rtos disp 2 dec) ")")
                                  "")))))))
)

(defun ktdim:lex (meas lf)
  ;; gia tri (mm that) dung de xet "do le":
  ;;  DIMLFAC < 1 va 1/DIMLFAC nguyen (doi don vi m/cm, chi tiet phong to x5, x20...) -> gia tri do goc
  ;;  con lai -> gia tri hien thi (do x DIMLFAC; dim layout do xuyen viewport)
  (if (and (> lf 0) (< lf 0.999) (ktdim:intstep-p (/ 1.0 lf)))
    meas
    (* meas lf))
)

(defun ktdim:geo (ed typ / p13 p14 a)
  ;; chieu dai HINH HOC cua dim thang (rotated: chieu len phuong 50; aligned: khoang cach 13-14)
  (setq p13 (kt:dxf 13 ed) p14 (kt:dxf 14 ed))
  (if (and p13 p14)
    (if (= typ 0)
      (progn
        (setq a (cond ((kt:dxf 50 ed)) (0.0)))
        (abs (+ (* (- (car p14) (car p13)) (cos a)) (* (- (cadr p14) (cadr p13)) (sin a)))))
      (distance (kt:2d p13) (kt:2d p14))))
)

(defun ktdim:nicek (lf / k)
  ;; DIMLFAC cua chi tiet phong to: 1/lf = 2, 2.5, 4, 5, 10, 20 -> he so; nil neu khong
  (if (and (numberp lf) (> lf 0) (< lf 1.0))
    (progn
      (setq k (/ 1.0 lf))
      (if (vl-some '(lambda (n) (<= (abs (- k n)) (* 0.005 n))) '(2.0 2.5 4.0 5.0 10.0 20.0)) k)))
)

(defun ktdim:ovnorm (code v)
  ;; DIMSCALE 0 (= 1 trong Model, = ty le viewport trong layout) coi nhu 1 khi so override
  (if (and (= code 40) (numberp v) (<= v 0)) 1.0 v)
)

(defun ktdim:check1 (en rec / ed typ sty st row ovr anno ds lf lfraw lfstd dec sp p10 pt r
                              h meas val txt g sc scs near dev x lst tv done sev geo heff dse hp hpl dv k cands)
  (setq ed   (entget en '("ACAD" "AcadAnnotative"))
        typ  (logand (cond ((kt:dxf 70 ed)) (0)) 7)
        sty  (cond ((kt:dxf 3 ed)) ("STANDARD"))
        st   (ktdim:style sty)
        row  (nth 0 st)
        ovr  (ktdim:dstyle (ktdim:xapp ed "ACAD"))
        anno (or (nth 6 st) (ktdim:annop (ktdim:xapp ed "AcadAnnotative")))
        ds   (ktdim:eff ovr 40 (nth 1 st))
        lfraw (ktdim:eff ovr 144 (nth 2 st))
        dec  (ktdim:eff ovr 271 (nth 3 st))
        sp   (kt:space ed)
        p10  (if (kt:dxf 10 ed) (kt:2d (kt:dxf 10 ed)) '(0.0 0.0))
        pt   (if (kt:dxf 11 ed) (kt:2d (kt:dxf 11 ed)) p10)
        h    (if rec (nth 3 rec) 0.0)
        r    (cond ((> h 0) (* 2.0 h))
                   ((and (= sp "Model") (numberp ds) (> ds 0)) (* 5.0 ds))
                   (T 5.0)))
  (if (not (numberp ds)) (setq ds 0.0))
  (if (< ds 0) (setq ds 0.0))
  (setq dec (if (numberp dec) (fix dec) 0))
  (if (< dec 0) (setq dec 0))
  (if (> dec 8) (setq dec 8))
  (if (not (numberp lfraw)) (setq lfraw nil))
  ;; DIMLFAC am: chi ap dung cho dim trong layout
  (setq lf (cond ((null lfraw) 1.0)
                 ((and (< lfraw 0) (= sp "Model")) 1.0)
                 ((equal lfraw 0.0 1e-12) 1.0)
                 (T (abs lfraw))))
  ;; meas = chieu dai HINH HOC, val = gia tri HIEN THI (= meas x DIMLFAC).
  ;; Dim thang: tinh tu diem 13/14 (ma 42 cua AutoCAD = Measurement DA nhan DIMLFAC - template:
  ;; style x4 do 100 ghi 42 = 25 -> khong dung 42 de khoi nhan DIMLFAC 2 lan). Dim khac: 42 = hien thi.
  (setq geo  (if (member typ '(0 1)) (ktdim:geo ed typ))
        meas (cond ((numberp geo) geo)
                   ((and (member typ '(0 1)) rec (nth 4 rec)) (distance (car (nth 4 rec)) (cadr (nth 4 rec))))
                   ((and (numberp (kt:dxf 42 ed)) (> lf 0)) (/ (kt:dxf 42 ed) lf))))
  (setq val (if meas (* meas lf)))

  ;; --- DIM-STYLE (gom theo style, xuat o ktdim:check) ---
  (if (and *KT:DIM-CFGSTY* (not (member (kt:ukey sty) *KT:DIM-CFGSTY*)))
    (ktdim:badsty sty en))

  ;; --- DIM-TYLE: chieu cao chu dim quy ra giay ---
  (if (not anno)
    (if (= sp "Model")
      (progn
        (setq heff (if (and (numberp (nth 7 st)) (> (nth 7 st) 0))
                     (nth 7 st)                                  ; textstyle co chieu cao co dinh
                     (ktdim:eff ovr 140 (nth 4 st)))
              dse  (if (> ds 0) ds 1.0)
              sc   (ktdim:scale p10 sp))
        (if (and (numberp heff) (> heff 0) (numberp sc) (> sc 0) *KT:DIM-HS*)
          (progn
            (setq scs   (ktdim:vp-at p10)
                  cands (cons sc scs)
                  hp    (/ (* heff dse) sc))
            ;; khop chuan o TL khung hoac 1 viewport nhin thay dim -> dung
            (if (not (vl-some '(lambda (c) (equal 0.0 (ktdim:hdev (/ (* heff dse) c)) 1e-9)) cands))
              (progn
                (setq dv   (ktdim:hdev hp)
                      done (cons 40 (cons 140 done))
                      sev  (if (and dv (<= dv 0.25)) "CANHBAO" "LOI")
                      hpl  (kt:join (mapcar 'ktdim:fmt2 *KT:DIM-HS*) "/"))
                (kt:add "DIM" "DIM-TYLE" sev
                        (strcat "Chu dim cao " (ktdim:fmt2 hp) "mm giay (DIMTXT " (ktdim:fmt heff)
                                (if (/= dse 1.0) (strcat " x DIMSCALE " (ktdim:fmt dse)) "")
                                " / TL 1/" (ktdim:fmt sc) "), chuan " hpl "mm - dimstyle " sty
                                (if (and (nth 8 st) (not (ktdim:sceq (nth 8 st) sc)))
                                  (strcat " (style cho TL 1/" (ktdim:fmt (nth 8 st)) ")") "")
                                (if (= sev "CANHBAO") " - gan chuan, kiem tra lai" ""))
                        en pt r))))))
      (if (and (> ds 0) (> (abs (- ds 1.0)) 0.01))
        (progn
          (setq done (cons 40 done))
          (kt:add "DIM" "DIM-TYLE" "LOI"
                  (strcat "Dim trong layout '" sp "' co DIMSCALE=" (ktdim:fmt ds)
                          " (phai la 1 hoac 0) - dimstyle " sty)
                  en pt r)))))

  ;; --- DIM-LFAC ---  (so gia tri HIEU DUNG voi chuan cua style)
  (setq lfstd (cond ((and row (kt:num (nth 2 row)) (/= (kt:num (nth 2 row)) 0))
                     (abs (kt:num (nth 2 row))))
                    (T 1.0)))
  (if (and lfraw (ktdim:neq lf lfstd)
           (not (and (/= sp "Model") (ktdim:vp-scale-p lf sp))))
    (progn
      (setq done (cons 144 done)
            k    (ktdim:nicek lf)
            ;; chi tiet ve phong to trong khung (vd khung 1/100, ve x5, DIMLFAC 0.2 -> TL that 1/20)
            sc   (if (= sp "Model") (ktdim:scale p10 sp))
            sev  (if (or k (and (numberp sc) (> sc 0) (< lf 1.0) (ktdim:allowed-p (* lf sc))))
                   "CANHBAO" "LOI"))
      (kt:add "DIM" "DIM-LFAC" sev
              (strcat "DIMLFAC=" (ktdim:fmt lfraw) " khac chuan " (ktdim:fmt lfstd)
                      " cua style " sty
                      (cond (k (strcat " - chi tiet phong to x" (ktdim:fmt k)
                                       "? nen dung dimstyle phong to cua cong ty (vd 'x" (ktdim:fmt k) "')"))
                            ((= sev "CANHBAO")
                             (strcat " - chi tiet phong to? (TL that 1/" (ktdim:fmt (* lf sc)) ")"))
                            (T " - dim do sai so"))
                      (if val (strcat " (do " (ktdim:fmt meas) " hien " (ktdim:fmt val) ")") ""))
              en pt r)))
  ;; ghi lai de xet dim cung chuoi khac DIMLFAC (ktdim:chk-lfmix)
  (if (and (member typ '(0 1)) (kt:dxf 13 ed) (kt:dxf 14 ed) rec (nth 4 rec))
    (setq *KT:DIM-LFL* (cons (list sp lf (caddr (nth 4 rec)) (kt:2d (kt:dxf 13 ed)) (kt:2d (kt:dxf 14 ed)) en)
                             *KT:DIM-LFL*)))

  ;; --- DIM-GHIDE ---
  (setq txt (kt:dxf 1 ed))
  (if (/= (type txt) 'STR) (setq txt ""))
  (if (setq g (ktdim:ghide txt typ val dec))
    (kt:add "DIM" "DIM-GHIDE" (car g) (cadr g) en pt r))

  ;; --- DIM-NHO / DIM-LE ---
  (cond
    ((and meas (member typ '(0 1 3 4)) (< (abs meas) 1.0))
     (kt:add "DIM" "DIM-NHO" "GOIY"
             (strcat "Dim gia tri 0 hoac rat nho (" (rtos meas 2 3) ") - dim thua hoac bat diem sai")
             en pt r))
    ((and meas (member typ '(0 1)))
     (setq x    (ktdim:lex meas lf)
           near (ktdim:roundto x *KT:DIM-STEP*)
           dev  (abs (- x near)))
     (if (> dev *KT:DIM-LECH*)
       (kt:add "DIM" "DIM-LE" "CANHBAO"
               (strcat "Kich thuoc do le " (rtos x 2 3)
                       " (hien " (rtos (ktdim:roundto val (expt 10.0 (- dec))) 2 dec)
                       ") lech " (rtos dev 2 3) " so voi boi so " (ktdim:fmt *KT:DIM-STEP*)
                       " - kiem tra bat diem")
               en pt r))))

  ;; --- DIM-ASSOC ---
  (if (and *KT:DIM-ASSOC* (not (ktdim:assocp ed)))
    (kt:add "DIM" "DIM-ASSOC" "GOIY" "Dim khong lien ket voi doi tuong (non-associative)"
            en pt r))

  ;; --- DIM-OVR --- (bo qua ma da bao o DIM-TYLE / DIM-LFAC)
  (foreach x '((40 "DIMSCALE" 1) (140 "DIMTXT" 4) (41 "DIMASZ" 5) (144 "DIMLFAC" 2) (271 "DIMDEC" 3))
    (if (and (not (member (car x) done))
             (assoc (car x) ovr)
             (numberp (setq tv (nth (caddr x) st)))
             (numberp (cdr (assoc (car x) ovr)))
             (ktdim:neq (float (ktdim:ovnorm (car x) (cdr (assoc (car x) ovr))))
                        (float (ktdim:ovnorm (car x) tv))))
      (setq lst (cons (strcat (cadr x) "=" (ktdim:fmt (cdr (assoc (car x) ovr)))
                              " (style " (ktdim:fmt tv) ")")
                      lst))))
  (if lst
    (kt:add "DIM" "DIM-OVR" "CANHBAO"
            (strcat "Override dimstyle " sty ": " (kt:join (reverse lst) ", "))
            en pt r))
  T
)

;;; ============================================================
;;; Chay kiem tra tren danh sach dim
;;; ============================================================
(defun ktdim:chk-lfmix (/ pts lst a b tol rest seen k)
  ;; 2 dim thang cung khong gian, cung phuong, chung 1 diem chan (13/14) ma khac DIMLFAC -> CANHBAO
  ;; (vd dim style x4 cua chi tiet phong to noi chuoi voi dim thuong: 1 trong 2 hien sai so)
  (setq tol (max 0.5 (* 0.5 *KT:DIM-TOL*)))
  ;; pts: (x y sp lf phuong en)
  (foreach d *KT:DIM-LFL*
    (foreach p (list (nth 3 d) (nth 4 d))
      (setq pts (cons (list (car p) (cadr p) (nth 0 d) (nth 1 d) (nth 2 d) (nth 5 d)) pts))))
  (setq lst (kt:msort pts '(lambda (a b) (< (car a) (car b)))))
  (while lst
    (setq a (car lst) lst (cdr lst) rest lst)
    (while (and rest (<= (- (car (car rest)) (car a)) tol))
      (setq b (car rest) rest (cdr rest))
      (if (and (<= (abs (- (cadr b) (cadr a))) tol)
               (= (nth 2 a) (nth 2 b))
               (ktdim:neq (nth 3 a) (nth 3 b))
               (< (abs (- (* (car (nth 4 a)) (cadr (nth 4 b))) (* (cadr (nth 4 a)) (car (nth 4 b))))) 1e-6)
               (not (member (setq k (list (nth 5 a) (nth 5 b))) seen)))
        (progn
          (setq seen (cons k (cons (reverse k) seen)))
          (kt:add "DIM" "DIM-LFAC" "CANHBAO"
                  (strcat "2 dim cung phuong chung diem chan nhung khac DIMLFAC ("
                          (ktdim:fmt (nth 3 a)) " / " (ktdim:fmt (nth 3 b))
                          "): dim chi tiet phong to noi chuoi voi dim thuong? 1 trong 2 hien sai so")
                  (list (nth 5 a) (nth 5 b)) (list (car a) (cadr a)) nil)))))
  (setq *KT:DIM-LFL* nil)
)

(defun ktdim:check (lst / ed n nerr r rec pairs spaces nov)
  (ktdim:params)
  (kt:begin "DIM")
  (setq n 0 nerr 0 nov 0)
  (foreach en lst
    (setq ed (entget en))
    (if (and ed
             (not (and *KT:DIM-SKIP* (kt:wcmatch-any (cond ((kt:dxf 8 ed)) ("0")) *KT:DIM-SKIP*))))
      (progn
        (setq n   (1+ n)
              rec (vl-catch-all-apply 'ktdim:record (list en)))
        (if (vl-catch-all-error-p rec)
          (setq rec nil)
          (setq pairs (cons (cons (kt:space ed) rec) pairs)))
        (setq r (vl-catch-all-apply 'ktdim:check1 (list en rec)))
        (if (vl-catch-all-error-p r) (setq nerr (1+ nerr))))))
  (setq r (vl-catch-all-apply 'ktdim:chk-lfmix nil))
  (if (vl-catch-all-error-p r)
    (princ (strcat "\n[DIM] Loi khi xet DIMLFAC chuoi dim: " (vl-catch-all-error-message r))))
  ;; DIM-STYLE: 1 dong / style khong chuan
  (foreach x (reverse *KT:DIM-BADSTY*)
    (kt:add "DIM" "DIM-STYLE" "LOI"
            (strcat "Dimstyle '" (nth 1 x) "' khong co trong chuan cong ty ("
                    (itoa (nth 2 x)) " dim)")
            (reverse (nth 3 x)) nil nil))
  (setq *KT:DIM-BADSTY* nil)
  ;; chong lan: tung khong gian rieng (so khong gian it -> O(n x so khong gian))
  (foreach p pairs (if (not (member (car p) spaces)) (setq spaces (cons (car p) spaces))))
  (foreach sp spaces
    (setq r (vl-catch-all-apply 'ktdim:overlap
              (list (mapcar 'cdr (vl-remove-if-not '(lambda (p) (= (car p) sp)) pairs)))))
    (if (vl-catch-all-error-p r)
      (princ (strcat "\n[DIM] Loi khi quet chong lan (" sp "): "
                     (vl-catch-all-error-message r)))
      (setq nov (+ nov r))))
  (princ (strcat "\n[DIM] Da kiem tra " (itoa n) " dim, " (itoa nov) " cap chong lan."))
  (if (> nerr 0)
    (princ (strcat "\n[DIM] " (itoa nerr) " dim loi khi doc du lieu (bo qua).")))
  (if (null *KT:DIM-CFGSTY*)
    (princ "\n[DIM] File chuan chua co muc DIMSTYLE - bo qua kiem tra DIM-STYLE."))
  (if *KT:DIM-SCERR*
    (princ (strcat "\n[DIM] Khong xac dinh duoc ty le khung (" *KT:DIM-SCERR*
                   ") - DIM-TYLE co the thieu.")))
  (kt:finish "DIM")
)

(defun ktdim:run ()
  ;; cho KTALL: tat ca dim, khong hoi
  (if (kt:cfg-ok)
    (ktdim:check (kt:ss-all '((0 . "DIMENSION")))))
)

(defun c:KTDIM ()
  ;; pham vi: toan ban ve / vung cua so (thay cho chon tung dim)
  (kt:cmd 'ktdim:run)
  (princ)
)

;;; ============================================================
;;; KTDIMSET - doi SETTING tam thoi trong phien (khong ghi file)
;;; ============================================================
(defun ktdim:setcfg (key val / sec rows found new)
  ;; cap nhat / them dong SETTING|key|val trong *KT:CFG*
  (setq key  (strcase key)
        sec  (assoc "SETTING" *KT:CFG*)
        rows (mapcar '(lambda (r)
                        (if (= (strcase (car r)) key)
                          (progn (setq found T) (cons (car r) (cons val (cddr r))))
                          r))
                     (cdr sec)))
  (if (not found) (setq rows (append rows (list (list key val)))))
  (setq new (cons "SETTING" rows))
  (setq *KT:CFG* (if sec (subst new sec *KT:CFG*) (cons new *KT:CFG*)))
  val
)

(defun c:KTDIMSET (/ items cur v)
  (if (kt:cfg-ok)
    (progn
      (setq items '(("DIM_DUNG_SAI_TL" 0.1 4 "Dung sai thang hang/chong duong (x chieu cao chu)")
                    ("DIM_HO_CHU" 0.0 4 "Khoang ho chu toi thieu (x chieu cao chu, 0 = chi bat chong that)")
                    ("DIM_BUOC_CHAN" 1.0 6 "Buoc so chan cua kich thuoc (mm)")
                    ("DIM_LECH_LE" 0.05 4 "Lech toi da so voi boi so chan (mm)")
                    ("DUNG_SAI_KICH_THUOC" 1.0 4 "Dung sai chu ghi de so voi gia tri do (mm)")))
      (foreach it items
        (setq cur (kt:cfg-num (car it) (cadr it)))
        (initget (caddr it))
        (if (setq v (getreal (strcat "\n" (nth 3 it) " <" (rtos cur 2 3) ">: ")))
          (ktdim:setcfg (car it) (rtos v 2 6))))
      (setq cur (fix (kt:cfg-num "KIEM_DIM_ASSOC" 0)))
      (initget "1 0")
      (if (setq v (getkword (strcat "\nKiem tra dim khong lien ket [1=bat/0=tat] <" (itoa cur) ">: ")))
        (ktdim:setcfg "KIEM_DIM_ASSOC" v))
      (princ "\n[DIM] Da doi SETTING trong phien (KTCFG se nap lai tu file, mat thay doi).")))
  (princ)
)

(princ "\nKT_Dim da nap. Lenh: KTDIM, KTDIMSET")
(princ)
