;;; ============================================================
;;; CheckDimOverlap.lsp  -  Kiem tra DIM bi chong lan nhau
;;; ------------------------------------------------------------
;;; Lenh:
;;;   CDO    : Kiem tra (chon dim, Enter = tat ca dim trong khong gian hien tai)
;;;   CDON   : Zoom lan luot toi tung loi
;;;   CDOX   : Xoa cac dau danh dau loi
;;;   CDOSET : Chinh dung sai / khoang ho chu
;;;
;;; Cac loai loi:
;;;   TRUNG   (do)      : 2 dim trung hoan toan (copy chong len nhau)
;;;   DUONG   (tim)     : 2 dim thang hang, duong dim chong len nhau
;;;   CHU     (cam)     : chu cua 2 dim de len nhau
;;;   CHU-DIM (xanh)    : chu cua dim nay de len duong dim cua dim khac
;;;
;;; Gia dinh: ban ve 2D, dim nam trong WCS (mat bang/mat dung thong thuong).
;;; ============================================================

(vl-load-com)

(if (not *CDO:TOLR*)  (setq *CDO:TOLR* 0.1))   ; dung sai = 0.1 x chieu cao chu dim
(if (not *CDO:GAPR*)  (setq *CDO:GAPR* 0.0))   ; noi rong khung chu (0.2 = bat ca chu qua sat)
(setq *CDO:LAYER* "CHECK_DIM_OVERLAP")

;;; ---------- Vector 2D ----------
(defun cdo:2d (p) (list (float (car p)) (float (cadr p))))
(defun cdo:3d (p) (list (car p) (cadr p) 0.0))
(defun cdo:v+ (a b) (list (+ (car a) (car b)) (+ (cadr a) (cadr b))))
(defun cdo:v- (a b) (list (- (car a) (car b)) (- (cadr a) (cadr b))))
(defun cdo:v* (a s) (list (* (car a) s) (* (cadr a) s)))
(defun cdo:dot (a b) (+ (* (car a) (car b)) (* (cadr a) (cadr b))))
(defun cdo:perp (v) (list (- (cadr v)) (car v)))
(defun cdo:unit (v / l)
  (setq l (distance '(0.0 0.0) v))
  (if (> l 1e-12) (list (/ (car v) l) (/ (cadr v) l)) '(1.0 0.0))
)
(defun cdo:mid (a b) (cdo:v* (cdo:v+ a b) 0.5))
(defun cdo:cen (pts)
  (list (/ (apply '+ (mapcar 'car pts)) (length pts))
        (/ (apply '+ (mapcar 'cadr pts)) (length pts)))
)
(defun cdo:aabb (pts / xs ys)
  (setq xs (mapcar 'car pts) ys (mapcar 'cadr pts))
  (list (apply 'min xs) (apply 'min ys) (apply 'max xs) (apply 'max ys))
)
(defun cdo:peq (a b tol)
  (or (and (null a) (null b))
      (and a b (< (distance (cdo:2d a) (cdo:2d b)) tol)))
)

;;; ---------- Tim chu (MTEXT/TEXT) trong block cua dim ----------
(defun cdo:dimtext (en / blk e ed res)
  (setq blk (cdr (assoc 2 (entget en))))
  (if (and blk (setq e (tblobjname "BLOCK" blk)))
    (progn
      (setq e (entnext e))
      (while (and e (not res))
        (setq ed (entget e))
        (cond ((= (cdr (assoc 0 ed)) "ENDBLK") (setq e nil))
              ((member (cdr (assoc 0 ed)) '("MTEXT" "TEXT")) (setq res ed))
        )
        (if e (setq e (entnext e)))
      )
    )
  )
  res
)

;;; Khung chu nhat xoay: tra ve (pts u v h)
(defun cdo:mkquad (bl u v w h / g)
  (setq g  (* *CDO:GAPR* h)
        bl (cdo:v- bl (cdo:v+ (cdo:v* u g) (cdo:v* v g))))
  (list (list bl
              (cdo:v+ bl (cdo:v* u (+ w g g)))
              (cdo:v+ (cdo:v+ bl (cdo:v* u (+ w g g))) (cdo:v* v (+ h g g)))
              (cdo:v+ bl (cdo:v* v (+ h g g))))
        u v h)
)

(defun cdo:textquad (ed / typ ins w h u v a col row bl ang tb)
  (setq typ (cdr (assoc 0 ed)))
  (cond
    ((= typ "MTEXT")
     (setq ins (cdo:2d (cdr (assoc 10 ed)))
           w   (cdr (assoc 42 ed))
           h   (cdr (assoc 43 ed))
           a   (cdr (assoc 71 ed)))
     (setq u (cond ((assoc 11 ed) (cdo:unit (cdo:2d (cdr (assoc 11 ed)))))
                   ((assoc 50 ed) (list (cos (cdr (assoc 50 ed))) (sin (cdr (assoc 50 ed)))))
                   (T '(1.0 0.0))))
     (if (and w h a (> w 0) (> h 0))
       (progn
         (setq v   (cdo:perp u)
               col (rem (1- a) 3)
               row (/ (1- a) 3)
               bl  (cdo:v- (cdo:v- ins (cdo:v* u (* col w 0.5)))
                           (cdo:v* v (* (- 2 row) h 0.5))))
         (cdo:mkquad bl u v w h)
       )
     )
    )
    ((= typ "TEXT")
     (if (setq tb (textbox ed))
       (progn
         (setq ins (cdo:2d (cdr (assoc 10 ed)))
               ang (cond ((cdr (assoc 50 ed))) (0.0))
               u   (list (cos ang) (sin ang))
               v   (cdo:perp u)
               w   (- (car (cadr tb)) (car (car tb)))
               h   (- (cadr (cadr tb)) (cadr (car tb)))
               bl  (cdo:v+ ins (cdo:v+ (cdo:v* u (car (car tb))) (cdo:v* v (cadr (car tb))))))
         (if (and (> w 0) (> h 0)) (cdo:mkquad bl u v w h))
       )
     )
    )
  )
)

;;; ---------- Duong dim (chi dim thang: rotated / aligned) ----------
(defun cdo:dimline (ed / typ p10 p13 p14 ang u e1 e2)
  (setq typ (logand (cdr (assoc 70 ed)) 7))
  (if (member typ '(0 1))
    (progn
      (setq p10 (cdo:2d (cdr (assoc 10 ed)))
            p13 (cdo:2d (cdr (assoc 13 ed)))
            p14 (cdo:2d (cdr (assoc 14 ed))))
      (setq u (if (= typ 0)
                (progn (setq ang (cond ((cdr (assoc 50 ed))) (0.0)))
                       (list (cos ang) (sin ang)))
                (if (> (distance p13 p14) 1e-9) (cdo:unit (cdo:v- p14 p13)))))
      (if u
        (progn
          (setq e1 (cdo:v+ p10 (cdo:v* u (cdo:dot (cdo:v- p13 p10) u)))
                e2 (cdo:v+ p10 (cdo:v* u (cdo:dot (cdo:v- p14 p10) u))))
          (if (> (distance e1 e2) 1e-9) (list e1 e2 u))
        )
      )
    )
  )
)

;;; ---------- Ban ghi 1 dim: (ename ed textquad h line aabb) ----------
(defun cdo:record (en / ed td tq h ln pts)
  (setq ed (entget en))
  (if (setq td (cdo:dimtext en)) (setq tq (cdo:textquad td)))
  (setq h  (if tq (nth 3 tq) 0.0)
        tq (if tq (list (car tq) (cadr tq) (caddr tq))))   ; (pts u v)
  (setq ln (cdo:dimline ed))
  (setq pts (append (if tq (car tq))
                    (if ln (list (car ln) (cadr ln)))
                    (list (cdo:2d (cdr (assoc 10 ed))))))
  (list en ed tq h ln (cdo:aabb pts))
)

;;; ---------- Hinh hoc va cham (Separating Axis Theorem) ----------
(defun cdo:proj (pts ax / d)
  (setq d (mapcar '(lambda (p) (cdo:dot p ax)) pts))
  (list (apply 'min d) (apply 'max d))
)
(defun cdo:sat (p1 a1 p2 a2 tol / ok r1 r2)
  (setq ok T)
  (foreach ax (append a1 a2)
    (if ok
      (progn
        (setq r1 (cdo:proj p1 ax) r2 (cdo:proj p2 ax))
        (if (<= (- (min (cadr r1) (cadr r2)) (max (car r1) (car r2))) tol)
          (setq ok nil))
      )
    )
  )
  ok
)

;;; 2 duong dim thang hang & chong nhau -> (diem giua doan chong, nua chieu dai) / nil
(defun cdo:lineover (l1 l2 tol / u1 u2 o s2 s3 s4 lo hi)
  (setq u1 (caddr l1) u2 (caddr l2) o (car l1))
  (if (and (< (abs (- (* (car u1) (cadr u2)) (* (cadr u1) (car u2)))) 1e-6)
           (< (abs (cdo:dot (cdo:v- (car l2) o) (cdo:perp u1))) tol))
    (progn
      (setq s2 (cdo:dot (cdo:v- (cadr l1) o) u1)
            s3 (cdo:dot (cdo:v- (car l2) o) u1)
            s4 (cdo:dot (cdo:v- (cadr l2) o) u1)
            lo (max (min 0.0 s2) (min s3 s4))
            hi (min (max 0.0 s2) (max s3 s4)))
      (if (> (- hi lo) tol)
        (list (cdo:v+ o (cdo:v* u1 (* 0.5 (+ lo hi)))) (* 0.5 (- hi lo))))
    )
  )
)

(defun cdo:dup (a b tol / ea eb)
  (setq ea (nth 1 a) eb (nth 1 b))
  (and (= (logand (cdr (assoc 70 ea)) 7) (logand (cdr (assoc 70 eb)) 7))
       (or (and (cdo:peq (cdr (assoc 13 ea)) (cdr (assoc 13 eb)) tol)
                (cdo:peq (cdr (assoc 14 ea)) (cdr (assoc 14 eb)) tol))
           (and (cdo:peq (cdr (assoc 13 ea)) (cdr (assoc 14 eb)) tol)
                (cdo:peq (cdr (assoc 14 ea)) (cdr (assoc 13 eb)) tol)))
       (if (and (nth 4 a) (nth 4 b))
         (cdo:lineover (nth 4 a) (nth 4 b) tol)
         (and (cdo:peq (cdr (assoc 10 ea)) (cdr (assoc 10 eb)) tol)
              (cdo:peq (cdr (assoc 15 ea)) (cdr (assoc 15 eb)) tol))))
)

(defun cdo:rad (half h)
  (cond ((> h 0) (max half (* 1.5 h))) ((> half 0) half) (T 1.0))
)

(defun cdo:segaxes (ln) (list (caddr ln) (cdo:perp (caddr ln))))

;;; Kiem tra 1 cap -> (loai enA enB tam bankinh) / nil
(defun cdo:check (a b / tqa tqb la lb h tol lo)
  (setq tqa (nth 2 a) tqb (nth 2 b) la (nth 4 a) lb (nth 4 b)
        h   (max (nth 3 a) (nth 3 b))
        tol (max (* *CDO:TOLR* h) 1e-6))
  (cond
    ((cdo:dup a b tol)
     (setq lo (if (and la lb) (cdo:lineover la lb tol)))
     (list "TRUNG" (car a) (car b)
           (if lo (car lo) (cdo:2d (cdr (assoc 10 (nth 1 a)))))
           (cdo:rad (if lo (cadr lo) 0.0) h)))
    ((and la lb (setq lo (cdo:lineover la lb tol)))
     (list "DUONG" (car a) (car b) (car lo) (cdo:rad (cadr lo) h)))
    ((and tqa tqb (cdo:sat (car tqa) (cdr tqa) (car tqb) (cdr tqb) 0.0))
     (list "CHU" (car a) (car b) (cdo:mid (cdo:cen (car tqa)) (cdo:cen (car tqb))) (cdo:rad 0.0 h)))
    ((and tqa lb (cdo:sat (car tqa) (cdr tqa) (list (car lb) (cadr lb)) (cdo:segaxes lb) -1e-9))
     (list "CHU-DIM" (car a) (car b) (cdo:cen (car tqa)) (cdo:rad 0.0 h)))
    ((and tqb la (cdo:sat (car tqb) (cdr tqb) (list (car la) (cadr la)) (cdo:segaxes la) -1e-9))
     (list "CHU-DIM" (car a) (car b) (cdo:cen (car tqb)) (cdo:rad 0.0 h)))
  )
)

;;; ---------- Danh dau ----------
(defun cdo:color (typ)
  (cdr (assoc typ '(("TRUNG" . 1) ("DUONG" . 6) ("CHU" . 30) ("CHU-DIM" . 4))))
)
(defun cdo:mklayer ()
  (if (not (tblsearch "LAYER" *CDO:LAYER*))
    (entmake (list '(0 . "LAYER") '(100 . "AcDbSymbolTableRecord")
                   '(100 . "AcDbLayerTableRecord") (cons 2 *CDO:LAYER*)
                   '(70 . 0) '(62 . 1) '(6 . "Continuous") '(290 . 0))))
)
(defun cdo:mark (x / c r col)
  (setq c (cdo:3d (nth 3 x)) r (nth 4 x) col (cdo:color (car x)))
  (entmake (list '(0 . "CIRCLE") (cons 8 *CDO:LAYER*) (cons 62 col) (cons 10 c) (cons 40 r)))
  (entmake (list '(0 . "TEXT") (cons 8 *CDO:LAYER*) (cons 62 col)
                 (cons 10 (list (+ (car c) (* 0.75 r)) (+ (cadr c) (* 0.75 r)) 0.0))
                 (cons 40 (* 0.35 r)) (cons 1 (car x))))
)
(defun cdo:clear (/ ss i)
  (if (setq ss (ssget "_X" (list (cons 8 *CDO:LAYER*))))
    (repeat (setq i (sslength ss)) (entdel (ssname ss (setq i (1- i))))))
)
(defun cdo:space ()
  (if (or (= 1 (getvar "TILEMODE")) (> (getvar "CVPORT") 1)) "Model" (getvar "CTAB"))
)

;;; ============================================================
;;; LENH CHINH
;;; ============================================================
(defun c:CDO (/ doc ss i en r recs maxh pad a b rest iss issues ss2 n)
  (setq doc (vla-get-ActiveDocument (vlax-get-acad-object)))
  (princ "\nChon DIM can kiem tra <Enter = tat ca DIM trong khong gian hien tai>: ")
  (if (not (setq ss (ssget '((0 . "DIMENSION")))))
    (setq ss (ssget "_X" (list '(0 . "DIMENSION") (cons 410 (cdo:space))))))
  (cond
    ((not ss) (princ "\nKhong tim thay DIM nao."))
    (T
     (vla-StartUndoMark doc)
     (cdo:clear)
     (setq i 0 maxh 0.0)
     (repeat (sslength ss)
       (setq en (ssname ss i) i (1+ i)
             r  (vl-catch-all-apply 'cdo:record (list en)))
       (if (not (vl-catch-all-error-p r))
         (setq recs (cons r recs) maxh (max maxh (nth 3 r)))))
     (setq n    (length recs)
           pad  (max (* *CDO:TOLR* maxh) 1e-6)
           recs (vl-sort recs '(lambda (x y) (< (car (nth 5 x)) (car (nth 5 y))))))
     ;; quet theo truc X de khong phai so tung cap
     (while recs
       (setq a (car recs) recs (cdr recs) rest recs)
       (while rest
         (setq b (car rest))
         (if (> (car (nth 5 b)) (+ (caddr (nth 5 a)) pad))
           (setq rest nil)
           (progn
             (if (and (<= (cadr (nth 5 b)) (+ (cadddr (nth 5 a)) pad))
                      (<= (cadr (nth 5 a)) (+ (cadddr (nth 5 b)) pad))
                      (setq iss (vl-catch-all-apply 'cdo:check (list a b)))
                      (not (vl-catch-all-error-p iss)))
               (setq issues (cons iss issues)))
             (setq rest (cdr rest))
           )
         )
       )
     )
     (setq ss2 (ssadd))
     (if issues (cdo:mklayer))
     (foreach x issues
       (cdo:mark x)
       (ssadd (nth 1 x) ss2)
       (ssadd (nth 2 x) ss2))
     (setq *CDO:ISSUES* (reverse issues) *CDO:IDX* -1)
     (vla-EndUndoMark doc)
     (princ (strcat "\n=== Da kiem tra " (itoa n) " dim - phat hien " (itoa (length issues)) " cap loi ==="))
     (foreach k '("TRUNG" "DUONG" "CHU" "CHU-DIM")
       (princ (strcat "\n  " k ": "
                      (itoa (length (vl-remove-if-not '(lambda (x) (= (car x) k)) issues))))))
     (if issues
       (progn
         (sssetfirst nil ss2)
         (princ (strcat "\nDim loi dang duoc chon. Danh dau tren layer " *CDO:LAYER*
                        ". Go CDON de xem tung loi, CDOX de xoa danh dau.")))
       (princ "\nKhong co dim chong lan."))
    )
  )
  (princ)
)

(defun c:CDON (/ n x s)
  (if *CDO:ISSUES*
    (progn
      (setq n (length *CDO:ISSUES*)
            *CDO:IDX* (rem (1+ *CDO:IDX*) n)
            x (nth *CDO:IDX* *CDO:ISSUES*))
      (vla-ZoomCenter (vlax-get-acad-object) (vlax-3d-point (cdo:3d (nth 3 x))) (* 8.0 (nth 4 x)))
      (setq s (ssadd))
      (foreach e (list (nth 1 x) (nth 2 x)) (if (entget e) (ssadd e s)))
      (if (> (sslength s) 0) (sssetfirst nil s))
      (princ (strcat "\nLoi " (itoa (1+ *CDO:IDX*)) "/" (itoa n) ": " (car x)))
    )
    (princ "\nChua co ket qua. Chay CDO truoc.")
  )
  (princ)
)

(defun c:CDOX ()
  (cdo:clear)
  (setq *CDO:ISSUES* nil *CDO:IDX* -1)
  (princ "\nDa xoa danh dau.")
  (princ)
)

(defun c:CDOSET (/ v)
  (initget 4)
  (if (setq v (getreal (strcat "\nDung sai thang hang/chong duong (x chieu cao chu) <" (rtos *CDO:TOLR* 2 2) ">: ")))
    (setq *CDO:TOLR* v))
  (initget 4)
  (if (setq v (getreal (strcat "\nKhoang ho chu toi thieu (x chieu cao chu, 0 = chi bat chong that) <" (rtos *CDO:GAPR* 2 2) ">: ")))
    (setq *CDO:GAPR* v))
  (princ)
)

(princ "\nCheckDimOverlap da nap. Lenh: CDO, CDON, CDOX, CDOSET")
(princ)
