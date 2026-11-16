;;; ============================================================
;;; KT_Sheet.lsp  -  Module "KHUNG": khung ten, so hieu, danh muc, tham chieu
;;; ------------------------------------------------------------
;;; Lenh: KTKHUNG        Ham khong hoi: (ktsh:run)
;;; Can: KT_Core.lsp (nap truoc). Khung ten = block trong muc KHUNG cua file chuan.
;;;
;;; Ma loi:
;;;   KHUNG-KHONGCO    (CANHBAO) khong tim thay khung ten nao
;;;   KHUNG-THIEU      (LOI)     tag so hieu / ten / ty le de trong
;;;                    (CANHBAO) tag khac de trong trong khi >= 1/2 khung khac da dien
;;;                              (bo qua tag khop SETTING KHUNG_TAG_BO_QUA, vd NGAY*,GHICHU)
;;;   KHUNG-TRUNGSO    (LOI)     2 khung cung so hieu
;;;   KHUNG-TRUNGTEN   (CANHBAO) 2 khung cung ten ban ve (gop TENBANVE1 + TENBANVE2... / tag "A+B");
;;;                              bo nhieu to so hieu LIEN TIEP (C/01..C/07) khong bao (SETTING
;;;                              KHUNG_TRUNGTEN_LIENTIEP=1 -> GOIY)
;;;   KHUNG-NHAYSO     (GOIY)    so hieu nhay coc trong cung tien to (KT-02 -> KT-04);
;;;                              so >= 3 chu so (A-101, A-201) xet rieng tung tram
;;;   KHUNG-TYLE       (LOI)     ty le ghi khac ty le thuc (Model: scale X x ty le goc;
;;;                              Layout: viewport trong khung). Ghi nhieu ty le: khop 1 la du
;;;                    (CANHBAO) moi khung Model lech cung 1 ti so (he so goc sai) -> 1 dong;
;;;                              ty le khong thuoc TY_LE_CHO_PHEP
;;;                    (GOIY)    co chu so nhung khong doc duoc ("NHU HINH", "-": bo qua)
;;;   KHUNG-DANHMUC    (CANHBAO) danh muc va khung ten khong khop (ten: so khong dau, chap
;;;                              nhan 1 ten chua ten kia)
;;;                    (GOIY)    khong co danh muc / so hieu chi gom chu so / > 1/2 ban ve
;;;                              danh muc khong co trong file (ho so tach file) -> 1 dong
;;;   KHUNG-THAMCHIEU  (CANHBAO) ky hieu mat cat/chi tiet tro toi so hieu cung tien to, trong
;;;                              khoang so cua file, ma khong co (file + danh muc)
;;;                    (GOIY)    nhu tren nhung ngoai khoang (ban ve o file khac?); so hieu
;;;                              tien to khac (KC-.., D-..) khong xet
;;;                    (CANHBAO) ky hieu mat cat 1-1 (tro toi ban ve trong file) nhung khong co
;;;                              ban ve/tieu de "MAT CAT 1-1"
;;;   KHUNG-NGOAI      (GOIY)    doi tuong trong Model nam ngoai moi khung ten va moi vung
;;;                              viewport (gom o luoi, bao 20 o dong nhat + 1 dong tong)
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

(defun ktsh:msort (lst f) (kt:msort lst f))   ; merge sort on dinh (loi)
(defun ktsh:uniq (lst) (kt:uniq lst))

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

;;; ---------- chuoi: ham loi (kt:plain kt:norm kt:txt) + font TCVN3 ----------
(defun ktsh:plain (s nl) (kt:plain s nl))
(defun ktsh:txt (ed) (kt:txt ed))

(defun ktsh:tc (c)
  ;; byte TCVN3 (ABC, font .VnTime/.VnTimeH) -> chu goc HOA; nil neu khong phai chu
  (cond ((or (member c '(161 162 168 169)) (and (>= c 181) (<= c 185))
             (and (>= c 187) (<= c 190)) (and (>= c 198) (<= c 203))) "A")
        ((member c '(167 174)) "D")
        ((or (member c '(163 170)) (and (>= c 204) (<= c 214))) "E")
        ((and (>= c 215) (<= c 222)) "I")
        ((or (member c '(164 165 171 172)) (and (>= c 223) (<= c 238))) "O")
        ((or (member c '(166 173)) (and (>= c 239) (<= c 249))) "U")
        ((and (>= c 250) (<= c 254)) "Y"))
)

(defun ktsh:tcvn3 (s / l)
  ;; chuoi go TCVN3 -> ASCII HOA; nil neu khong co byte dac trung TCVN3
  ;; (byte 161-254 khong phai chu Viet Latin-1/CP1258, tru ky hieu do, +-, mu, x, phi)
  (setq l (vl-string->list (kt:str s)))
  (if (vl-some '(lambda (c) (and (>= c 161) (<= c 254)
                                 (not (member c '(176 177 178 179 215 216 222
                                                  192 193 194 195 200 201 202 204 205 208 210 211 212
                                                  213 217 218 221 224 225 226 227 232 233 234 236 237
                                                  240 242 243 244 245 249 250 253)))))
               l)
    (apply 'strcat (mapcar '(lambda (c) (cond ((< c 128) (strcase (chr c))) ((ktsh:tc c)) (T ""))) l)))
)

(defun ktsh:norm (s / t3)
  ;; chuan hoa so sanh: bo dinh dang + dau (Unicode, \U+, CP1258, TCVN3), HOA, chi giu A-Z 0-9
  ;; (%%u %%o %%k gach chan/tren cua TEXT cung bi bo)
  (if (= (type s) 'STR)
    (progn
      (foreach k '("%%U" "%%u" "%%O" "%%o" "%%K" "%%k")
        (while (vl-string-search k s) (setq s (vl-string-subst "" k s))))
      (if (setq t3 (ktsh:tcvn3 (kt:plain s nil))) (kt:norm t3) (kt:norm s)))
    "")
)

(defun ktsh:name-eq (a b / na nb)
  ;; 2 ten ban ve "giong nhau": bang nhau sau chuan hoa, hoac 1 ten chua ten kia
  ;; (khung ten tach 2 dong "MAT BANG" / "TANG 1", danh muc ghi tat...)
  (setq na (ktsh:norm a) nb (ktsh:norm b))
  (or (= na "") (= nb "") (= na nb)
      (and (>= (min (strlen na) (strlen nb)) 4)
           (or (vl-string-search na nb) (vl-string-search nb na))))
)

(defun ktsh:bname (en ed / nm)
  (setq nm (cond ((kt:dxf 2 ed)) ("")))
  (if (wcmatch nm "`**") (setq nm (cond ((kt:effname en)) (nm))))
  (kt:ukey nm)
)

;;; ---------- khung ten ----------
;;; frame: (ename space minpt maxpt scale sohieu ten scale-ghi)
(defun ktsh:flabel (f)
  (if (and (nth 5 f) (/= (kt:trim (nth 5 f)) ""))
    (nth 5 f)
    (strcat "(chua so hieu, handle " (kt:str (car f)) ")"))
)

(defun ktsh:stripdig (s / i)
  ;; "TENBANVE2" -> "TENBANVE"
  (setq s (kt:str s) i (strlen s))
  (while (and (> i 0) (wcmatch (substr s i 1) "#,_, ")) (setq i (1- i)))
  (substr s 1 i)
)

(defun ktsh:ftitle (f / row tg base res)
  ;; ten ban ve day du: tag ten + cac tag cung goc (TENBANVE1 "MAT BANG" + TENBANVE2 "TANG 1")
  (setq row (kt:cfg-row "KHUNG" (kt:effname (car f)))
        tg  (if row (strcase (kt:str (nth 2 row))) ""))
  ;; "TEN_BAN_VE+TEN_CONG_TRINH": kt:frames da noi cac dong (kt:attval)
  (if (and (/= tg "") (not (vl-string-search "+" tg)))
    (progn
      (setq base (ktsh:stripdig tg))
      (foreach a (kt:attribs (car f))
        (if (and (= (ktsh:stripdig (car a)) base) (/= (cdr a) "")) (setq res (cons (cdr a) res))))))
  (if res (kt:join (reverse res) " ") (nth 6 f))
)

(defun ktsh:splitnum (s / u i)
  ;; "KT-01" -> ("KT" "01" "KT-") ; "01" -> ("" "01" "") ; nil neu khong co so cuoi
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
;;; - tag so hieu / ten / ty le (muc KHUNG) de trong -> LOI
;;; - tag khac de trong: chi CANHBAO khi >= 1/2 so khung DA DIEN tag do (tag de trong o
;;;   moi khung = o tuy chon nhu LAN SUA, GHI CHU -> khong bao)
(defun ktsh:chk-thieu (frames / skip stat it row core empt emp2 subs)
  (setq skip (kt:cfg-list "KHUNG_TAG_BO_QUA"))
  ;; stat: (TAG so-lan-co so-lan-da-dien)
  (foreach f frames
    (foreach a (kt:attribs (car f))
      (setq it   (assoc (car a) stat)
            stat (cons (list (car a) (1+ (if it (cadr it) 0))
                             (+ (if it (caddr it) 0) (if (= (cdr a) "") 0 1)))
                       (if it (vl-remove it stat) stat)))))
  (foreach f frames
    ;; tag ten "A+B": A bat buoc, B (dong 2 cua ten ban ve) tuy chon
    (setq row  (kt:cfg-row "KHUNG" (kt:effname (car f)))
          core (vl-remove "" (mapcar 'kt:tag1 (list (nth 1 row) (nth 2 row) (nth 3 row))))
          subs (mapcar 'strcase (cdr (kt:split (kt:str (nth 2 row)) "+")))
          empt nil emp2 nil)
    (foreach a (kt:attribs (car f))
      (if (and (= (cdr a) "") (not (member (car a) subs))
               (not (and skip (kt:wcmatch-any (car a) skip))))
        (cond ((member (car a) core) (setq empt (cons (car a) empt)))
              ((and (setq it (assoc (car a) stat)) (> (caddr it) 0) (>= (* 2 (caddr it)) (cadr it)))
               (setq emp2 (cons (car a) emp2))))))
    (if empt
      (kt:add "KHUNG" "KHUNG-THIEU" "LOI"
              (strcat "Khung ten " (ktsh:flabel f) " chua dien: " (kt:join (reverse empt) ", "))
              (car f) nil nil))
    (if emp2
      (kt:add "KHUNG" "KHUNG-THIEU" "CANHBAO"
              (strcat "Khung ten " (ktsh:flabel f) " con o trong (cac khung khac da dien): "
                      (kt:join (reverse emp2) ", "))
              (car f) nil nil)))
)

;;; ---------- KHUNG-TRUNGSO / KHUNG-TRUNGTEN ----------
(defun ktsh:series-p (fs / ns pre r ok)
  ;; T neu cac khung cung ten co so hieu LIEN TIEP cung tien to (bo nhieu to: C/01..C/07)
  (foreach f fs
    (setq r (ktsh:splitnum (nth 5 f)))
    (if (and r (/= (cadr r) "") (or (null pre) (= (car r) pre)))
      (setq pre (car r) ns (cons (atoi (cadr r)) ns))
      (setq pre 'BAD)))
  (if (and (/= pre 'BAD) ns (= (length ns) (length fs)))
    (progn
      (setq ns (ktsh:msort ns '<) ok T)
      (while (cdr ns)
        (if (> (- (cadr ns) (car ns)) 1) (setq ok nil))
        (setq ns (cdr ns)))
      ok))
)

(defun ktsh:chk-trung (frames / ser)
  (setq ser (fix (kt:cfg-num "KHUNG_TRUNGTEN_LIENTIEP" 0)))
  (foreach g (ktsh:group frames 5)
    (if (cddr g)
      (kt:add "KHUNG" "KHUNG-TRUNGSO" "LOI"
              (strcat "So hieu " (kt:str (nth 5 (cadr g))) " bi trung o " (itoa (length (cdr g)))
                      " khung ten (ten: "
                      (kt:join (mapcar '(lambda (f) (kt:str (nth 6 f))) (cdr g)) " / ") ")")
              (mapcar 'car (cdr g)) nil nil)))
  ;; trung ten: bo nhieu to lien tiep (quy cach cong ty) -> bo qua (KHUNG_TRUNGTEN_LIENTIEP=1: GOIY)
  (foreach g (ktsh:group frames 6)
    (if (and (cddr g) (not (and (= ser 0) (ktsh:series-p (cdr g)))))
      (kt:add "KHUNG" "KHUNG-TRUNGTEN" (if (ktsh:series-p (cdr g)) "GOIY" "CANHBAO")
              (strcat "Ten ban ve \"" (kt:str (nth 6 (cadr g))) "\" bi trung o "
                      (itoa (length (cdr g))) " khung ten (copy quen sua ten?): "
                      (kt:join (mapcar 'ktsh:flabel (cdr g)) ", "))
              (mapcar 'car (cdr g)) nil nil)))
)

;;; ---------- KHUNG-NHAYSO ----------
;;; GOIY: ho so thuong tach nhieu file (moi file 1 phan so hieu) -> nhay so chua chac la loi.
;;; So hieu >= 3 chu so (A-101, A-201: tang 1 / tang 2) xet rieng tung tram.
(defun ktsh:chk-nhayso (frames / recs g r grp nums w miss en prev raw lo hi k key)
  ;; recs: (khoa so-nguyen do-rong tien-to-goc frame)
  (foreach f frames
    (if (and (setq r (ktsh:splitnum (nth 5 f))) (/= (cadr r) ""))
      (setq key  (strcat (car r) "|" (if (>= (strlen (cadr r)) 3) (itoa (/ (atoi (cadr r)) 100)) ""))
            recs (cons (list key (atoi (cadr r)) (strlen (cadr r)) (caddr r) f) recs))))
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
            (kt:add "KHUNG" "KHUNG-NHAYSO" "GOIY"
                    (strcat "So hieu nhay coc (" raw (ktsh:pad lo w) " .. " raw (ktsh:pad hi w)
                            "): thieu " (itoa (length miss)) " so: "
                            (kt:join (mapcar '(lambda (m) (strcat raw (ktsh:pad m w)))
                                             (ktsh:head miss 20))
                                     ", ")
                            (if (> (length miss) 20) ", ..." "")
                            " (bo qua neu cac ban ve do o file khac)")
                    en nil nil))))))
)

;;; ---------- KHUNG-TYLE ----------
(defun ktsh:allowed (/ res v)
  (foreach s (kt:cfg-list "TY_LE_CHO_PHEP")
    (if (setq v (cond ((kt:parse-scale s)) ((kt:num s))))
      (setq res (cons v res))))
  (reverse res)
)

(defun ktsh:scales (s / res p st b u n)
  ;; moi ty le ghi trong chuoi: "1/100" -> (100.0) ; "TL 1/50; 1/20" -> (50.0 20.0)
  ;; "100" -> (100.0) ; "NHU HINH" / "-" -> nil
  (if (= (type s) 'STR)
    (progn
      (setq u (vl-string-translate ":" "/" (strcase s)) st 0)
      (while (vl-string-search " /" u) (setq u (vl-string-subst "/" " /" u)))
      (while (vl-string-search "/ " u) (setq u (vl-string-subst "/" "/ " u)))
      (while (setq p (vl-string-search "1/" u st))
        (if (and (or (= p 0) (not (wcmatch (substr u p 1) "#,.")))
                 (setq b (kt:num (kt:numhead (substr u (+ p 3))))) (> b 0))
          (setq res (cons b res)))
        (setq st (1+ p)))
      (if (and (null res) (setq n (kt:num s)) (>= n 1)) (setq res (list n)))))
  (reverse res)
)

(defun ktsh:okscale (ghis vals)
  ;; 1 ty le ghi khop 1 ty le thuc (0.5%)
  (vl-some '(lambda (g) (vl-some '(lambda (v) (<= (abs (- g v)) (max 0.01 (* 0.005 v)))) vals)) ghis)
)

(defun ktsh:chk-tyle (frames / allow row ed base real raw ghis vps mism nmod rat r0 same)
  (setq allow (ktsh:allowed) nmod 0)
  (foreach f frames
    (setq ed   (entget (car f))
          row  (kt:cfg-row "KHUNG" (kt:effname (car f)))
          base (cond ((kt:num (nth 4 row))) (1.0))
          real (* (abs (cond ((kt:dxf 41 ed)) (1.0))) base)
          raw  (if (and (nth 3 row) (/= (nth 3 row) "")) (kt:attval (car f) (nth 3 row)))
          ghis (ktsh:scales raw))
    (cond
      ;; co chu so nhung khong doc duoc ("TL 100"...). Chu "NHU HINH", "-" -> bo qua
      ((and raw (null ghis) (wcmatch raw "*#*"))
       (kt:add "KHUNG" "KHUNG-TYLE" "GOIY"
               (strcat "Khung ten " (ktsh:flabel f) ": khong doc duoc ty le \"" raw
                       "\" (ghi dang 1/100 hoac 1:100)")
               (car f) nil nil))
      ;; Model: ty le ghi so voi scale thuc cua block khung
      ((and ghis (= (nth 1 f) "Model") (> real 0))
       (setq nmod (1+ nmod))
       (if (not (ktsh:okscale ghis (list real)))
         (setq mism (cons (list f (car ghis) real (abs (cond ((kt:dxf 41 ed)) (1.0))) base) mism))))
      ;; Layout: ty le ghi so voi viewport nam trong khung
      ((and ghis (/= (nth 1 f) "Model"))
       (setq vps nil)
       (foreach v (kt:viewports)
         (if (and (= (nth 1 v) (nth 1 f))
                  (kt:dxf 10 (entget (car v)))
                  (kt:inbox (kt:2d (kt:dxf 10 (entget (car v)))) (nth 2 f) (nth 3 f)))
           (setq vps (cons (nth 2 v) vps))))
       (if (and vps (not (ktsh:okscale ghis vps)))
         (kt:add "KHUNG" "KHUNG-TYLE" "LOI"
                 (strcat "Khung ten " (ktsh:flabel f) " ghi ty le " (kt:join (mapcar 'ktsh:sc ghis) ", ")
                         " nhung viewport trong khung co ty le "
                         (kt:join (mapcar 'ktsh:sc (ktsh:uniq vps)) ", "))
                 (car f) nil nil))))
    ;; ty le cho phep (CANHBAO: chuan cong ty, khong phai sai ban ve)
    (foreach sc (cond (ghis) ((= (nth 1 f) "Model") (list real)))
      (if (and allow (not (vl-some '(lambda (a) (equal a sc (max 1e-6 (* 0.005 a)))) allow)))
        (kt:add "KHUNG" "KHUNG-TYLE" "CANHBAO"
                (strcat "Khung ten " (ktsh:flabel f) ": ty le " (ktsh:sc sc)
                        " khong thuoc danh sach cho phep (" (kt:join (mapcar 'ktsh:sc allow) ", ") ")")
                (car f) nil nil))))
  ;; moi khung Model deu lech cung 1 ti so -> he so goc trong muc KHUNG sai (1 dong thay vi N dong)
  (if mism
    (progn
      (setq rat  (mapcar '(lambda (m) (/ (cadr m) (caddr m))) mism)
            r0   (car rat)
            same (and (cdr mism) (= (length mism) nmod)
                      (vl-every '(lambda (x) (<= (abs (- x r0)) (* 0.005 r0))) rat)))
      (if same
        (kt:add "KHUNG" "KHUNG-TYLE" "CANHBAO"
                (strcat "Ca " (itoa (length mism)) " khung ten trong Model ghi ty le = " (rtos r0 2 3)
                        " x (scale X x he so goc): kiem tra cot 'ty le goc' cua dong KHUNG trong file chuan")
                (mapcar '(lambda (m) (car (car m))) mism) nil nil)
        (foreach m mism
          (kt:add "KHUNG" "KHUNG-TYLE" "LOI"
                  (strcat "Khung ten " (ktsh:flabel (car m)) " ghi ty le " (ktsh:sc (cadr m))
                          " nhung khung chen theo ty le " (ktsh:sc (caddr m)) " (scale X = "
                          (rtos (nth 3 m) 2 3) " x he so goc " (rtos (nth 4 m) 2 3) ")")
                  (car (car m)) nil nil)))))
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
                              ;; chi chuan hoa chu co the la tieu de (tang toc); chu co dau dang
                              ;; Unicode/CP1258/TCVN3 (ma > 127) cung phai chuan hoa
                              (if (or (vl-string-search "\\U+" u) (vl-string-search "DANH" u)
                                      (vl-string-search "CAT" u) (vl-string-search "MUC" u)
                                      (vl-some '(lambda (c) (> c 127)) (vl-string->list raw)))
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

(defun ktsh:okname (c cand prefs / n)
  ;; o co the la ten ban ve (khong phai so hieu, STT, ty le, tieu de)
  (setq n (ktsh:norm c))
  (and (not (equal c cand)) (>= (strlen n) 3) (not (ktsh:alldig n))
       (not (ktsh:shcand c prefs)) (not (vl-string-search "DANHMUC" n)))
)

(defun ktsh:pickname (cells cand prefs / best)
  ;; TABLE: ten ban ve = o dai nhat cung hang
  (foreach c cells
    (if (and (ktsh:okname c cand prefs)
             (or (null best) (> (strlen (ktsh:norm c)) (strlen (ktsh:norm best)))))
      (setq best c)))
  (if best (kt:trim (ktsh:plain best nil)) "")
)

(defun ktsh:dm-title-p (n / p)
  ;; tieu de danh muc: "DANH MUC BAN VE", "BANG DANH MUC..." (khong phai ghi chu "XEM DANH MUC...")
  (and n (setq p (vl-string-search "DANHMUC" n)) (<= p 6))
)

(defun ktsh:table-cells (en / o r nr nc i j row res v ed strs)
  ;; o cua TABLE: (tin-cay hang1 hang2 ...), moi hang list chuoi. ActiveX; du phong DXF (1/302):
  ;; o rong khong co nhom 1 -> cot lech -> tin-cay = nil (chi dung so hieu, bo ten)
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
        (setq res (cons (reverse row) res)))
      (setq res (append res (list 'DXF)))))
  (if (= (last res) 'DXF)
    (cons nil (cdr (reverse res)))
    (cons T (reverse res)))
)

(defun ktsh:dm-rows (texts prefs / found rows tbl ok cand f mn mx h p its sp plain words rowit name best bd d)
  ;; tra ve (found rows), rows: ((key sohieu ten ename) ...); ten "" = khong doc chac
  ;; 1. TABLE
  (foreach en (kt:ss-all '((0 . "ACAD_TABLE")))
    (setq tbl (ktsh:table-cells en) ok (car tbl) tbl (cdr tbl))
    (if (vl-some '(lambda (rw) (vl-some '(lambda (c) (ktsh:dm-title-p (ktsh:norm c))) rw)) tbl)
      (progn
        (setq found T)
        (foreach rw tbl
          (setq cand nil)
          (foreach c rw (if (and (null cand) (ktsh:shcand c prefs)) (setq cand c)))
          (if cand
            (setq rows (cons (list (ktsh:norm cand) (kt:trim cand)
                                   (if ok (ktsh:pickname rw cand prefs) "") en)
                             rows)))))))
  ;; 2. TEXT/MTEXT tieu de "DANH MUC" + chu trong khung (hoac vung duoi tieu de)
  (foreach tt texts
    (if (ktsh:dm-title-p (nth 5 tt))
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
        ;; o don: cung hang (cung Y), ten = o hop le GAN NHAT theo X (danh muc 2 cot canh nhau,
        ;; cot ten truoc hay sau cot so hieu deu dung)
        (foreach c its
          (if (ktsh:shcand (nth 3 c) prefs)
            (progn
              (setq best nil bd nil)
              (foreach x its
                (if (and (<= (abs (- (cadr (nth 1 x)) (cadr (nth 1 c))))
                             (* 0.7 (max (nth 2 x) (nth 2 c) 1e-6)))
                         (ktsh:okname (nth 3 x) (nth 3 c) prefs))
                  (progn
                    (setq d (abs (- (car (nth 1 x)) (car (nth 1 c)))))
                    (if (or (null bd) (< d bd)) (setq bd d best x)))))
              (setq rows (cons (list (ktsh:norm (nth 3 c)) (kt:trim (nth 3 c))
                                     (if best (kt:trim (nth 3 best)) "") (car c))
                               rows))))))))
  (list found (reverse rows))
)

(defun ktsh:chk-danhmuc (frames texts / fr prefs res found rows dm r k fm dmpref miss)
  ;; tra ve danh muc doc duoc (dung cho KHUNG-THAMCHIEU)
  (setq fr (vl-remove-if '(lambda (f) (= (ktsh:norm (nth 5 f)) "")) frames))
  (setq prefs (ktsh:uniq (vl-remove "" (vl-remove nil (mapcar '(lambda (f) (car (ktsh:splitnum (nth 5 f)))) fr)))))
  (cond
    ((null fr) nil)
    ((null prefs)
     (kt:add "KHUNG" "KHUNG-DANHMUC" "GOIY"
             "So hieu khung ten chi gom chu so (01, 02...): khong doi chieu duoc voi danh muc (de lan voi STT)"
             nil nil nil))
    (T
     (setq res (ktsh:dm-rows texts prefs) found (car res) rows (cadr res))
     ;; bo trung so hieu trong danh muc (giu dong dau)
     (foreach r rows (if (not (assoc (car r) dm)) (setq dm (cons r dm))))
     (setq dm (reverse dm))
     (cond
       ((not found)
        (kt:add "KHUNG" "KHUNG-DANHMUC" "GOIY" "Khong tim thay bang danh muc ban ve trong file nay" nil nil nil))
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
            ((null fm) (setq miss (cons r miss)))
            ((not (ktsh:name-eq (caddr r) (nth 6 (car fm))))
             (kt:add "KHUNG" "KHUNG-DANHMUC" "CANHBAO"
                     (strcat "Ten ban ve " (cadr r) " khong khop: danh muc \"" (caddr r)
                             "\", khung ten \"" (kt:str (nth 6 (car fm))) "\"")
                     (list (car (car fm)) (cadddr r)) nil nil))))
        ;; ban ve co trong danh muc ma khong co khung: nhieu -> ho so tach nhieu file -> 1 GOIY
        (setq miss (reverse miss))
        (if (> (length miss) (max 3 (/ (length dm) 2)))
          (kt:add "KHUNG" "KHUNG-DANHMUC" "GOIY"
                  (strcat (itoa (length miss)) "/" (itoa (length dm))
                          " ban ve trong danh muc khong co khung ten trong file nay (ho so tach nhieu file?): "
                          (kt:join (mapcar 'cadr (ktsh:head miss 15)) ", ")
                          (if (> (length miss) 15) ", ..." ""))
                  (cadddr (car miss)) nil nil)
          (foreach r miss
            (kt:add "KHUNG" "KHUNG-DANHMUC" "CANHBAO"
                    (strcat "Danh muc co ban ve " (cadr r)
                            (if (/= (caddr r) "") (strcat " (" (caddr r) ")") "")
                            " nhung khong co khung ten nao mang so hieu nay")
                    (cadddr r) nil nil)))
        ;; khung -> danh muc (chi xet tien to co trong danh muc)
        (foreach f fr
          (setq k (ktsh:norm (nth 5 f)))
          (if (and (not (assoc k dm))
                   (member (car (ktsh:splitnum (nth 5 f))) dmpref))
            (kt:add "KHUNG" "KHUNG-DANHMUC" "CANHBAO"
                    (strcat "Khung ten " (nth 5 f) " (" (kt:str (nth 6 f))
                            ") khong co trong bang danh muc ban ve")
                    (car f) nil nil)))))))
  (if (listp dm) dm)
)

;;; ---------- KHUNG-THAMCHIEU ----------
(defun ktsh:title-has (n k / p r)
  ;; ten chuan hoa n co dang "MATCAT k-k ..." ("MAT CAT A-A VA B-B" cung nhan B)
  (and n (setq p (vl-string-search "MATCAT" n))
       (setq r (substr n (+ p 7)))
       (or (= (substr r 1 (strlen k)) k) (vl-string-search (strcat k k) r)))
)

(defun ktsh:refstat (ref frames shkeys prefs dm / k sn nums n)
  ;; 'OK: ban ve ton tai trong file / danh muc ; 'SKIP: khong phai so hieu cung bo (KC-.., ghi chu)
  ;; 'IN: khong co, so nam trong khoang so hieu file nay ; 'OUT: khong co, ngoai khoang (file khac?)
  (setq k (ktsh:norm ref) sn (ktsh:splitnum ref))
  (cond ((= k "") 'OK)
        ((member k shkeys) 'OK)
        ((assoc k dm) 'OK)
        ((ktsh:alldig k)
         (if (vl-some '(lambda (f) (and (setq n (ktsh:splitnum (nth 5 f))) (/= (cadr n) "")
                                       (= (atoi (cadr n)) (atoi k))))
                      frames)
           'OK 'OUT))
        ((or (null sn) (= (cadr sn) "") (not (member (car sn) prefs))) 'SKIP)
        (T
         (foreach f frames
           (if (and (setq n (ktsh:splitnum (nth 5 f))) (= (car n) (car sn)) (/= (cadr n) ""))
             (setq nums (cons (atoi (cadr n)) nums))))
         (if (and nums (>= (atoi (cadr sn)) (apply 'min nums)) (<= (atoi (cadr sn)) (apply 'max nums)))
           'IN 'OUT)))
)

(defun ktsh:chk-thamchieu (frames texts dm / cmap ed r atts main key reft ref shkeys prefs st keys titles kv role nk)
  (foreach row (kt:cfg "BLOCK")
    (if (member (strcase (kt:str (cadr row))) '("MATCAT" "CHITIET"))
      (setq cmap (cons (list (kt:ukey (car row)) (strcase (kt:str (cadr row)))
                             (strcase (kt:str (caddr row))) (strcase (kt:str (cadddr row))))
                       cmap))))
  (if (null cmap)
    (kt:add "KHUNG" "KHUNG-THAMCHIEU" "GOIY"
            "Chua cau hinh BLOCK vai tro MATCAT/CHITIET trong file chuan: bo qua kiem tra ky hieu tham chieu"
            nil nil nil)
    (progn
      (setq shkeys (vl-remove "" (mapcar '(lambda (f) (ktsh:norm (nth 5 f))) frames))
            prefs  (ktsh:uniq (vl-remove nil (mapcar '(lambda (f) (car (ktsh:splitnum (nth 5 f)))) frames))))
      (foreach en (kt:ss-all '((0 . "INSERT") (66 . 1)))
        (setq ed (entget en))
        (if (setq r (assoc (ktsh:bname en ed) cmap))
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
                                            atts)))))
                  st   (if (and shkeys ref) (ktsh:refstat ref frames shkeys prefs dm) 'OK))
            ;; so hieu ban ve tham chieu phai ton tai (file nay hoac danh muc)
            (if (member st '(IN OUT))
              (kt:add "KHUNG" "KHUNG-THAMCHIEU" (if (= st 'IN) "CANHBAO" "GOIY")
                      (strcat "Ky hieu " (if (= role "MATCAT") "mat cat" "chi tiet") " "
                              (kt:str key) " tro toi ban ve " ref " khong co trong file"
                              (if dm "/danh muc" "")
                              (if (= st 'OUT) " (ban ve o file khac?)" ""))
                      en nil nil))
            ;; gom ky hieu mat cat de kiem ban ve "MAT CAT x-x": (khoa ten co-tro-trong-file en...)
            (setq nk (ktsh:norm key))
            (if (and (= role "MATCAT") (/= nk ""))
              (if (setq kv (assoc nk keys))
                (setq keys (subst (append (list nk (cadr kv) (or (caddr kv) (= st 'OK))) (cdddr kv) (list en))
                                  kv keys))
                (setq keys (cons (list nk key (= st 'OK) en) keys)))))))
      (if keys
        (progn
          (setq titles (append (mapcar '(lambda (f) (ktsh:norm (nth 6 f))) frames)
                               (vl-remove nil (mapcar '(lambda (x) (nth 5 x)) texts))))
          (foreach kv (reverse keys)
            ;; chi xet khi ky hieu tro toi ban ve trong file nay (hoac khong ghi so ban ve)
            (if (and (caddr kv) (not (vl-some '(lambda (n) (ktsh:title-has n (car kv))) titles)))
              (kt:add "KHUNG" "KHUNG-THAMCHIEU" "CANHBAO"
                      (strcat "Ky hieu mat cat " (cadr kv) " (" (itoa (length (cdddr kv)))
                              " cho) nhung khong co ban ve/tieu de nao ten \"MAT CAT "
                              (cadr kv) "\"")
                      (cdddr kv) nil nil)))))))
)

;;; ---------- KHUNG-NGOAI ----------
;;; Vung "trong": khung ten Model + vung model ma viewport layout nhin thay.
;;; Hieu nang (100k doi tuong): 1 entget / doi tuong, layer loc bang 1 wcmatch, nho khung vua
;;; trung, o luoi cap nhat dau danh sach (doi tuong lien tiep thuong cung o). INSERT/HATCH ngoai
;;; vung theo diem 10 moi tinh hop bao (xref chen tai 0,0).
(defun ktsh:in-any (p boxes / res)
  (if (and *KT:SHL* (kt:inbox p (car *KT:SHL*) (cadr *KT:SHL*)))
    (setq res *KT:SHL*)
    (foreach b boxes
      (if (and (not res) (kt:inbox p (car b) (cadr b))) (setq res b))))
  (if res (setq *KT:SHL* res))
  res
)

(defun ktsh:noplot (/ d res)
  ;; ten layer khong in (290 = 0), da thoat ky tu wildcard
  (setq d (tblnext "LAYER" T))
  (while d
    (if (and (= (kt:dxf 290 d) 0) (kt:dxf 2 d)) (setq res (cons (kt:wcesc (kt:dxf 2 d)) res)))
    (setq d (tblnext "LAYER")))
  res
)

(defun ktsh:chk-ngoai (frames / mf boxes fens pat umn umx cw ch ed typ p key cells cell n lay tot shown)
  (setq mf (vl-remove-if-not '(lambda (f) (= (nth 1 f) "Model")) frames))
  (if mf
    (progn
      (setq fens  (mapcar 'car mf)
            boxes (append (mapcar '(lambda (f) (list (nth 2 f) (nth 3 f))) mf)
                          (vl-remove-if '(lambda (b) (or (null (car b)) (null (cadr b))))
                                        (mapcar '(lambda (v) (list (nth 3 v) (nth 4 v))) (kt:viewports))))
            ;; bo qua layer KHONG IN (plot = 0, vd KCS_Plotter / Defpoints): khong anh huong ban in
            pat   (strcase (kt:join (append (list (kt:wcesc *KT:LAYER*)) (kt:cfg-list "LAYER_BO_QUA")
                                            (ktsh:noplot))
                                    ","))
            cw    (/ (apply '+ (mapcar '(lambda (f) (- (car (nth 3 f)) (car (nth 2 f)))) mf)) (float (length mf)))
            ch    (/ (apply '+ (mapcar '(lambda (f) (- (cadr (nth 3 f)) (cadr (nth 2 f)))) mf)) (float (length mf)))
            umn   (list (apply 'min (mapcar '(lambda (f) (car (nth 2 f))) mf))
                        (apply 'min (mapcar '(lambda (f) (cadr (nth 2 f))) mf)))
            umx   (list (apply 'max (mapcar '(lambda (f) (car (nth 3 f))) mf))
                        (apply 'max (mapcar '(lambda (f) (cadr (nth 3 f))) mf)))
            *KT:SHL* nil tot 0)
      (if (<= cw 0) (setq cw 1.0))
      (if (<= ch 0) (setq ch 1.0))
      (foreach en (kt:ss-all '((410 . "Model")))
        (setq ed (entget en) typ (kt:dxf 0 ed) lay (strcase (cond ((kt:dxf 8 ed)) (""))))
        (if (and (not (member typ '("VIEWPORT" "XLINE" "RAY")))
                 (not (wcmatch lay pat))
                 (not (member en fens))
                 (setq p (if (= typ "HATCH") (kt:cen en) (kt:dxf 10 ed))))
          (progn
            (setq p (kt:2d p))
            (if (and (= typ "INSERT") (not (ktsh:in-any p boxes)))
              (setq p (kt:cen en)))
            (if (not (ktsh:in-any p boxes))
              (progn
                (setq tot (1+ tot)
                      key (list (ktsh:floor (/ (- (car p) (car umn)) cw))
                                (ktsh:floor (/ (- (cadr p) (cadr umn)) ch))))
                ;; cell: (key so-luong tong-x tong-y (ename mau...)) ; o vua dung o dau danh sach
                (cond ((and cells (equal (car (car cells)) key)) (setq cell (car cells) cells (cdr cells)))
                      ((setq cell (assoc key cells)) (setq cells (vl-remove cell cells))))
                (cond
                  (cell
                   (setq cells (cons (list key (1+ (cadr cell)) (+ (caddr cell) (car p))
                                           (+ (cadddr cell) (cadr p))
                                           (if (< (cadr cell) 30) (cons en (nth 4 cell)) (nth 4 cell)))
                                     cells)
                         cell nil))
                  ((< (length cells) 500)
                   (setq cells (cons (list key 1 (car p) (cadr p) (list en)) cells)))))))))
      ;; bao 20 o dong nhat, con lai gop 1 dong
      (setq cells (ktsh:msort cells '(lambda (a b) (> (cadr a) (cadr b)))) shown 0)
      (foreach c (ktsh:head cells 20)
        (setq n (cadr c) shown (+ shown n))
        (kt:add "KHUNG" "KHUNG-NGOAI" "GOIY"
                (strcat "Co " (itoa n) " doi tuong trong Model nam ngoai moi khung ten/viewport (vung quanh "
                        (rtos (/ (caddr c) n) 2 0) "," (rtos (/ (cadddr c) n) 2 0) ")")
                (reverse (nth 4 c))
                (list (/ (caddr c) n) (/ (cadddr c) n))
                (* 0.5 (max cw ch))))
      (if (> tot shown)
        (kt:add "KHUNG" "KHUNG-NGOAI" "GOIY"
                (strcat "Con " (itoa (- tot shown)) " doi tuong khac ngoai moi khung ten/viewport (rai rac)")
                nil nil nil))))
)

;;; ---------- chay ----------
(defun ktsh:run (/ frames texts dm)
  (if (kt:cfg-ok)
    (progn
      (kt:begin "KHUNG")
      (setq frames (kt:frames) *KT:SHL* nil)
      (if (null frames)
        (kt:add "KHUNG" "KHUNG-KHONGCO" "CANHBAO"
                "Khong tim thay khung ten nao (kiem tra ten block trong muc KHUNG cua file chuan)"
                nil nil nil)
        (progn
          ;; ten ban ve day du (gop TENBANVE1 + TENBANVE2...)
          (setq frames (mapcar '(lambda (f) (list (nth 0 f) (nth 1 f) (nth 2 f) (nth 3 f) (nth 4 f)
                                                  (nth 5 f) (ktsh:ftitle f) (nth 7 f)))
                               frames))
          (ktsh:try "o trong" 'ktsh:chk-thieu (list frames))
          (ktsh:try "trung so hieu/ten" 'ktsh:chk-trung (list frames))
          (ktsh:try "nhay so" 'ktsh:chk-nhayso (list frames))
          (ktsh:try "ty le" 'ktsh:chk-tyle (list frames))
          (setq texts (ktsh:try "doc chu" 'ktsh:texts nil))
          (setq dm (ktsh:try "danh muc" 'ktsh:chk-danhmuc (list frames texts)))
          (ktsh:try "tham chieu" 'ktsh:chk-thamchieu (list frames texts dm))
          (ktsh:try "ngoai khung" 'ktsh:chk-ngoai (list frames))
          (princ (strcat "\n[KHUNG] " (itoa (length frames)) " khung ten."))))
      (setq *KT:SHL* nil)
      (kt:finish "KHUNG")))
  (princ)
)

(defun c:KTKHUNG () (ktsh:run) (princ))

(princ "\nKT_Sheet: lenh KTKHUNG (khung ten / so hieu / danh muc / tham chieu).")
(princ)
