;;; ============================================================
;;; KT_Match.lsp  -  Module "KHOP": kich thuoc cac ban ve khop nhau
;;; ------------------------------------------------------------
;;; Lenh: KTKHOP        Ham khong hoi: (ktmat:run)
;;; Can: KT_Core.lsp (nap truoc).
;;;
;;; Ma loi:
;;;   KHOP-TRUC        (LOI)     khoang cach 2 truc khac nhau giua cac ban ve
;;;                              (hoac giua 2 hang ky hieu truc trong cung ban ve)
;;;   KHOP-THUTU       (CANHBAO) thu tu truc khac ban ve tham chieu (A,B,C / A,C,B)
;;;   KHOP-TRUNGTRUC   (LOI)     1 ten truc lap 2 lan o 2 vi tri khac nhau trong 1 hang
;;;   KHOP-DIMTRUC     (LOI)     dim noi 2 truc ghi khac khoang cach truc
;;;   KHOP-TONG        (LOI)     dim tong (truc dau -> truc cuoi) ghi khac tong khoang cach
;;;   KHOP-CAODO-VITRI (LOI)     ky hieu cao do dat sai vi tri Y tren mat dung/mat cat
;;;   KHOP-CAODO       (CANHBAO) 2 mat dung/mat cat co cap cao do lech nhau <= CAODO_LECH_NGHI
;;;                              ma ban kia khong co, va 1 gia tri co tren mat bang (cao do san)
;;;                    (GOIY)    nhu tren nhung khong gia tri nao co tren mat bang; cao do dinh
;;;                              khac nhau (chi khi SETTING KHOP_CAODO_DINH=1 - thuong hop le)
;;;   KHOP-CAODO-MB    (GOIY)    cao do tren mat bang gan (khong bang) 1 cao do mat cat
;;;                              (KHOP_CAODO_MB: 0 tat, 1 mac dinh, 2 moi gia tri khong co)
;;;   KHOP-PHONGTO     (GOIY)    ban ve co truc/cao do ve phong to k lan (chi tiet x5): bo qua so
;;;   KHOP-KHUNG       (GOIY)    khong co khung ten/viewport nao de phan vung ban ve
;;;
;;; SETTING tuy chon: KHOP_TRUC_MOI_BAN_VE (0: chi MB/MD/MC bo phieu truc), KHOP_CAODO_TEXT
;;;   (0: chi kiem vi tri block cao do), KHOP_CAODO_DINH (0), KHOP_CAODO_MB (1).
;;;
;;; GIA DINH VE CACH VE (leader can pho bien cho nhan vien - xem docs/MATCH_NOTES.md):
;;;  1. Hinh ve trong Model ve 1:1, don vi mm: khoang cach model = kich thuoc that.
;;;     Khung ten (Model) chi phong to theo ty le, KHONG thu nho hinh. (DIMLFAC = 1;
;;;     neu dim co DIMLFAC khac 1 thi gia tri hien thi = do x DIMLFAC).
;;;  2. Moi "ban ve" = 1 khung ten trong Model (muc KHUNG cua file chuan), hoac 1
;;;     viewport tren layout (vung model ma viewport nhin thay, mang so hieu cua
;;;     khung ten tren layout do). Doi tuong duoc gan ban ve theo diem chen/diem 10.
;;;  3. Loai ban ve theo TEN trong khung ten (khong dau/khong phan biet hoa):
;;;       chua "MAT BANG" -> mat bang ; "MAT DUNG"/"MAT TIEN"/"MAT BEN"/"MAT SAU"
;;;       -> mat dung ; "MAT CAT" -> mat cat.  Ten khac: chi kiem truc + dim.
;;;  4. Ky hieu truc: block vai tro TRUC trong muc BLOCK (tag chinh = ten truc).
;;;     Neu KHONG cau hinh TRUC: tu nhan block co dung 1 attribute, gia tri la
;;;     1-3 chu so hoac 1-2 chu cai (vd 1, 12, A, AB, A'), dinh nghia block co CIRCLE.
;;;     Vi tri truc = DIEM CHEN cua block (tam vong tron, nam tren duong truc).
;;;     Truc so (1,2,3) va truc chu (A,B,C) xet rieng. Cac ky hieu cung ten o 2 dau
;;;     truc la binh thuong. Hang ky hieu = cac ky hieu cung Y (xep ngang, do theo X)
;;;     hoac cung X (xep doc, do theo Y), sai lech <= 1/2 kich thuoc ky hieu.
;;;  5. Cao do: block vai tro CAODO (gia tri "+3.600", "3.600", "3600" mm...) hoac
;;;     neu khong cau hinh: attribute/TEXT/MTEXT dang "+3.600" "-0.450" "%%p0.000"
;;;     "+3,600" "COS +3.600" (bat buoc co dau +/-/+- hoac la 0.000, 3 so le).
;;;     Diem chen block cao do = dinh tam giac nam tren cao do do. Ky hieu block va
;;;     TEXT duoc xet rieng (TEXT nam tren vach mot khoang co dinh -> tu triet tieu).
;;;     Moc = ky hieu gia tri 0 (co the nhieu moc neu nhieu mat dung xep chong) hoac
;;;     ky hieu gia tri nho nhat.
;;; GIOI HAN: khong doc truc/cao do trong XREF hay block long nhau; khong xet dim
;;;   xoay xien (chi dim ngang/doc); chu tieng Viet dang TCVN3/VNI khong bo dau duoc
;;;   (ten khung nen go Unicode hoac khong dau); 2 ban ve dat canh nhau trong 1
;;;   khung: chi tach dung khi khoang ho giua 2 ban ve > 1.5 nhip truc trung binh.
;;; Thuat toan duoc mo phong & kiem thu bang tests/sim_match.py (cung ten buoc).
;;; ============================================================

;;; ---------- tien ich chung ----------
(defun ktmat:try (name f args / r)
  ;; goi (f args...) an toan; loi -> in thong bao, tra ve nil
  (setq r (vl-catch-all-apply f args))
  (if (vl-catch-all-error-p r)
    (progn
      (princ (strcat "\n[KHOP] Loi khi kiem tra " name ": " (vl-catch-all-error-message r)))
      nil)
    r)
)

(defun ktmat:msort (lst f) (kt:msort lst f))   ; merge sort on dinh (loi)

(defun ktmat:median (lst / s n)
  (setq s (ktmat:msort lst '<) n (length s))
  (cond ((= n 0) 0.0)
        ((= (rem n 2) 1) (float (nth (/ n 2) s)))
        (T (* 0.5 (+ (nth (1- (/ n 2)) s) (nth (/ n 2) s)))))
)

(defun ktmat:diffs (lst / res)
  ;; hieu so lien tiep cua 1 day so
  (while (cdr lst)
    (setq res (cons (- (cadr lst) (car lst)) res) lst (cdr lst)))
  (reverse res)
)

(defun ktmat:uniq (lst) (kt:uniq lst))

(defun ktmat:round (x)
  (if (< x 0) (- (fix (+ (- x) 0.5))) (fix (+ x 0.5)))
)

(defun ktmat:mm (v / r)
  ;; so mm -> chuoi (so nguyen neu tron, 1 so le neu khong)
  (setq r (/ (ktmat:round (* v 10.0)) 10.0))
  (if (equal r (float (fix r)) 1e-9) (itoa (fix r)) (rtos r 2 1))
)

(defun ktmat:lvstr (v / m a)
  ;; cao do (m) -> "+3.600" "-0.450" "+-0.000"
  (setq m (ktmat:round (* v 1000.0)) a (abs m))
  (strcat (cond ((< m 0) "-") ((= m 0) "+-") (T "+"))
          (itoa (/ a 1000)) "." (substr (itoa (+ 1000 (rem a 1000))) 2))
)

(defun ktmat:alldig (s)
  (and (= (type s) 'STR) (/= s "")
       (vl-every '(lambda (c) (and (>= c 48) (<= c 57))) (vl-string->list s)))
)

(defun ktmat:nat< (a b)
  ;; so sanh tu nhien ten truc: 2 < 10, so truoc chu
  (cond ((and (ktmat:alldig a) (ktmat:alldig b))
         (if (= (atoi a) (atoi b)) (< a b) (< (atoi a) (atoi b))))
        ((ktmat:alldig a) T)
        ((ktmat:alldig b) nil)
        (T (< a b)))
)

(defun ktmat:pkey (a b)
  (if (ktmat:nat< b a) (strcat b "|" a) (strcat a "|" b))
)

(defun ktmat:pname (k) (vl-string-subst "-" "|" k))

(defun ktmat:fam (name)
  (if (wcmatch (substr name 1 1) "#") "SO" "CHU")
)

;;; ---------- chuoi: dung ham loi (kt:plain kt:norm kt:txt), them TCVN3 ----------
(defun ktmat:plain (s) (kt:plain s nil))
(defun ktmat:txt (ed) (kt:txt ed))

(defun ktmat:tc (c)
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

(defun ktmat:tcvn3 (s / l)
  ;; chuoi go TCVN3 -> ASCII HOA; nil neu chuoi khong co byte dac trung TCVN3
  ;; (byte 161-254 khong phai chu Viet Latin-1/CP1258, tru ky hieu do, +-, mu 2, mu 3, x, phi)
  (setq l (vl-string->list (kt:str s)))
  (if (vl-some '(lambda (c) (and (>= c 161) (<= c 254)
                                 (not (member c '(176 177 178 179 215 216 222
                                                  192 193 194 195 200 201 202 204 205 208 210 211 212
                                                  213 217 218 221 224 225 226 227 232 233 234 236 237
                                                  240 242 243 244 245 249 250 253)))))
               l)
    (apply 'strcat (mapcar '(lambda (c) (cond ((< c 128) (strcase (chr c))) ((ktmat:tc c)) (T ""))) l)))
)

(defun ktmat:norm (s / t3)
  ;; chuan hoa so sanh (loi kt:norm: Unicode/\U+/CP1258) + font TCVN3
  (if (and (= (type s) 'STR) (setq t3 (ktmat:tcvn3 (kt:plain s nil))))
    (kt:norm t3)
    (kt:norm s))
)

;;; ---------- doc gia tri cao do ----------
(defun ktmat:ch (s i)
  (if (and (>= i 1) (<= i (strlen s))) (substr s i 1) "")
)

(defun ktmat:isdig (c) (and (= (strlen c) 1) (wcmatch c "#")))

(defun ktmat:lv-parse (s allowmm / u n i j k sg v res t2)
  ;; chuoi cao do -> met (nil neu khong phai). allowmm: block CAODO da cau hinh
  ;; (chap nhan "3.6", "3600" mm, khong can dau). Chuoi tu do: can [+|-|+-]x.xxx
  (if (= (type s) 'STR)
    (progn
      (setq u (strcase (ktmat:plain s)))
      (foreach k (list "%%P" "\\U+00B1" (chr 177))
        (while (vl-string-search k u) (setq u (vl-string-subst "+" k u))))
      (if (or allowmm (<= (strlen u) 40))
        (progn
          (setq n (strlen u) i 1)
          (while (and (null res) (<= i n))
            (if (and (ktmat:isdig (ktmat:ch u i))
                     (not (ktmat:isdig (ktmat:ch u (1- i))))
                     (not (member (ktmat:ch u (1- i)) '("." ","))))
              (progn
                (setq j i)
                (while (ktmat:isdig (ktmat:ch u j)) (setq j (1+ j)))
                (if (and (member (ktmat:ch u j) '("." ","))
                         (ktmat:isdig (ktmat:ch u (+ j 1)))
                         (ktmat:isdig (ktmat:ch u (+ j 2)))
                         (ktmat:isdig (ktmat:ch u (+ j 3)))
                         (not (ktmat:isdig (ktmat:ch u (+ j 4)))))
                  (progn
                    (setq k (1- i))
                    (if (= (ktmat:ch u k) " ") (setq k (1- k)))
                    (setq sg (ktmat:ch u k)
                          v  (+ (atof (substr u i (- j i)))
                                (/ (atof (substr u (1+ j) 3)) 1000.0)))
                    (if (or allowmm (member sg '("+" "-")) (= v 0.0))
                      (setq res (if (= sg "-") (- v) v)))))
                (setq i (1+ j)))
              (setq i (1+ i))))
          (if (and (null res) allowmm)
            (progn
              (setq t2 (vl-string-translate "," "." (vl-list->string
                         (vl-remove-if '(lambda (c) (member c '(32 43))) (vl-string->list u)))))
              (if (setq v (kt:num t2))
                (setq res (cond ((vl-string-search "." t2) v)
                                ((>= (abs v) 100.0) (/ v 1000.0))
                                (T v))))))))))
  res
)

;;; ---------- ban ve (vung) ----------
;;; unit: (idx so-hieu ten flags minpt maxpt ename)
(defun ktmat:flabel (f)
  (if (and (nth 5 f) (/= (kt:trim (nth 5 f)) ""))
    (nth 5 f)
    (strcat "khung " (kt:str (car f))))
)

(defun ktmat:stripdig (s / i)
  ;; "TENBANVE2" -> "TENBANVE" (bo so / _ / cach cuoi)
  (setq s (kt:str s) i (strlen s))
  (while (and (> i 0) (wcmatch (substr s i 1) "#,_, ")) (setq i (1- i)))
  (substr s 1 i)
)

(defun ktmat:ftitle (f / row tg base res)
  ;; ten ban ve day du: tag ten + cac tag cung goc (TENBANVE1 + TENBANVE2: "MAT BANG" / "TANG 1")
  (setq row (kt:cfg-row "KHUNG" (kt:effname (car f)))
        tg  (if row (strcase (kt:str (nth 2 row))) ""))
  (if (/= tg "")
    (progn
      (setq base (ktmat:stripdig tg))
      (foreach a (kt:attribs (car f))
        (if (and (= (ktmat:stripdig (car a)) base) (/= (cdr a) "")) (setq res (cons (cdr a) res))))))
  (if res (kt:join (reverse res) " ") (kt:str (nth 6 f)))
)

(defun ktmat:flags (title / n res)
  (setq n (ktmat:norm title))
  (if (vl-string-search "MATBANG" n) (setq res (cons "MB" res)))
  (if (or (vl-string-search "MATDUNG" n) (vl-string-search "MATTIEN" n)
          (vl-string-search "MATBEN" n) (vl-string-search "MATSAU" n))
    (setq res (cons "MD" res)))
  (if (vl-string-search "MATCAT" n) (setq res (cons "MC" res)))
  res
)

(defun ktmat:isel (u)
  ;; mat dung hoac mat cat
  (or (member "MD" (nth 3 u)) (member "MC" (nth 3 u)))
)

(defun ktmat:units (/ res i c ed lf ti)
  (setq i 0)
  (foreach f (kt:frames)
    (if (= (nth 1 f) "Model")
      (setq ti  (ktmat:ftitle f)
            res (cons (list (setq i (1+ i)) (ktmat:flabel f) ti
                            (ktmat:flags ti) (nth 2 f) (nth 3 f) (car f))
                      res))))
  (foreach vp (kt:viewports)
    (if (and (nth 3 vp) (nth 4 vp))
      (progn
        (setq c (list (* 0.5 (+ (car (nth 3 vp)) (car (nth 4 vp))))
                      (* 0.5 (+ (cadr (nth 3 vp)) (cadr (nth 4 vp))))))
        ;; bo viewport nhin vao vung da co (khung Model / viewport truoc)
        (if (not (vl-some '(lambda (u) (kt:inbox c (nth 4 u) (nth 5 u))) res))
          (progn
            (setq ed (entget (car vp))
                  lf (if (kt:dxf 10 ed) (kt:frame-at (kt:2d (kt:dxf 10 ed)) (nth 1 vp))))
            (setq ti  (if lf (ktmat:ftitle lf) (nth 1 vp))
                  res (cons (list (setq i (1+ i))
                                  (if lf (ktmat:flabel lf) (nth 1 vp))
                                  ti
                                  (ktmat:flags ti)
                                  (nth 3 vp) (nth 4 vp) (car vp))
                            res)))))))
  (reverse res)
)

(defun ktmat:unit-at (p / res)
  ;; ban ve chua diem p (Model); nho ban ve vua tim de tang toc
  (if (and p *KT:MATL* (kt:inbox p (nth 4 *KT:MATL*) (nth 5 *KT:MATL*)))
    (setq res *KT:MATL*)
    (if p
      (foreach u *KT:MATU*
        (if (and (not res) (kt:inbox p (nth 4 u) (nth 5 u))) (setq res u)))))
  (if res (setq *KT:MATL* res))
  res
)

;;; ---------- thu thap ----------
(defun ktmat:bname (en ed / nm)
  (setq nm (cond ((kt:dxf 2 ed)) ("")))
  (if (wcmatch nm "`**") (setq nm (cond ((kt:effname en)) (nm))))
  (strcase nm)
)

(defun ktmat:has-circle (bn / r e ed i res)
  ;; dinh nghia block co CIRCLE? (co nho dem)
  (if (setq r (assoc bn *KT:MATCIR*))
    (cdr r)
    (progn
      (if (setq e (tblobjname "BLOCK" bn))
        (progn
          (setq e (entnext e) i 0)
          (while (and e (< i 300) (not res))
            (setq ed (entget e))
            (cond ((= (kt:dxf 0 ed) "ENDBLK") (setq e nil))
                  ((= (kt:dxf 0 ed) "CIRCLE") (setq res T))
                  (T (setq e (entnext e) i (1+ i)))))))
      (setq *KT:MATCIR* (cons (cons bn res) *KT:MATCIR*))
      res))
)

(defun ktmat:axname (s strict / u)
  ;; ten truc hop le -> chuoi HOA khong cach; nil neu khong
  (if (= (type s) 'STR)
    (progn
      (setq u (vl-list->string (vl-remove 32 (vl-string->list (strcase (kt:trim s))))))
      (cond ((= u "") nil)
            ((not strict) (if (<= (strlen u) 8) u))
            ((wcmatch u "#,##,###,@,@@,#',##',@',@@'") u))))
)

(defun ktmat:pickatt (atts tag / a)
  (cond ((and tag (/= tag "") (setq a (assoc (strcase tag) atts))) (cdr a))
        ((car atts) (cdar atts)))
)

(defun ktmat:hv (ang / a)
  ;; phuong dim: "H" ngang, "V" doc, nil xien
  (setq a (rem (abs ang) pi))
  (cond ((or (< a 0.01) (< (- pi a) 0.01)) "H")
        ((< (abs (- a (* 0.5 pi))) 0.01) "V"))
)

(defun ktmat:dimlfac (en ed / x l r st)
  ;; DIMLFAC: ghi de (xdata ACAD DSTYLE, ma 144) > dimstyle > 1.0
  (setq x (vl-catch-all-apply 'entget (list en '("ACAD"))))
  (if (not (vl-catch-all-error-p x))
    (setq l (cdr (assoc "ACAD" (cdr (assoc -3 x))))))
  ;; XData DSTYLE: (1000 . "DSTYLE") (1002 . "{") cap (1070 . ma) (gia tri) ... (1002 . "}")
  (while (and l (/= (car (car l)) 1002)) (setq l (cdr l)))
  (setq l (cdr l))
  (while (and l (cdr l) (null r) (/= (car (car l)) 1002))
    (if (and (= (car (car l)) 1070) (= (cdr (car l)) 144) (numberp (cdr (cadr l))))
      (setq r (cdr (cadr l))))
    (setq l (cddr l)))
  (if (null r)
    (if (setq st (tblsearch "DIMSTYLE" (cond ((kt:dxf 3 ed)) ("STANDARD"))))
      (setq r (kt:dxf 144 st))))
  (if (and (numberp r) (> r 0)) (float r) 1.0)
)

(defun ktmat:dimval (ed lf / ov n)
  ;; gia tri hien thi: so ghi de (neu la so) hoac do x DIMLFAC
  (setq ov (kt:trim (ktmat:plain (cond ((kt:dxf 1 ed)) ("")))))
  (if (and (/= ov "") (not (vl-string-search "<>" ov)) (setq n (kt:num ov)))
    n
    (* (cond ((kt:dxf 42 ed)) (0.0)) lf))
)

(defun ktmat:collect (/ trc cdo oth fnames r ed p u nm atts v bubs levs dims typ p1 p2 dr lf)
  ;; tra ve (bubbles levels dims)
  ;;  bubble: (uidx ten x y kichthuoc ename)
  ;;  level : (uidx giatri_m x y loai("B"/"T") ename)
  ;;  dim   : (uidx x13 y13 x14 y14 "H"/"V" giatri ename dimlfac)
  (foreach row (kt:cfg "BLOCK")
    (cond ((= (strcase (kt:str (cadr row))) "TRUC")
           (setq trc (cons (cons (strcase (kt:str (car row))) (kt:str (caddr row))) trc)))
          ((= (strcase (kt:str (cadr row))) "CAODO")
           (setq cdo (cons (cons (strcase (kt:str (car row))) (kt:str (caddr row))) cdo)))
          ;; block vai tro khac (MATCAT, CHITIET, CUA...) khong bao gio la ky hieu truc
          (T (setq oth (cons (strcase (kt:str (car row))) oth)))))
  (setq fnames (kt:cfg-names "KHUNG"))
  ;; block: truc / cao do (bo qua chinh khung ten)
  (foreach en (kt:ss-all '((0 . "INSERT")))
    (setq ed (entget en) p (kt:dxf 10 ed))
    (if (and p (= (kt:space ed) "Model") (= (kt:dxf 66 ed) 1)
             (setq u (ktmat:unit-at (kt:2d p))))
      (progn
        (setq nm (ktmat:bname en ed) atts (kt:attribs en) p (kt:2d p) v nil)
        (cond
          ((member nm fnames) nil)
          ((member nm oth) nil)
          ((setq r (assoc nm trc))
           (if (setq v (ktmat:axname (ktmat:pickatt atts (cdr r)) nil))
             (setq bubs (cons (list (car u) v (car p) (cadr p) (kt:boxsize en) en) bubs))))
          ((setq r (assoc nm cdo))
           (setq v (ktmat:lv-parse (ktmat:pickatt atts (cdr r)) T))
           (foreach a atts (if (null v) (setq v (ktmat:lv-parse (cdr a) T))))
           (if v (setq levs (cons (list (car u) v (car p) (cadr p) "B" en) levs))))
          ((and (null trc) atts (null (cdr atts))
                (setq v (ktmat:axname (cdar atts) T))
                (ktmat:has-circle (cond ((kt:dxf 2 ed)) (""))))
           (setq bubs (cons (list (car u) v (car p) (cadr p) (kt:boxsize en) en) bubs)))
          ((null cdo)
           (setq v nil)
           (foreach a atts (if (null v) (setq v (ktmat:lv-parse (cdr a) nil))))
           (if v (setq levs (cons (list (car u) v (car p) (cadr p) "B" en) levs))))))))
  ;; TEXT / MTEXT cao do
  (foreach en (kt:ss-all '((0 . "TEXT,MTEXT")))
    (setq ed (entget en) p (kt:dxf 10 ed))
    (if (and p (= (kt:space ed) "Model")
             (/= (strcase (cond ((kt:dxf 8 ed)) (""))) (strcase *KT:LAYER*))
             (setq u (ktmat:unit-at (kt:2d p)))
             (setq v (ktmat:lv-parse (ktmat:txt ed) nil)))
      (setq levs (cons (list (car u) v (car p) (cadr p) "T" en) levs))))
  ;; DIMENSION thang (rotated / aligned)
  (foreach en (kt:ss-all '((0 . "DIMENSION")))
    (setq ed (entget en) typ (logand (cond ((kt:dxf 70 ed)) (0)) 7))
    (if (and (= (kt:space ed) "Model") (member typ '(0 1))
             (kt:dxf 13 ed) (kt:dxf 14 ed)
             (setq u (ktmat:unit-at (kt:2d (kt:dxf 13 ed)))))
      (progn
        (setq p1 (kt:2d (kt:dxf 13 ed)) p2 (kt:2d (kt:dxf 14 ed)) lf (ktmat:dimlfac en ed)
              dr (ktmat:hv (if (= typ 0) (cond ((kt:dxf 50 ed)) (0.0)) (angle p1 p2))))
        (if dr
          (setq dims (cons (list (car u) (car p1) (cadr p1) (car p2) (cadr p2) dr
                                 (ktmat:dimval ed lf) en lf)
                           dims))))))
  (list (reverse bubs) (reverse levs) (reverse dims))
)

;;; ---------- truc: gom hang -> day truc ----------
;;; bubble trong unit: (ten x y kichthuoc ename)
(defun ktmat:co (b ori)
  (if (= ori "H") (cadr b) (caddr b))
)

(defun ktmat:chain (lst ori tol / res cur prev k)
  ;; sap theo toa do ori, tach nhom khi buoc nhay > tol
  (foreach b (ktmat:msort lst '(lambda (a b) (< (ktmat:co a ori) (ktmat:co b ori))))
    (setq k (ktmat:co b ori))
    (if (and cur (> (- k prev) tol))
      (setq res (cons (reverse cur) res) cur nil))
    (setq cur (cons b cur) prev k))
  (if cur (setq res (cons (reverse cur) res)))
  (reverse res)
)

(defun ktmat:unit-seqs (u bs tol / res fb sizes rowtol across g seg segs nm c c0 sp med gap dups)
  ;; tra ve list (ho huong items), items = ((ten toado ename) ...) theo toa do tang
  (foreach fam '("SO" "CHU")
    (setq fb (vl-remove-if-not '(lambda (b) (= (ktmat:fam (car b)) fam)) bs))
    (if (cdr fb)
      (progn
        (setq sizes  (vl-remove-if-not '(lambda (x) (> x 0)) (mapcar 'cadddr fb))
              rowtol (max (if sizes (* 0.5 (ktmat:median sizes)) 0.0) tol))
        (foreach ori '("H" "V")
          (setq across (if (= ori "H") "V" "H"))
          (foreach grp (ktmat:chain fb across rowtol)
            (if (cdr (ktmat:uniq (mapcar 'car grp)))
              (progn
                (setq g    (ktmat:msort grp '(lambda (a b) (< (ktmat:co a ori) (ktmat:co b ori))))
                      seg  (list (list (car (car g)) (ktmat:co (car g) ori) (nth 4 (car g))))
                      segs nil)
                (foreach b (cdr g)
                  (setq nm (car b) c (ktmat:co b ori))
                  (if (assoc nm seg)
                    (progn
                      (setq c0 (cadr (assoc nm seg)))
                      (if (> (abs (- c c0)) tol)
                        (progn
                          (setq sp  (ktmat:diffs (mapcar 'cadr seg))
                                med (if sp (ktmat:median sp) 0.0)
                                gap (- c (cadr (last seg))))
                          ;; ten lap nam sau doan hien tai mot khoang ho > 1.5 nhip trung vi
                          ;; -> ban ve thu 2 (vd mai chi co truc 2..4) dat canh trong cung khung
                          (if (and (> med 0) (> gap (* 1.5 med)))
                            ;; ban ve thu 2 dat canh trong cung khung: tach doan
                            (setq segs (cons seg segs) seg (list (list nm c (nth 4 b))))
                            (if (not (member nm dups))
                              (progn
                                (setq dups (cons nm dups))
                                (kt:add "KHOP" "KHOP-TRUNGTRUC" "LOI"
                                        (strcat "Truc " nm " lap 2 lan trong " (cadr u)
                                                " o 2 vi tri khac nhau (lech "
                                                (ktmat:mm (abs (- c c0))) ")")
                                        (list (caddr (assoc nm seg)) (nth 4 b)) nil nil)))))))
                    (setq seg (append seg (list (list nm c (nth 4 b)))))))
                (setq segs (cons seg segs))
                (foreach s (reverse segs)
                  (if (cdr s) (setq res (cons (list fam ori s) res)))))))))))
  (ktmat:msort (reverse res) '(lambda (a b) (> (length (caddr a)) (length (caddr b)))))
)

;;; he so phong to "tron": hinh chi tiet ve phong to trong khung (vd 1/20 ve x5 trong khung 1/100)
(defun ktmat:nice (k)
  (and (numberp k) (> k 1.0)
       (vl-some '(lambda (n) (<= (abs (- k n)) (* 0.005 n))) '(2.0 2.5 4.0 5.0 10.0 20.0 25.0 50.0)))
)

(defun ktmat:same-k (ks / k0)
  ;; moi he so trong ks bang nhau (0.5%) va "tron" -> he so; nil neu khong
  (if (and ks (setq k0 (ktmat:median ks)) (ktmat:nice k0)
           (vl-every '(lambda (k) (<= (abs (- k k0)) (* 0.005 k0))) ks))
    k0)
)

(defun ktmat:chk-axes (units bubs tol / allseqs votes orders ub seqs upairs it n i j a b k v cs old rep e lst srt cls cur c0 ref labs ordr refo com mine allu allp rs oth scaled kk)
  ;; tra ve (list day-truc he-so-phong-to): day truc (uidx ho huong items), he so ((uidx . k) ...)
  ;; chi ban ve MAT BANG / MAT DUNG / MAT CAT tham gia bo phieu giua cac ban ve
  ;; (chi tiet ve cat/ngat truc -> bao nham); SETTING KHOP_TRUC_MOI_BAN_VE=1 de xet ca ban ve khac
  (setq allu (= 1 (fix (kt:cfg-num "KHOP_TRUC_MOI_BAN_VE" 0))))
  ;; tra ve tat ca day truc: (uidx ho huong items)
  (foreach u units
    (setq ub (mapcar 'cdr (vl-remove-if-not '(lambda (x) (= (car x) (car u))) bubs)))
    (if (cdr ub)
      (progn
        (setq seqs   (ktmat:unit-seqs u ub tol)
              upairs nil)
        (foreach s seqs
          (setq allseqs (cons (cons (car u) s) allseqs))
          (if (not (vl-some '(lambda (o) (and (= (car o) (car s)) (= (cadr o) (car u)))) orders))
            (setq orders (cons (list (car s) (car u) (mapcar 'car (caddr s))) orders)))
          ;; moi cap truc trong day
          (setq it (caddr s) n (length it) i 0)
          (while (< i n)
            (setq j (1+ i))
            (while (< j n)
              (setq a  (nth i it) b (nth j it)
                    k  (ktmat:pkey (car a) (car b))
                    v  (abs (- (cadr b) (cadr a)))
                    cs (= j (1+ i)))
              (if (setq old (assoc k upairs))
                ;; old: (key giatri lientiep dabao ens)
                (progn
                  (setq rep (nth 3 old))
                  (if (and (> (abs (- v (cadr old))) tol) (not rep) (or cs (caddr old)))
                    (progn
                      (kt:add "KHOP" "KHOP-TRUC" "LOI"
                              (strcat "Truc " (ktmat:pname k) " trong " (cadr u)
                                      " khong thong nhat giua 2 hang ky hieu: "
                                      (ktmat:mm (cadr old)) " / " (ktmat:mm v))
                              (list (caddr a) (caddr b)) nil nil)
                      (setq rep T)))
                  (setq upairs (subst (list k (cadr old) (or cs (caddr old)) rep (nth 4 old))
                                      old upairs)))
                (setq upairs (cons (list k v cs nil (list (caddr a) (caddr b))) upairs)))
              (setq j (1+ j)))
            (setq i (1+ i))))
        ;; phieu cua ban ve nay: (nhan giatri lientiep ens uidx)
        (setq allp (cons (cons u (mapcar '(lambda (p) (list (car p) (list (cadr u) (cadr p) (caddr p) (nth 4 p) (car u))))
                                         (reverse upairs)))
                         allp))
        (if (or allu (nth 3 u))
          (foreach p (reverse upairs)
            (setq e (list (cadr u) (cadr p) (caddr p) (nth 4 p) (car u)))
            (if (setq old (assoc (car p) votes))
              (setq votes (subst (append old (list e)) old votes))
              (setq votes (cons (list (car p) e) votes))))))))
  ;; ban ve ve phong to k lan (moi cap truc = k x gia tri nho nhat cua ban ve khac): bo khoi bo phieu
  (foreach up (reverse allp)
    (setq rs nil)
    (foreach pe (cdr up)
      (if (setq oth (vl-remove-if '(lambda (x) (= (nth 4 x) (car (car up)))) (cdr (assoc (car pe) votes))))
        (setq rs (cons (/ (cadr (cadr pe)) (max 1e-6 (apply 'min (mapcar 'cadr oth)))) rs))))
    (if (setq kk (ktmat:same-k rs))
      (progn
        (setq scaled (cons (cons (car (car up)) kk) scaled)
              votes  (mapcar '(lambda (kv) (cons (car kv) (vl-remove-if '(lambda (x) (= (nth 4 x) (car (car up)))) (cdr kv))))
                             votes))
        (kt:add "KHOP" "KHOP-PHONGTO" "GOIY"
                (strcat "Truc trong " (cadr (car up)) " ve phong to x" (rtos kk 2 1)
                        " so voi ban ve khac (chi tiet phong to?): khong so khoang cach truc")
                (nth 6 (car up)) nil nil))))
  ;; bo phieu giua cac ban ve
  (foreach kv (reverse votes)
    (setq lst (cdr kv))
    (if (cdr lst)
      (progn
        (setq srt (ktmat:msort lst '(lambda (a b) (< (cadr a) (cadr b))))
              cls nil cur nil)
        (foreach x srt
          (if (and cur (<= (- (cadr x) c0) tol))
            (setq cur (cons x cur))
            (progn
              (if cur (setq cls (cons (reverse cur) cls)))
              (setq cur (list x) c0 (cadr x)))))
        (if cur (setq cls (cons (reverse cur) cls)))
        (if (cdr cls)
          (progn
            (setq cls (ktmat:msort (reverse cls) '(lambda (a b) (> (length a) (length b)))))
            (if (> (length (car cls)) (length (cadr cls)))
              (progn
                (setq ref  (car cls)
                      labs (kt:join (ktmat:uniq (mapcar 'car ref)) ","))
                (foreach c (cdr cls)
                  (foreach x c
                    (if (caddr x)
                      (kt:add "KHOP" "KHOP-TRUC" "LOI"
                              (strcat "Truc " (ktmat:pname (car kv)) ": " (car x) " = "
                                      (ktmat:mm (cadr x)) ", " labs " = " (ktmat:mm (cadr (car ref))))
                              (nth 3 x) nil nil)))))
              (if (vl-some 'caddr lst)
                (kt:add "KHOP" "KHOP-TRUC" "LOI"
                        (strcat "Truc " (ktmat:pname (car kv)) " khong khop giua cac ban ve: "
                                (kt:join (mapcar '(lambda (x) (strcat (car x) " = " (ktmat:mm (cadr x))))
                                                 lst)
                                         ", "))
                        (apply 'append (mapcar 'cadddr lst)) nil nil))))))))
  ;; thu tu truc: so voi ban ve co nhieu truc nhat (cung ho), cho phep dao nguoc
  (setq orders (reverse orders))
  (foreach fam '("SO" "CHU")
    (setq lst (vl-remove-if-not '(lambda (o) (= (car o) fam)) orders) ref nil)
    (foreach o lst (if (or (null ref) (> (length (caddr o)) (length (caddr ref)))) (setq ref o)))
    (if (cdr lst)
      (foreach o lst
        (if (/= (cadr o) (cadr ref))
          (progn
            (setq ordr (caddr o) refo (caddr ref)
                  com  (vl-remove-if-not '(lambda (x) (member x ordr)) refo)
                  mine (vl-remove-if-not '(lambda (x) (member x com)) ordr))
            (if (and (>= (length com) 3)
                     (not (equal mine com)) (not (equal mine (reverse com))))
              (kt:add "KHOP" "KHOP-THUTU" "CANHBAO"
                      (strcat "Thu tu truc khac nhau: " (cadr (assoc (cadr ref) units)) ": "
                              (kt:join com ",") " ; " (cadr (assoc (cadr o) units)) ": "
                              (kt:join mine ","))
                      (nth 6 (assoc (cadr o) units)) nil nil)))))))
  (list (reverse allseqs) scaled)
)

;;; ---------- dim noi truc ----------
(defun ktmat:near (items c tolm / best)
  ;; truc gan toa do c nhat trong dung sai tolm
  (foreach x items
    (if (and (<= (abs (- (cadr x) c)) tolm)
             (or (null best) (< (abs (- (cadr x) c)) (abs (- (cadr best) c)))))
      (setq best x)))
  best
)

(defun ktmat:dim-ok (val ad lf k tol / ex)
  ;; gia tri dim hien thi val co hop voi khoang cach truc ad (do trong model)?
  (setq ex (* ad lf))
  (or (<= (abs (- val ex)) tol)
      (and k (<= (abs (- val (/ ad k))) tol))                         ; chi tiet phong to, ghi de so that
      (and (> val 0) (< val (* 0.01 ex)) (<= (abs (- (* 1000.0 val) ex)) tol)))  ; ghi theo m
)

(defun ktmat:chk-dims (units seqs dims tol scaled / tolm done c1 c2 a b ad its code lab lf k)
  (setq tolm (max (* 2.0 tol) 5.0))
  (foreach d dims
    (setq done nil)
    (foreach s seqs
      (if (and (not done) (= (car s) (car d)) (= (caddr s) (nth 5 d)))
        (progn
          (setq its (cadddr s)
                c1  (if (= (nth 5 d) "H") (nth 1 d) (nth 2 d))
                c2  (if (= (nth 5 d) "H") (nth 3 d) (nth 4 d))
                a   (ktmat:near its c1 tolm)
                b   (ktmat:near its c2 tolm))
          (if (and a b (/= (car a) (car b)))
            (progn
              (setq done T ad (abs (- (cadr b) (cadr a)))
                    lf (cond ((numberp (nth 8 d)) (nth 8 d)) (1.0))
                    k  (cdr (assoc (car d) scaled)))
              (if (not (ktmat:dim-ok (nth 6 d) ad lf k tol))
                (progn
                  (setq lab  (cadr (assoc (car d) units))
                        code (if (and (cddr its)
                                      (member (car a) (list (car (car its)) (car (last its))))
                                      (member (car b) (list (car (car its)) (car (last its)))))
                               "KHOP-TONG" "KHOP-DIMTRUC"))
                  (kt:add "KHOP" code "LOI"
                          (strcat (if (= code "KHOP-TONG") "Kich thuoc tong truc " "Kich thuoc truc ")
                                  (ktmat:pname (ktmat:pkey (car a) (car b))) " ghi "
                                  (ktmat:mm (nth 6 d)) " nhung khoang cach truc = " (ktmat:mm (* ad lf))
                                  " (" lab ")")
                          (nth 7 d) nil nil)))))))))
)

;;; ---------- cao do ----------
;;; Cao do tren mat dung/mat cat: ky hieu dung vi tri thi Y - 1000 x gia tri = Y moc (+-0.000).
;;; Gom ky hieu theo "moc ngam dinh" do: moi hinh ve 1 cum. Cum chua ky hieu 0 la moc;
;;; ky hieu ngoai cum moc = sai vi tri (vd copy ky hieu +7.200 xuong san +3.600 quen sua so),
;;; tru cum co >= 2 gia tri lech moc > 1m (hinh ve khac xep chong khong ghi +-0.000).
(defun ktmat:chain1 (lst tol / res cur prev k)
  ;; gom theo (car x), tach nhom khi buoc nhay > tol
  (foreach b (ktmat:msort lst '(lambda (a b) (< (car a) (car b))))
    (setq k (car b))
    (if (and cur (> (- k prev) tol))
      (setq res (cons (reverse cur) res) cur nil))
    (setq cur (cons b cur) prev k))
  (if cur (setq res (cons (reverse cur) res)))
  (reverse res)
)

(defun ktmat:chk-lvpos (units levs tollv / kinds ul syms cls dcls big bad vals off ref ks k best err meas)
  ;; TEXT cao do: khoang cach chu - vach khong co dinh -> mac dinh chi xet block
  ;; (SETTING KHOP_CAODO_TEXT=1 de xet ca TEXT/MTEXT)
  (setq kinds (if (= 1 (fix (kt:cfg-num "KHOP_CAODO_TEXT" 0))) '("B" "T") '("B")))
  (foreach u units
    (if (ktmat:isel u)
      (progn
        (setq ul (mapcar 'cdr (vl-remove-if-not '(lambda (x) (= (car x) (car u))) levs)))
        ;; ul: (giatri x y loai ename)
        (foreach kind kinds
          (setq syms (vl-remove-if-not '(lambda (x) (= (nth 3 x) kind)) ul))
          (if (cdr syms)
            (progn
              ;; phan tu cum: (moc giatri x y loai ename)
              (setq cls  (ktmat:chain1 (mapcar '(lambda (x) (cons (- (caddr x) (* 1000.0 (car x))) x)) syms)
                                       tollv)
                    dcls (vl-remove-if-not
                           '(lambda (c) (vl-some '(lambda (x) (< (abs (cadr x)) 1e-6)) c)) cls))
              (if (null dcls)
                (progn
                  (setq big nil)
                  (foreach c cls (if (or (null big) (> (length c) (length big))) (setq big c)))
                  (if (null (cdr big))
                    ;; khong cum nao >= 2: moc = ky hieu gia tri nho nhat
                    (foreach c cls (if (< (cadr (car c)) (cadr (car big))) (setq big c))))
                  (setq dcls (list big))))
              (setq bad nil)
              (foreach c cls
                (if (not (member c dcls))
                  (progn
                    (setq vals (ktmat:uniq (mapcar '(lambda (x) (ktmat:round (* 1000.0 (cadr x)))) c))
                          off  (apply 'min (mapcar '(lambda (d) (abs (- (car (car c)) (car (car d))))) dcls)))
                    (if (not (and (cdr vals) (> off 1000.0)))
                      (setq bad (append bad c))))))
              ;; hinh ve phong to k lan (chi tiet x5): moi ky hieu sai cung 1 he so -> bo qua
              (setq ref (car (car dcls)) ks nil)
              (foreach x bad
                (if (> (abs (- (cadr x) (cadr ref))) 1e-6)
                  (setq ks (cons (/ (- (nth 3 x) (nth 3 ref)) (* 1000.0 (- (cadr x) (cadr ref)))) ks))))
              (if (and (cdr bad) (= (length ks) (length bad)) (setq k (ktmat:same-k ks)))
                (kt:add "KHOP" "KHOP-PHONGTO" "GOIY"
                        (strcat "Cao do trong " (cadr u) " ve phong to x" (rtos k 2 1)
                                " (chi tiet phong to?): khong kiem vi tri cao do")
                        (nth 5 (car bad)) nil nil)
                (foreach x bad
                  (setq best nil)
                  (foreach d dcls
                    (setq err (abs (- (car x) (car (car d)))))
                    (if (or (null best) (< err (car best))) (setq best (list err (car d)))))
                  ;; (cadr best): ky hieu moc (moc giatri x y loai ename)
                  (if (> (car best) tollv)
                    (progn
                      (setq meas (+ (cadr (cadr best)) (/ (- (nth 3 x) (nth 3 (cadr best))) 1000.0)))
                      (kt:add "KHOP" "KHOP-CAODO-VITRI" "LOI"
                              (strcat "Cao do " (ktmat:lvstr (cadr x)) " dat sai vi tri, do duoc "
                                      (ktmat:lvstr meas) " theo moc " (ktmat:lvstr (cadr (cadr best)))
                                      " (lech " (ktmat:mm (car best)) "mm) - " (cadr u))
                              (nth 5 x) nil nil)))))))))))
)

(defun ktmat:lvset (u levs / vals k)
  ;; tap cao do (mm nguyen, khong trung) cua 1 ban ve: ((mm . ename) ...) tang dan
  (foreach x levs
    (if (= (car x) (car u))
      (progn
        (setq k (ktmat:round (* 1000.0 (cadr x))))
        (if (not (assoc k vals)) (setq vals (cons (cons k (nth 5 x)) vals))))))
  (ktmat:msort vals '(lambda (a b) (< (car a) (car b))))
)

(defun ktmat:has (vals k)
  (vl-some '(lambda (x) (<= (abs (- (car x) k)) 1)) vals)
)

(defun ktmat:planvals (units levs / res)
  ;; cao do ghi tren cac mat bang (khong phai mat dung/mat cat)
  (foreach u units
    (if (and (member "MB" (nth 3 u)) (not (ktmat:isel u)))
      (setq res (append res (ktmat:lvset u levs)))))
  res
)

(defun ktmat:chk-lvcross (units levs nearm / sets vals mx lo hi nmm s1 rest pl sev)
  ;; giua cac mat dung / mat cat.
  ;; - Cao do dinh khac nhau thuong HOP LE (mat cat qua tum thang, mat dung chi toi tuong chan mai)
  ;;   -> mac dinh tat; SETTING KHOP_CAODO_DINH=1 de bat (GOIY).
  ;; - Cap gia tri lech nhau <= CAODO_LECH_NGHI ma ban kia khong co: CANHBAO neu 1 trong 2 gia tri
  ;;   co tren mat bang (cao do san), nguoc lai GOIY (cao do bau cua / lanh to / day dam...).
  (foreach u units
    (if (and (ktmat:isel u) (setq vals (ktmat:lvset u levs)))
      (setq sets (cons (list u vals) sets))))
  (setq sets (reverse sets) pl (ktmat:planvals units levs))
  (if (cdr sets)
    (progn
      (setq mx (mapcar '(lambda (s) (last (cadr s))) sets)
            lo (apply 'min (mapcar 'car mx))
            hi (apply 'max (mapcar 'car mx)))
      (if (and (> (- hi lo) 1) (= 1 (fix (kt:cfg-num "KHOP_CAODO_DINH" 0))))
        (kt:add "KHOP" "KHOP-CAODO" "GOIY"
                (strcat "Cao do dinh khac nhau giua cac mat dung/mat cat: "
                        (kt:join (mapcar '(lambda (s) (strcat (cadr (car s)) " = "
                                                              (ktmat:lvstr (/ (car (last (cadr s))) 1000.0))))
                                         sets)
                                 ", "))
                (mapcar 'cdr mx) nil nil))
      (setq nmm (ktmat:round (* 1000.0 nearm)) rest sets)
      (while (cdr rest)
        (setq s1 (car rest))
        (foreach s2 (cdr rest)
          (foreach a (cadr s1)
            (if (not (ktmat:has (cadr s2) (car a)))
              (foreach b (cadr s2)
                (if (and (not (ktmat:has (cadr s1) (car b)))
                         (> (abs (- (car a) (car b))) 1)
                         (<= (abs (- (car a) (car b))) nmm))
                  (progn
                    (setq sev (if (or (ktmat:has pl (car a)) (ktmat:has pl (car b))) "CANHBAO" "GOIY"))
                    (kt:add "KHOP" "KHOP-CAODO" sev
                            (strcat "Cao do lech nhau: " (cadr (car s1)) " = "
                                    (ktmat:lvstr (/ (car a) 1000.0)) ", " (cadr (car s2)) " = "
                                    (ktmat:lvstr (/ (car b) 1000.0)) " (lech "
                                    (itoa (abs (- (car a) (car b)))) "mm)")
                            (list (cdr a) (cdr b)) nil nil)))))))
        (setq rest (cdr rest)))))
)

(defun ktmat:chk-lvplan (units levs nearm / mode nmm ref ens)
  ;; cao do ghi tren mat bang phai co tren mat cat (khong co mat cat: mat dung).
  ;; SETTING KHOP_CAODO_MB: 0 tat; 1 (mac dinh) chi bao gia tri GAN 1 cao do mat cat
  ;; (lech 1mm..CAODO_LECH_NGHI, nghi ghi nham); 2 bao moi gia tri khong co (nhieu: WC, san...).
  (setq mode (fix (kt:cfg-num "KHOP_CAODO_MB" 1)) nmm (ktmat:round (* 1000.0 nearm)))
  (if (> mode 0)
    (progn
      (foreach u units
        (if (member "MC" (nth 3 u)) (setq ref (append ref (ktmat:lvset u levs)))))
      (if (null ref)
        (foreach u units
          (if (member "MD" (nth 3 u)) (setq ref (append ref (ktmat:lvset u levs))))))))
  (if ref
    (foreach u units
      (if (and (member "MB" (nth 3 u)) (not (ktmat:isel u)))
        (foreach a (ktmat:lvset u levs)
          (if (and (not (ktmat:has ref (car a)))
                   (or (>= mode 2)
                       (vl-some '(lambda (r) (<= (abs (- (car r) (car a))) nmm)) ref)))
            (progn
              (setq ens (mapcar '(lambda (x) (nth 5 x))
                                (vl-remove-if-not
                                  '(lambda (x) (and (= (car x) (car u))
                                                    (= (ktmat:round (* 1000.0 (cadr x))) (car a))))
                                  levs)))
              (kt:add "KHOP" "KHOP-CAODO-MB" "GOIY"
                      (strcat "Cao do " (ktmat:lvstr (/ (car a) 1000.0)) " ghi tren mat bang "
                              (cadr u) " khong co tren mat cat/mat dung nao")
                      ens nil nil)))))))
)

;;; ---------- chay ----------
(defun ktmat:run (/ units data ax seqs tol tollv nearm)
  (if (kt:cfg-ok)
    (progn
      (kt:begin "KHOP")
      (setq tol   (max 0.01 (kt:cfg-num "DUNG_SAI_KICH_THUOC" 1.0))
            tollv (max 0.01 (kt:cfg-num "DUNG_SAI_CAO_DO" 5.0))
            nearm (max 0.002 (kt:cfg-num "CAODO_LECH_NGHI" 0.1))
            *KT:MATU* nil *KT:MATL* nil *KT:MATCIR* nil)
      (setq units (ktmat:try "phan vung ban ve" 'ktmat:units nil))
      (if (null units)
        (kt:add "KHOP" "KHOP-KHUNG" "GOIY"
                "Khong tim thay khung ten trong Model hoac viewport nao: bo qua kiem tra khop truc/cao do"
                nil nil nil)
        (progn
          (setq *KT:MATU* units)
          (setq data (ktmat:try "thu thap truc/cao do/dim" 'ktmat:collect nil))
          (setq ax   (ktmat:try "khoang cach truc" 'ktmat:chk-axes (list units (car data) tol))
                seqs (car ax))
          (ktmat:try "dim truc" 'ktmat:chk-dims (list units seqs (caddr data) tol (cadr ax)))
          (ktmat:try "vi tri cao do" 'ktmat:chk-lvpos (list units (cadr data) tollv))
          (ktmat:try "cao do giua cac ban ve" 'ktmat:chk-lvcross (list units (cadr data) nearm))
          (ktmat:try "cao do mat bang" 'ktmat:chk-lvplan (list units (cadr data) nearm))
          (princ (strcat "\n[KHOP] " (itoa (length units)) " ban ve, "
                         (itoa (length (car data))) " ky hieu truc, "
                         (itoa (length (cadr data))) " cao do, "
                         (itoa (length (caddr data))) " dim thang."))))
      (setq *KT:MATU* nil *KT:MATL* nil *KT:MATCIR* nil)
      (kt:finish "KHOP")))
  (princ)
)

(defun c:KTKHOP () (ktmat:run) (princ))

(princ "\nKT_Match: lenh KTKHOP (khop truc / cao do / dim giua cac ban ve).")
(princ)
