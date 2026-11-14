;;; ============================================================
;;; KT_Sheet.lsp  -  Module "KHUNG": khung ten, so hieu, danh muc, tham chieu
;;; ------------------------------------------------------------
;;; Lenh: KTKHUNG        Ham khong hoi: (ktsh:run)
;;; Can: KT_Core.lsp (nap truoc). Khung ten = block trong muc KHUNG cua file chuan.
;;;
;;; Ma loi:
;;;   KHUNG-KHONGCO    (CANHBAO) khong tim thay khung ten nao
;;;   KHUNG-THIEU      (LOI)     khung ten con attribute rong (bo qua tag khop
;;;                              SETTING KHUNG_TAG_BO_QUA, wildcard, vd NGAY*,GHICHU)
;;;   KHUNG-TRUNGSO    (LOI)     2 khung cung so hieu
;;;   KHUNG-TRUNGTEN   (CANHBAO) 2 khung cung ten ban ve
;;;   KHUNG-NHAYSO     (CANHBAO) so hieu nhay coc trong cung tien to (KT-02 -> KT-04)
;;;   KHUNG-TYLE       (LOI)     ty le ghi trong khung khac ty le thuc (Model: scale X
;;;                              x ty le goc; Layout: ty le viewport trong khung),
;;;                              khong doc duoc, hoac khong thuoc TY_LE_CHO_PHEP
;;;   KHUNG-DANHMUC    (CANHBAO) bang danh muc ban ve trong ban ve khong khop khung ten
;;;                    (GOIY)    khong tim thay bang danh muc
;;;   KHUNG-THAMCHIEU  (LOI)     ky hieu mat cat/chi tiet tro toi so hieu khong ton tai
;;;                    (CANHBAO) ky hieu mat cat 1-1 nhung khong co ban ve/tieu de
;;;                              "MAT CAT 1-1"
;;;   KHUNG-NGOAI      (GOIY)    doi tuong trong Model nam ngoai moi khung ten (gom o)
;;;
;;; Gia dinh:
;;;  - Danh muc: TABLE co o chua "DANH MUC", hoac TEXT/MTEXT "DANH MUC..." + cac
;;;    TEXT/MTEXT trong cung khung ten (khong co khung: vung duoi tieu de). So hieu
;;;    trong danh muc phai cung tien to voi so hieu khung ten (vd KT-01), so hieu
;;;    chi gom chu so (01, 02) khong duoc ho tro. Ten ban ve = o dai nhat cung hang.
;;;    MTEXT nhieu dong: moi dong 1 ban ve ("1  KT-01  MAT BANG TANG 1").
;;;  - Ky hieu tham chieu: block vai tro MATCAT/CHITIET trong muc BLOCK
;;;    (BLOCK|ten|MATCAT|tag ky hieu|tag so hieu ban ve). Khong co cot 4: lay tag co
;;;    ten khop *BV*,*SHEET*,*KH*,*SO*BV* (khac tag ky hieu).
;;;  - So sanh ten: bo dau tieng Viet dang \U+XXXX / Unicode, bo khoang trang va
;;;    dau cau, khong phan biet hoa thuong. Font TCVN3/VNI: chi so sanh ASCII.
;;; ============================================================

;;; ---------- tien ich ----------
(defun ktsh:try (name f args / r)
  (setq r (vl-catch-all-apply f args))
  (if (vl-catch-all-error-p r)
    (progn
      (princ (strcat "\n[KHUNG] Loi khi kiem tra " name ": " (vl-catch-all-error-message r)))
      nil)
    r)
)

(defun ktsh:merge (a b f / res)
  (while (and a b)
    (if (apply f (list (car b) (car a)))
      (setq res (cons (car b) res) b (cdr b))
      (setq res (cons (car a) res) a (cdr a))))
  (append (reverse res) a b)
)

(defun ktsh:msort (lst f / a n i)
  ;; merge sort on dinh (vl-sort co the xoa phan tu trung)
  (if (or (null lst) (null (cdr lst)))
    lst
    (progn
      (setq n (/ (length lst) 2) i 0)
      (while (< i n)
        (setq a (cons (car lst) a) lst (cdr lst) i (1+ i)))
      (ktsh:merge (ktsh:msort (reverse a) f) (ktsh:msort lst f) f)))
)

(defun ktsh:uniq (lst / res)
  (foreach x lst (if (not (member x res)) (setq res (cons x res))))
  (reverse res)
)

(defun ktsh:head (lst n / res)
  ;; n phan tu dau
  (while (and lst (> n 0))
    (setq res (cons (car lst) res) lst (cdr lst) n (1- n)))
  (reverse res)
)

(defun ktsh:floor (x)
  (if (and (< x 0) (/= x (fix x))) (1- (fix x)) (fix x))
)

(defun ktsh:pad (n w / s)
  (setq s (itoa n))
  (while (< (strlen s) w) (setq s (strcat "0" s)))
  s
)

(defun ktsh:sc (s)
  ;; 100.0 -> "1/100"
  (if (numberp s)
    (strcat "1/" (if (equal s (float (fix s)) 1e-6) (itoa (fix s)) (rtos s 2 2)))
    "?")
)

(defun ktsh:alldig (s)
  (and (= (type s) 'STR) (/= s "")
       (vl-every '(lambda (c) (and (>= c 48) (<= c 57))) (vl-string->list s)))
)

;;; ---------- chuoi: bo ma MTEXT, bo dau ----------
(defun ktsh:plain (s nl / i n c d j res)
  ;; bo ma dinh dang MTEXT; \P -> xuong dong (nl=T) hoac dau cach; giu \U+XXXX
  (setq i 1 n (strlen s) res "")
  (while (<= i n)
    (setq c (substr s i 1))
    (cond
      ((and (= c "\\") (< i n))
       (setq d (substr s (1+ i) 1))
       (cond
         ((= d "P") (setq res (strcat res (if nl "\n" " ")) i (+ i 2)))
         ((member d '("N" "~")) (setq res (strcat res " ") i (+ i 2)))
         ((member (strcase d) '("F" "H" "C" "T" "Q" "W" "A" "S" "P"))
          (setq j (vl-string-search ";" s i))
          (setq i (if j (+ j 2) (1+ n))))
         ((member (strcase d) '("U" "M")) (setq res (strcat res c) i (1+ i)))
         ((member (strcase d) '("L" "O" "K")) (setq i (+ i 2)))
         (T (setq res (strcat res d) i (+ i 2)))))
      ((member c '("{" "}")) (setq i (1+ i)))
      (T (setq res (strcat res c) i (1+ i)))))
  res
)

(defun ktsh:hex (s / i v d)
  (setq s (strcase s) i 1 v 0)
  (while (and v (<= i (strlen s)))
    (if (setq d (vl-string-search (substr s i 1) "0123456789ABCDEF"))
      (setq v (+ (* v 16) d))
      (setq v nil))
    (setq i (1+ i)))
  v
)

(defun ktsh:uchar (c)
  ;; ma Unicode chu Viet co dau -> chu khong dau (HOA)
  (cond ((and (>= c 7840) (<= c 7863)) "A")
        ((and (>= c 7864) (<= c 7879)) "E")
        ((and (>= c 7880) (<= c 7883)) "I")
        ((and (>= c 7884) (<= c 7907)) "O")
        ((and (>= c 7908) (<= c 7921)) "U")
        ((and (>= c 7922) (<= c 7929)) "Y")
        ((member c '(192 193 194 195 196 197 224 225 226 227 228 229 258 259)) "A")
        ((member c '(200 201 202 203 232 233 234 235)) "E")
        ((member c '(204 205 206 207 236 237 238 239 296 297)) "I")
        ((member c '(210 211 212 213 214 242 243 244 245 246 416 417)) "O")
        ((member c '(217 218 219 220 249 250 251 252 360 361 431 432)) "U")
        ((member c '(221 253)) "Y")
        ((member c '(208 240 272 273)) "D")
        (T ""))
)

(defun ktsh:unaccent (s / p h res)
  (setq s (strcase s) res "")
  (while (setq p (vl-string-search "\\U+" s))
    (setq h   (ktsh:hex (substr s (+ p 4) 4))
          res (strcat res (substr s 1 p) (if h (ktsh:uchar h) ""))
          s   (substr s (+ p 8))))
  (setq res (strcat res s))
  (apply 'strcat
         (mapcar '(lambda (c) (if (> c 127) (ktsh:uchar c) (chr c)))
                 (vl-string->list res)))
)

(defun ktsh:norm (s)
  ;; chuan hoa so sanh: bo dinh dang + dau, HOA, chi giu A-Z 0-9
  (if (= (type s) 'STR)
    (vl-list->string
      (vl-remove-if-not
        '(lambda (c) (or (and (>= c 48) (<= c 57)) (and (>= c 65) (<= c 90))))
        (vl-string->list (ktsh:unaccent (ktsh:plain s nil)))))
    "")
)

(defun ktsh:txt (ed / s)
  ;; noi dung TEXT/MTEXT (MTEXT dai: nhom 3 + nhom 1)
  (setq s "")
  (foreach x ed (if (= (car x) 3) (setq s (strcat s (cdr x)))))
  (strcat s (cond ((kt:dxf 1 ed)) ("")))
)

(defun ktsh:bname (en ed / nm)
  (setq nm (cond ((kt:dxf 2 ed)) ("")))
  (if (wcmatch nm "`**") (setq nm (cond ((kt:effname en)) (nm))))
  (strcase nm)
)

;;; ---------- khung ten ----------
;;; frame: (ename space minpt maxpt scale sohieu ten scale-ghi)
(defun ktsh:flabel (f)
  (if (and (nth 5 f) (/= (kt:trim (nth 5 f)) ""))
    (nth 5 f)
    (strcat "(chua so hieu, handle " (kt:str (car f)) ")"))
)

(defun ktsh:splitnum (s / u i)
  ;; "KT-01" -> ("KT" "01" "KT-") ; nil neu khong co so cuoi
  (if (= (type s) 'STR)
    (progn
      (setq u (strcase (kt:trim s)) i (strlen u))
      (while (and (> i 0) (wcmatch (substr u i 1) "#")) (setq i (1- i)))
      (if (< i (strlen u))
        (list (ktsh:norm (substr u 1 i)) (substr u (1+ i)) (substr u 1 i)))))
)

(defun ktsh:group (frames idx / g k r)
  ;; gom khung theo gia tri chuan hoa cua truong idx: ((key f1 f2 ...) ...)
  (foreach f frames
    (setq k (ktsh:norm (nth idx f)))
    (if (/= k "")
      (if (setq r (assoc k g))
        (setq g (subst (append r (list f)) r g))
        (setq g (cons (list k f) g)))))
  (reverse g)
)

;;; ---------- KHUNG-THIEU ----------
(defun ktsh:chk-thieu (frames / skip empt)
  (setq skip (kt:cfg-list "KHUNG_TAG_BO_QUA"))
  (foreach f frames
    (setq empt nil)
    (foreach a (kt:attribs (car f))
      (if (and (= (cdr a) "") (not (and skip (kt:wcmatch-any (car a) skip))))
        (setq empt (cons (car a) empt))))
    (if empt
      (kt:add "KHUNG" "KHUNG-THIEU" "LOI"
              (strcat "Khung ten " (ktsh:flabel f) " con " (itoa (length empt))
                      " o trong: " (kt:join (reverse empt) ", "))
              (car f) nil nil)))
)

;;; ---------- KHUNG-TRUNGSO / KHUNG-TRUNGTEN ----------
(defun ktsh:chk-trung (frames)
  (foreach g (ktsh:group frames 5)
    (if (cddr g)
      (kt:add "KHUNG" "KHUNG-TRUNGSO" "LOI"
              (strcat "So hieu " (kt:str (nth 5 (cadr g))) " bi trung o " (itoa (length (cdr g)))
                      " khung ten (ten: "
                      (kt:join (mapcar '(lambda (f) (kt:str (nth 6 f))) (cdr g)) " / ") ")")
              (mapcar 'car (cdr g)) nil nil)))
  (foreach g (ktsh:group frames 6)
    (if (cddr g)
      (kt:add "KHUNG" "KHUNG-TRUNGTEN" "CANHBAO"
              (strcat "Ten ban ve \"" (kt:str (nth 6 (cadr g))) "\" bi trung o "
                      (itoa (length (cdr g))) " khung ten: "
                      (kt:join (mapcar 'ktsh:flabel (cdr g)) ", "))
              (mapcar 'car (cdr g)) nil nil)))
)

;;; ---------- KHUNG-NHAYSO ----------
(defun ktsh:chk-nhayso (frames / recs g r grp nums w miss en prev raw lo hi k)
  ;; recs: (tien-to-chuan so-nguyen do-rong tien-to-goc frame)
  (foreach f frames
    (if (setq r (ktsh:splitnum (nth 5 f)))
      (setq recs (cons (list (car r) (atoi (cadr r)) (strlen (cadr r)) (caddr r) f) recs))))
  (foreach r (reverse recs)
    (if (setq grp (assoc (car r) g))
      (setq g (subst (append grp (list r)) grp g))
      (setq g (cons (list (car r) r) g))))
  (foreach grp (reverse g)
    (if (cddr grp)
      (progn
        (setq nums (ktsh:msort (cdr grp) '(lambda (a b) (< (cadr a) (cadr b))))
              w    (caddr (car nums))
              raw  (cadddr (car nums))
              miss nil en nil prev nil)
        (foreach r nums
          (if (and prev (> (- (cadr r) (cadr prev)) 1))
            (progn
              (if (null en) (setq en (car (nth 4 r))))
              (setq k (1+ (cadr prev)))
              (while (< k (cadr r))
                (setq miss (cons k miss) k (1+ k)))))
          (setq prev r))
        (if miss
          (progn
            (setq miss (reverse miss)
                  lo   (cadr (car nums))
                  hi   (cadr (last nums)))
            (kt:add "KHUNG" "KHUNG-NHAYSO" "CANHBAO"
                    (strcat "So hieu nhay coc (" raw (ktsh:pad lo w) " .. " raw (ktsh:pad hi w)
                            "): thieu " (itoa (length miss)) " so: "
                            (kt:join (mapcar '(lambda (m) (strcat raw (ktsh:pad m w)))
                                             (ktsh:head miss 20))
                                     ", ")
                            (if (> (length miss) 20) ", ..." ""))
                    en nil nil))))))
)

;;; ---------- KHUNG-TYLE ----------
(defun ktsh:allowed (/ res v)
  (foreach s (kt:cfg-list "TY_LE_CHO_PHEP")
    (if (setq v (cond ((kt:parse-scale s)) ((kt:num s))))
      (setq res (cons v res))))
  (reverse res)
)

(defun ktsh:chk-tyle (frames / allow row ed base real ghi raw sc vps ok)
  (setq allow (ktsh:allowed))
  (foreach f frames
    (setq ed   (entget (car f))
          row  (kt:cfg-row "KHUNG" (kt:effname (car f)))
          base (cond ((kt:num (nth 4 row))) (1.0))
          real (* (abs (cond ((kt:dxf 41 ed)) (1.0))) base)
          ghi  (nth 7 f)
          raw  (if (and (nth 3 row) (/= (nth 3 row) "")) (kt:attval (car f) (nth 3 row))))
    (cond
      ;; ghi nhung khong doc duoc
      ((and raw (/= raw "") (null ghi))
       (kt:add "KHUNG" "KHUNG-TYLE" "LOI"
               (strcat "Khung ten " (ktsh:flabel f) ": khong doc duoc ty le \"" raw
                       "\" (ghi dang 1/100 hoac 1:100)")
               (car f) nil nil))
      ;; Model: ty le ghi so voi scale thuc cua block khung
      ((and ghi (= (nth 1 f) "Model") (> real 0)
            (> (abs (- ghi real)) (max 0.01 (* 0.005 real))))
       (kt:add "KHUNG" "KHUNG-TYLE" "LOI"
               (strcat "Khung ten " (ktsh:flabel f) " ghi ty le " (ktsh:sc ghi)
                       " nhung khung chen theo ty le " (ktsh:sc real) " (scale X = "
                       (rtos (abs (cond ((kt:dxf 41 ed)) (1.0))) 2 3) " x he so goc "
                       (rtos base 2 3) ")")
               (car f) nil nil))
      ;; Layout: ty le ghi so voi viewport nam trong khung
      ((and ghi (/= (nth 1 f) "Model"))
       (setq vps nil ok nil)
       (foreach v (kt:viewports)
         (if (and (= (nth 1 v) (nth 1 f))
                  (kt:dxf 10 (entget (car v)))
                  (kt:inbox (kt:2d (kt:dxf 10 (entget (car v)))) (nth 2 f) (nth 3 f)))
           (progn
             (setq vps (cons (nth 2 v) vps))
             (if (<= (abs (- (nth 2 v) ghi)) (max 0.01 (* 0.005 ghi))) (setq ok T)))))
       (if (and vps (not ok))
         (kt:add "KHUNG" "KHUNG-TYLE" "LOI"
                 (strcat "Khung ten " (ktsh:flabel f) " ghi ty le " (ktsh:sc ghi)
                         " nhung viewport trong khung co ty le "
                         (kt:join (mapcar 'ktsh:sc (ktsh:uniq vps)) ", "))
                 (car f) nil nil))))
    ;; ty le cho phep
    (setq sc (cond (ghi) ((= (nth 1 f) "Model") real)))
    (if (and allow sc (not (vl-some '(lambda (a) (equal a sc 1e-6)) allow)))
      (kt:add "KHUNG" "KHUNG-TYLE" "LOI"
              (strcat "Khung ten " (ktsh:flabel f) ": ty le " (ktsh:sc sc)
                      " khong thuoc danh sach cho phep (" (kt:join (mapcar 'ktsh:sc allow) ", ") ")")
              (car f) nil nil)))
)

;;; ---------- doc chu ----------
;;; text: (ename space diem chieucao noidung-goc norm|nil)
(defun ktsh:texts (/ res ed p raw u)
  (foreach en (kt:ss-all '((0 . "TEXT,MTEXT")))
    (setq ed (entget en) p (kt:dxf 10 ed))
    (if (and p (/= (strcase (cond ((kt:dxf 8 ed)) (""))) (strcase *KT:LAYER*)))
      (progn
        (setq raw (ktsh:txt ed) u (strcase raw))
        (setq res (cons (list en (kt:space ed) (kt:2d p) (cond ((kt:dxf 40 ed)) (0.0)) raw
                              ;; chi chuan hoa chu co the la tieu de (tang toc)
                              (if (or (vl-string-search "\\U+" u) (vl-string-search "DANH" u)
                                      (vl-string-search "CAT" u) (vl-string-search "MUC" u))
                                (ktsh:norm raw)))
                        res)))))
  (reverse res)
)

;;; ---------- KHUNG-DANHMUC ----------
(defun ktsh:shcand (s prefs / sn)
  ;; chuoi co phai so hieu ban ve (cung tien to voi khung ten)?
  (setq sn (ktsh:splitnum s))
  (and sn (/= (car sn) "") (member (car sn) prefs) (<= (strlen (ktsh:norm s)) 15))
)

(defun ktsh:pickname (cells cand prefs / best n)
  ;; ten ban ve = o dai nhat cung hang (khong phai so hieu, STT, tieu de)
  (foreach c cells
    (setq n (ktsh:norm c))
    (if (and (not (equal c cand)) (/= n "") (not (ktsh:alldig n))
             (not (ktsh:shcand c prefs)) (not (vl-string-search "DANHMUC" n))
             (or (null best) (> (strlen n) (strlen (ktsh:norm best)))))
      (setq best c)))
  (if best (kt:trim (ktsh:plain best nil)) "")
)

(defun ktsh:table-cells (en / o r nr nc i j row res v ed strs)
  ;; o cua TABLE: list hang, moi hang list chuoi. ActiveX; du phong DXF (1/302)
  (setq r (vl-catch-all-apply
            '(lambda ()
               (setq o (vlax-ename->vla-object en))
               (list (vla-get-Rows o) (vla-get-Columns o))) ; lisplint: ignore=RISKY
            nil))
  (if (and (not (vl-catch-all-error-p r)) (numberp (car r)) (numberp (cadr r)))
    (progn
      (setq nr (car r) nc (cadr r) i 0)
      (while (< i nr)
        (setq j 0 row nil)
        (while (< j nc)
          (setq v (vl-catch-all-apply 'vla-GetText (list o i j)))
          (setq row (cons (if (= (type v) 'STR) (ktsh:plain v nil) "") row) j (1+ j)))
        (setq res (cons (reverse row) res) i (1+ i))))
    (progn
      (setq ed (entget en) nc (cond ((kt:dxf 92 ed)) (1)))
      (if (< nc 1) (setq nc 1))
      (foreach x ed
        (if (and (member (car x) '(1 302)) (= (type (cdr x)) 'STR))
          (setq strs (cons (ktsh:plain (cdr x) nil) strs))))
      (setq strs (reverse strs))
      (while strs
        (setq row nil j 0)
        (while (and strs (< j nc))
          (setq row (cons (car strs) row) strs (cdr strs) j (1+ j)))
        (setq res (cons (reverse row) res)))))
  (reverse res)
)

(defun ktsh:dm-rows (texts prefs / found rows tbl cells cand f mn mx h p its sp plain lines words c rowit name)
  ;; tra ve (found rows), rows: ((key sohieu ten ename) ...)
  ;; 1. TABLE
  (foreach en (kt:ss-all '((0 . "ACAD_TABLE")))
    (setq tbl (ktsh:table-cells en))
    (if (vl-some '(lambda (rw) (vl-some '(lambda (c) (vl-string-search "DANHMUC" (ktsh:norm c))) rw)) tbl)
      (progn
        (setq found T)
        (foreach rw tbl
          (setq cand nil)
          (foreach c rw (if (and (null cand) (ktsh:shcand c prefs)) (setq cand c)))
          (if cand
            (setq rows (cons (list (ktsh:norm cand) (kt:trim cand) (ktsh:pickname rw cand prefs) en)
                             rows)))))))
  ;; 2. TEXT/MTEXT tieu de "DANH MUC" + chu trong khung (hoac vung duoi tieu de)
  (foreach tt texts
    (if (and (nth 5 tt) (vl-string-search "DANHMUC" (nth 5 tt)))
      (progn
        (setq found T
              sp (nth 1 tt) p (nth 2 tt)
              h  (if (> (nth 3 tt) 0) (nth 3 tt) (* 2.5 (cond ((kt:scale-at p sp)) (1.0))))
              f  (kt:frame-at p sp))
        (if f
          (setq mn (nth 2 f) mx (nth 3 f))
          (setq mn (list (- (car p) (* 40.0 h)) (- (cadr p) (* 80.0 h)))
                mx (list (+ (car p) (* 60.0 h)) (+ (cadr p) (* 2.0 h)))))
        ;; its: (ename tam chieucao chuoi) ; MTEXT nhieu dong -> phan tich tung dong
        (setq its nil)
        (foreach x texts
          ;; ke ca chinh tieu de (MTEXT 1 khoi: tieu de + cac dong danh muc)
          (if (and (= (nth 1 x) sp) (kt:inbox (nth 2 x) mn mx))
            (progn
              (setq plain (ktsh:plain (nth 4 x) T))
              (if (vl-string-search "\n" plain)
                (foreach ln (kt:split plain "\n")
                  (setq words (vl-remove "" (kt:split (vl-string-translate "\t" " " ln) " "))
                        cand  nil)
                  (foreach w words (if (and (null cand) (ktsh:shcand w prefs)) (setq cand w)))
                  (if cand
                    (progn
                      ;; bo so hieu va cot ty le (1/100, 1:50) khoi ten
                      (setq name (vl-remove-if '(lambda (w) (or (= w cand) (wcmatch w "*#/#*,*#:#*")))
                                               words))
                      (if (and name (ktsh:alldig (ktsh:norm (car name)))) (setq name (cdr name)))
                      (setq rows (cons (list (ktsh:norm cand) cand (kt:join name " ") (car x)) rows)))))
                (setq its (cons (list (car x) (kt:cen (car x)) (nth 3 x) plain) its))))))
        ;; o don: gom theo hang (cung Y)
        (foreach c its
          (if (ktsh:shcand (nth 3 c) prefs)
            (progn
              (setq rowit nil)
              (foreach x its
                (if (<= (abs (- (cadr (nth 1 x)) (cadr (nth 1 c))))
                        (* 0.7 (max (nth 2 x) (nth 2 c) 1e-6)))
                  (setq rowit (cons (nth 3 x) rowit))))
              (setq rows (cons (list (ktsh:norm (nth 3 c)) (kt:trim (nth 3 c))
                                     (ktsh:pickname rowit (nth 3 c) prefs) (car c))
                               rows))))))))
  (list found (reverse rows))
)

(defun ktsh:chk-danhmuc (frames texts / fr prefs res found rows dm r k fm dmpref)
  (setq fr (vl-remove-if '(lambda (f) (= (ktsh:norm (nth 5 f)) "")) frames))
  (setq prefs (ktsh:uniq (vl-remove "" (vl-remove nil (mapcar '(lambda (f) (car (ktsh:splitnum (nth 5 f)))) fr)))))
  (if (and fr prefs)
    (progn
      (setq res (ktsh:dm-rows texts prefs) found (car res) rows (cadr res))
      ;; bo trung so hieu trong danh muc (giu dong dau)
      (foreach r rows (if (not (assoc (car r) dm)) (setq dm (cons r dm))))
      (setq dm (reverse dm))
      (cond
        ((not found)
         (kt:add "KHUNG" "KHUNG-DANHMUC" "GOIY" "Khong tim thay bang danh muc ban ve" nil nil nil))
        ((null dm)
         (kt:add "KHUNG" "KHUNG-DANHMUC" "GOIY"
                 (strcat "Tim thay tieu de/bang danh muc nhung khong doc duoc so hieu nao"
                         " (so hieu phai cung tien to voi khung ten, vd "
                         (kt:str (nth 5 (car fr))) ")")
                 nil nil nil))
        (T
         (setq dmpref (ktsh:uniq (mapcar '(lambda (r) (car (ktsh:splitnum (cadr r)))) dm)))
         ;; danh muc -> khung
         (foreach r dm
           (setq fm (vl-remove-if-not '(lambda (f) (= (ktsh:norm (nth 5 f)) (car r))) fr))
           (cond
             ((null fm)
              (kt:add "KHUNG" "KHUNG-DANHMUC" "CANHBAO"
                      (strcat "Danh muc co ban ve " (cadr r)
                              (if (/= (caddr r) "") (strcat " (" (caddr r) ")") "")
                              " nhung khong co khung ten nao mang so hieu nay")
                      (cadddr r) nil nil))
             ((and (/= (ktsh:norm (caddr r)) "") (/= (ktsh:norm (nth 6 (car fm))) "")
                   (/= (ktsh:norm (caddr r)) (ktsh:norm (nth 6 (car fm)))))
              (kt:add "KHUNG" "KHUNG-DANHMUC" "CANHBAO"
                      (strcat "Ten ban ve " (cadr r) " khong khop: danh muc \"" (caddr r)
                              "\", khung ten \"" (kt:str (nth 6 (car fm))) "\"")
                      (list (car (car fm)) (cadddr r)) nil nil))))
         ;; khung -> danh muc (chi xet tien to co trong danh muc)
         (foreach f fr
           (setq k (ktsh:norm (nth 5 f)))
           (if (and (not (assoc k dm))
                    (member (car (ktsh:splitnum (nth 5 f))) dmpref))
             (kt:add "KHUNG" "KHUNG-DANHMUC" "CANHBAO"
                     (strcat "Khung ten " (nth 5 f) " (" (kt:str (nth 6 f))
                             ") khong co trong bang danh muc ban ve")
                     (car f) nil nil)))))))
)

;;; ---------- KHUNG-THAMCHIEU ----------
(defun ktsh:title-has (n k / p)
  ;; ten chuan hoa n co dang "MATCAT..k.."?
  (and n (setq p (vl-string-search "MATCAT" n))
       (vl-string-search k (substr n (+ p 7))))
)

(defun ktsh:sheet-ok (ref frames shkeys / k sn)
  (setq k (ktsh:norm ref))
  (cond ((= k "") T)
        ((member k shkeys) T)
        ((ktsh:alldig k)
         (vl-some '(lambda (f)
                     (and (setq sn (ktsh:splitnum (nth 5 f))) (= (atoi (cadr sn)) (atoi k))))
                  frames))
        (T nil))
)

(defun ktsh:chk-thamchieu (frames texts / cmap ed nm r atts main key reft ref shkeys keys titles kv role)
  (foreach row (kt:cfg "BLOCK")
    (if (member (strcase (kt:str (cadr row))) '("MATCAT" "CHITIET"))
      (setq cmap (cons (list (strcase (kt:str (car row))) (strcase (kt:str (cadr row)))
                             (strcase (kt:str (caddr row))) (strcase (kt:str (cadddr row))))
                       cmap))))
  (if (null cmap)
    (kt:add "KHUNG" "KHUNG-THAMCHIEU" "GOIY"
            "Chua cau hinh BLOCK vai tro MATCAT/CHITIET trong file chuan: bo qua kiem tra ky hieu tham chieu"
            nil nil nil)
    (progn
      (setq shkeys (vl-remove "" (mapcar '(lambda (f) (ktsh:norm (nth 5 f))) frames)))
      (foreach en (kt:ss-all '((0 . "INSERT")))
        (setq ed (entget en))
        (if (and (= (kt:dxf 66 ed) 1) (setq r (assoc (ktsh:bname en ed) cmap)))
          (progn
            (setq atts (kt:attribs en)
                  role (cadr r)
                  main (caddr r)
                  key  (if (/= main "") (cdr (assoc main atts)) (cdar atts))
                  reft (cadddr r)
                  ref  (cond ((/= reft "") (cdr (assoc reft atts)))
                             (T (cdr (car (vl-remove-if-not
                                            '(lambda (a)
                                               (and (/= (car a) main) (/= (cdr a) "")
                                                    (kt:wcmatch-any (car a) '("*BV*" "*SHEET*" "*KH*" "*SO*BV*"))))
                                            atts))))))
            ;; so hieu ban ve tham chieu phai ton tai
            (if (and shkeys ref (not (ktsh:sheet-ok ref frames shkeys)))
              (kt:add "KHUNG" "KHUNG-THAMCHIEU" "LOI"
                      (strcat "Ky hieu " (if (= role "MATCAT") "mat cat" "chi tiet") " "
                              (kt:str key) " tro toi ban ve " ref " khong ton tai")
                      en nil nil))
            ;; gom ky hieu mat cat de kiem ban ve "MAT CAT x-x"
            (if (and (= role "MATCAT") (/= (ktsh:norm key) ""))
              (if (setq kv (assoc (ktsh:norm key) keys))
                (setq keys (subst (append kv (list en)) kv keys))
                (setq keys (cons (list (ktsh:norm key) key en) keys)))))))
      (if keys
        (progn
          (setq titles (append (mapcar '(lambda (f) (ktsh:norm (nth 6 f))) frames)
                               (vl-remove nil (mapcar '(lambda (x) (nth 5 x)) texts))))
          (foreach kv (reverse keys)
            (if (not (vl-some '(lambda (n) (ktsh:title-has n (car kv))) titles))
              (kt:add "KHUNG" "KHUNG-THAMCHIEU" "CANHBAO"
                      (strcat "Ky hieu mat cat " (cadr kv) " (" (itoa (length (cddr kv)))
                              " cho) nhung khong co ban ve/tieu de nao ten \"MAT CAT "
                              (cadr kv) "\"")
                      (cddr kv) nil nil)))))))
)

;;; ---------- KHUNG-NGOAI ----------
(defun ktsh:in-any (p mf / res)
  (if (and *KT:SHL* (kt:inbox p (nth 2 *KT:SHL*) (nth 3 *KT:SHL*)))
    (setq res *KT:SHL*)
    (foreach f mf
      (if (and (not res) (kt:inbox p (nth 2 f) (nth 3 f))) (setq res f))))
  (if res (setq *KT:SHL* res))
  res
)

(defun ktsh:chk-ngoai (frames / mf fens skip umn umx cw ch ed typ p key cells cell n)
  (setq mf (vl-remove-if-not '(lambda (f) (= (nth 1 f) "Model")) frames))
  (if mf
    (progn
      (setq fens (mapcar 'car mf)
            skip (kt:cfg-list "LAYER_BO_QUA")
            cw   (/ (apply '+ (mapcar '(lambda (f) (- (car (nth 3 f)) (car (nth 2 f)))) mf)) (length mf))
            ch   (/ (apply '+ (mapcar '(lambda (f) (- (cadr (nth 3 f)) (cadr (nth 2 f)))) mf)) (length mf))
            umn  (list (apply 'min (mapcar '(lambda (f) (car (nth 2 f))) mf))
                       (apply 'min (mapcar '(lambda (f) (cadr (nth 2 f))) mf)))
            umx  (list (apply 'max (mapcar '(lambda (f) (car (nth 3 f))) mf))
                       (apply 'max (mapcar '(lambda (f) (cadr (nth 3 f))) mf)))
            *KT:SHL* nil)
      (if (<= cw 0) (setq cw 1.0))
      (if (<= ch 0) (setq ch 1.0))
      (foreach en (kt:ss-all '((410 . "Model")))
        (setq ed (entget en) typ (kt:dxf 0 ed))
        (if (and (not (member typ '("VIEWPORT" "XLINE" "RAY")))
                 (not (member en fens))
                 (/= (strcase (cond ((kt:dxf 8 ed)) (""))) (strcase *KT:LAYER*))
                 (not (and skip (kt:wcmatch-any (cond ((kt:dxf 8 ed)) ("")) skip)))
                 (setq p (if (= typ "HATCH") (kt:cen en) (kt:dxf 10 ed))))
          (progn
            (setq p (kt:2d p))
            (if (or (not (kt:inbox p umn umx)) (not (ktsh:in-any p mf)))
              (progn
                (setq key (list (ktsh:floor (/ (- (car p) (car umn)) cw))
                                (ktsh:floor (/ (- (cadr p) (cadr umn)) ch))))
                ;; cell: (key so-luong tong-x tong-y (ename mau...))
                (if (setq cell (assoc key cells))
                  (setq cells (subst (list key (1+ (cadr cell)) (+ (caddr cell) (car p))
                                           (+ (cadddr cell) (cadr p))
                                           (if (< (length (nth 4 cell)) 30)
                                             (cons en (nth 4 cell))
                                             (nth 4 cell)))
                                     cell cells))
                  (if (< (length cells) 200)
                    (setq cells (cons (list key 1 (car p) (cadr p) (list en)) cells)))))))))
      (foreach c (reverse cells)
        (setq n (cadr c))
        (kt:add "KHUNG" "KHUNG-NGOAI" "GOIY"
                (strcat "Co " (itoa n) " doi tuong trong Model nam ngoai moi khung ten (vung quanh "
                        (rtos (/ (caddr c) n) 2 0) "," (rtos (/ (cadddr c) n) 2 0) ")")
                (reverse (nth 4 c))
                (list (/ (caddr c) n) (/ (cadddr c) n))
                (* 0.5 (max cw ch))))))
)

;;; ---------- chay ----------
(defun ktsh:run (/ frames texts)
  (if (kt:cfg-ok)
    (progn
      (kt:begin "KHUNG")
      (setq frames (kt:frames) *KT:SHL* nil)
      (if (null frames)
        (kt:add "KHUNG" "KHUNG-KHONGCO" "CANHBAO"
                "Khong tim thay khung ten nao (kiem tra ten block trong muc KHUNG cua file chuan)"
                nil nil nil)
        (progn
          (ktsh:try "o trong" 'ktsh:chk-thieu (list frames))
          (ktsh:try "trung so hieu/ten" 'ktsh:chk-trung (list frames))
          (ktsh:try "nhay so" 'ktsh:chk-nhayso (list frames))
          (ktsh:try "ty le" 'ktsh:chk-tyle (list frames))
          (setq texts (ktsh:try "doc chu" 'ktsh:texts nil))
          (ktsh:try "danh muc" 'ktsh:chk-danhmuc (list frames texts))
          (ktsh:try "tham chieu" 'ktsh:chk-thamchieu (list frames texts))
          (ktsh:try "ngoai khung" 'ktsh:chk-ngoai (list frames))
          (princ (strcat "\n[KHUNG] " (itoa (length frames)) " khung ten."))))
      (setq *KT:SHL* nil)
      (kt:finish "KHUNG")))
  (princ)
)

(defun c:KTKHUNG () (ktsh:run) (princ))

(princ "\nKT_Sheet: lenh KTKHUNG (khung ten / so hieu / danh muc / tham chieu).")
(princ)
