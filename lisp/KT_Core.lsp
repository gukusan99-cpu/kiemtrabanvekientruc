;;; ============================================================
;;; KT_Core.lsp  -  Thu vien loi dung chung cho bo KIEM TRA BAN VE (KT)
;;; ------------------------------------------------------------
;;; Chay tren AutoCAD va VinaCAD. Moi module (KT_*.lsp) dung chung:
;;;   - doc file chuan cong ty  : KT_ChuanCongTy.txt
;;;   - danh sach loi          : *KT:ISSUES*
;;;   - danh dau / xem / bao cao: layer KT_CHECK, lenh KTN KTP KTX KTBC
;;;
;;; Lenh chung:
;;;   KTN   : Zoom toi loi tiep theo        KTP : loi truoc do
;;;   KTX   : Xoa danh dau + danh sach loi
;;;   KTBC  : Xuat bao cao CSV (mo bang Excel)
;;;   KTCFG : Nap lai file chuan cong ty
;;;   KTPROBE: do kha nang cua phan mem CAD
;;; ============================================================

(vl-load-com)

(setq *KT:VER*   "1.1"
      *KT:LAYER* "KT_CHECK"
      *KT:CFGNAME* "KT_ChuanCongTy.txt")
(if (not *KT:ISSUES*) (setq *KT:ISSUES* nil))
(if (not *KT:IDX*)    (setq *KT:IDX* -1))

;;; ---------- Tien ich chuoi ----------
(defun kt:trim (s)
  (cond ((null s) "")
        ((= (type s) 'STR) (vl-string-trim " \t\r\n" s))
        (T (vl-string-trim " \t\r\n" (kt:str s))))
)

(defun kt:split (s d / p res n)
  ;; tach chuoi s theo chuoi phan cach d. s nil -> nil
  (if (= (type s) 'STR)
    (progn
      (setq n (max 1 (strlen d)))
      (while (setq p (vl-string-search d s))
        (setq res (cons (kt:trim (substr s 1 p)) res)
              s   (substr s (+ p n 1))))
      (reverse (cons (kt:trim s) res))))
)

(defun kt:join (lst d / res first)
  (setq res "" first T)
  (foreach x lst
    (setq res (strcat res (if first "" d) (kt:str x)) first nil))
  res
)

(defun kt:str (x)
  ;; moi kieu -> chuoi (khong bao gio tra ve nil)
  (cond ((= (type x) 'STR) x)
        ((= (type x) 'INT) (itoa x))
        ((= (type x) 'REAL) (rtos x 2 3))
        ((null x) "")
        ((= (type x) 'ENAME) (cond ((cdr (assoc 5 (entget x)))) ("")))
        (T (vl-princ-to-string x)))
)

(defun kt:num (s / v)
  ;; chuoi -> so thuc, nil neu khong phai so
  (cond
    ((and (= (type s) 'STR) (/= (kt:trim s) "")) (distof (kt:trim s) 2))
    ((numberp s) (float s)))
)

(defun kt:wcmatch-any (s pats / ok)
  ;; s khop 1 trong cac mau wildcard (danh sach chuoi)
  (if (= (type s) 'STR)
    (progn
      (setq s (strcase s))
      (foreach p pats
        (if (and (not ok) (= (type p) 'STR) (/= p "") (wcmatch s (strcase p))) (setq ok T)))))
  ok
)

(defun kt:wcesc (s / i c r)
  ;; thoat ky tu dac biet cua wcmatch (dung cho bo loc ssget theo ten)
  (setq r "" i 1 s (kt:str s))
  (while (<= i (strlen s))
    (setq c (substr s i 1))
    (setq r (strcat r (if (vl-string-search c "#@.*?~[]-,`") "`" "") c)
          i (1+ i)))
  r
)

(defun kt:csvq (s / i c r)
  ;; dua chuoi vao o CSV: bao nhay kep, nhay kep ben trong nhan doi (chuan RFC4180)
  (setq s (kt:str s) r "" i 1)
  (while (<= i (strlen s))
    (setq c (substr s i 1))
    (cond ((= c "\"") (setq c "\"\""))
          ((member c '("\r" "\n")) (setq c " ")))
    (setq r (strcat r c) i (1+ i)))
  (strcat "\"" r "\"")
)

(defun kt:uniq (lst / res)
  ;; bo phan tu trung (giu thu tu)
  (foreach x lst (if (not (member x res)) (setq res (cons x res))))
  (reverse res)
)

(defun kt:merge (a b f / res)
  (while (and a b)
    (if (apply f (list (car b) (car a)))
      (setq res (cons (car b) res) b (cdr b))
      (setq res (cons (car a) res) a (cdr a))))
  (append (reverse res) a b)
)

(defun kt:msort (lst f / a n i)
  ;; merge sort ON DINH, khong xoa phan tu trung (vl-sort co the xoa).
  ;; f: ham so sanh 2 doi (a b) -> T neu a dung truoc b
  (if (or (null lst) (null (cdr lst)))
    lst
    (progn
      (setq n (/ (length lst) 2) i 0)
      (while (< i n)
        (setq a (cons (car lst) a) lst (cdr lst) i (1+ i)))
      (kt:merge (kt:msort (reverse a) f) (kt:msort lst f) f)))
)

;;; ---------- Tieng Viet: bo dau ----------
;;; AutoLISP ANSI (AutoCAD < 2021 / LISPSYS=0, nhieu ban CAD clone): ky tu ngoai codepage
;;; tra ve dang "\U+1EA1"; ky tu trong codepage (vd CP1258 tieng Viet) la 1 byte 128-255.
;;; AutoLISP Unicode (LISPSYS=1): ma ky tu la ma Unicode.
(defun kt:cp1258-p (/ r)
  ;; T neu chuoi LISP la byte theo codepage Windows-1258 (tieng Viet)
  (if (null *KT:CP*)
    (setq *KT:CP*
           (if (and (= (strcase (kt:str (getvar "SYSCODEPAGE"))) "ANSI_1258")
                    (not (equal 1 (getvar "LISPSYS"))))
             "1258" "X")))
  (= *KT:CP* "1258")
)

(defun kt:hex (s / i v d)
  ;; "1EA1" -> 7841 ; nil neu khong phai hex
  (setq s (strcase (kt:str s)) i 1 v (if (= s "") nil 0))
  (while (and v (<= i (strlen s)))
    (if (setq d (vl-string-search (substr s i 1) "0123456789ABCDEF"))
      (setq v (+ (* v 16) d))
      (setq v nil))
    (setq i (1+ i)))
  v
)

(defun kt:uchar (c)
  ;; ma ky tu chu Viet co dau -> chu khong dau (HOA); "" neu khong biet / dau rieng
  (cond ((< c 128) (strcase (chr c)))
        ((and (>= c 7840) (<= c 7863)) "A")
        ((and (>= c 7864) (<= c 7879)) "E")
        ((and (>= c 7880) (<= c 7883)) "I")
        ((and (>= c 7884) (<= c 7907)) "O")
        ((and (>= c 7908) (<= c 7921)) "U")
        ((and (>= c 7922) (<= c 7929)) "Y")
        ((and (< c 256) (kt:cp1258-p))
         ;; Windows-1258: DD/FD = U+01AF/01B0 (U*), CC D2 DE EC F2 = dau thanh to hop
         (cond ((member c '(192 193 194 195 196 197 224 225 226 227 228 229)) "A")
               ((member c '(200 201 202 203 232 233 234 235)) "E")
               ((member c '(205 206 207 237 238 239)) "I")
               ((member c '(211 212 213 214 216 243 244 245 246 248)) "O")
               ((member c '(217 218 219 220 221 249 250 251 252 253)) "U")
               ((member c '(208 240)) "D")
               ((member c '(159 255)) "Y")
               (T "")))
        ((member c '(192 193 194 195 196 197 224 225 226 227 228 229 258 259)) "A")
        ((member c '(200 201 202 203 232 233 234 235)) "E")
        ((member c '(204 205 206 207 236 237 238 239 296 297)) "I")
        ((member c '(210 211 212 213 214 216 242 243 244 245 246 248 416 417)) "O")
        ((member c '(217 218 219 220 249 250 251 252 360 361 431 432)) "U")
        ((member c '(221 253 255)) "Y")
        ((member c '(208 240 272 273)) "D")
        (T ""))
)

(defun kt:ulower-p (c)
  ;; ma ky tu co dau la chu thuong?
  (cond ((and (>= c 7840) (<= c 7929)) (= 1 (rem c 2)))
        ((and (>= c 224) (<= c 255)) T)
        ((member c '(259 273 297 361 417 432)) T))
)

(defun kt:deacc (s keep / p h res c u)
  ;; bo dau: keep=T giu hoa/thuong (ky tu la -> '?'), keep=nil -> VIET HOA (ky tu la bi bo)
  (setq s (kt:str s) res "")
  (while (setq p (vl-string-search "\\U+" (strcase s)))
    (setq h   (kt:hex (substr s (+ p 4) 4))
          u   (if h (kt:uchar h) "")
          res (strcat res (substr s 1 p)
                      (cond ((not keep) u)
                            ((= u "") "?")
                            ((kt:ulower-p h) (strcase u T))
                            (T u)))
          s   (substr s (+ p 8))))
  (setq res (strcat res s))
  (setq res
    (apply 'strcat
           (mapcar '(lambda (c)
                      (cond ((< c 128) (chr c))
                            ((not keep) (kt:uchar c))
                            ((= (setq u (kt:uchar c)) "") (if (kt:cp1258-p) "" "?"))
                            ((kt:ulower-p c) (strcase u T))
                            (T u)))
                   (vl-string->list res))))
  (if keep res (strcase res))
)

(defun kt:unaccent (s)
  ;; "M\U+1EB6T C\U+1EAET" -> "MAT CAT" (VIET HOA, bo ky tu khong doc duoc)
  (kt:deacc s nil)
)

(defun kt:ascii (s)
  ;; chuoi bat ky -> ASCII giu hoa/thuong: "Nh\U+00E0" -> "Nha" (dung cho bao cao/ten file)
  (kt:deacc s T)
)

(defun kt:plain (s nl / i n c d j res)
  ;; bo ma dinh dang MTEXT; \P -> xuong dong (nl=T) hoac dau cach; giu \U+XXXX
  (setq s (kt:str s) i 1 n (strlen s) res "")
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

(defun kt:norm (s)
  ;; chuan hoa de so sanh: bo dinh dang MTEXT + dau, HOA, chi giu A-Z 0-9
  (if (= (type s) 'STR)
    (vl-list->string
      (vl-remove-if-not
        '(lambda (c) (or (and (>= c 48) (<= c 57)) (and (>= c 65) (<= c 90))))
        (vl-string->list (kt:unaccent (kt:plain s nil)))))
    "")
)

(defun kt:txt (ed / s)
  ;; noi dung TEXT/MTEXT/ATTRIB (MTEXT dai: cac nhom 3 + nhom 1)
  (setq s "")
  (foreach x ed (if (= (car x) 3) (setq s (strcat s (cdr x)))))
  (strcat s (cond ((kt:dxf 1 ed)) ("")))
)

;;; ---------- DXF / doi tuong ----------
(defun kt:dxf (code ed) (cdr (assoc code ed)))

(defun kt:ss->list (ss / i res)
  (if ss
    (repeat (setq i (sslength ss))
      (setq res (cons (ssname ss (setq i (1- i))) res))))
  res
)

(defun kt:ss-all (flt)
  (kt:ss->list (if flt (ssget "_X" flt) (ssget "_X")))
)

(defun kt:2d (p) (list (float (car p)) (float (cadr p))))
(defun kt:3d (p) (list (float (car p)) (float (cadr p)) 0.0))

(defun kt:space (ed / s o oed)
  ;; ten khong gian cua doi tuong: "Model" hoac ten layout.
  ;; ATTRIB / VERTEX khong co 410 -> lay theo doi tuong chu (INSERT / POLYLINE).
  (setq s (kt:dxf 410 ed))
  (if (and (null s)
           (member (kt:dxf 0 ed) '("ATTRIB" "VERTEX" "SEQEND"))
           (setq o (kt:dxf 330 ed))
           (= (type o) 'ENAME)
           (setq oed (entget o))
           (member (kt:dxf 0 oed) '("INSERT" "POLYLINE")))
    (setq s (kt:dxf 410 oed)))
  (if (or (null s) (= (strcase s) "MODEL")) "Model" s)
)

(defun kt:cur-space ()
  (if (= 1 (getvar "TILEMODE")) "Model" (getvar "CTAB"))
)

;;; --- hop bao ---
(defun kt:pts-box (pts / mn mx)
  ;; hop bao cua danh sach diem
  (foreach p pts
    (if (and (listp p) (numberp (car p)) (numberp (cadr p)))
      (if mn
        (setq mn (list (min (car mn) (car p)) (min (cadr mn) (cadr p)))
              mx (list (max (car mx) (car p)) (max (cadr mx) (cadr p))))
        (setq mn (kt:2d p) mx (kt:2d p)))))
  (if mn (list (kt:2d mn) (kt:2d mx)))
)

(defun kt:box-corners (b)
  (list (car b) (cadr b) (list (car (car b)) (cadr (cadr b))) (list (car (cadr b)) (cadr (car b))))
)

(defun kt:xform (p ins sx sy ang / x y)
  ;; diem trong toa do block -> toa do ngoai (scale, xoay, tinh tien)
  (setq x (* sx (car p)) y (* sy (cadr p)))
  (list (+ (car ins) (- (* x (cos ang)) (* y (sin ang))))
        (+ (cadr ins) (+ (* x (sin ang)) (* y (cos ang)))))
)

(defun kt:ent-pts (ed depth / typ pts r p b tb a ins)
  ;; cac diem dac trung cua 1 doi tuong (du phong khi khong co ActiveX)
  (setq typ (kt:dxf 0 ed))
  (cond
    ((member typ '("CIRCLE" "ARC"))
     (setq p (kt:dxf 10 ed) r (cond ((kt:dxf 40 ed)) (0.0)))
     (if p (list (list (- (car p) r) (- (cadr p) r)) (list (+ (car p) r) (+ (cadr p) r)))))
    ((and (member typ '("TEXT" "ATTRIB" "ATTDEF")) (setq p (kt:dxf 10 ed)))
     (setq tb (vl-catch-all-apply 'textbox (list ed))
           a  (cond ((kt:dxf 50 ed)) (0.0)))
     (if (or (vl-catch-all-error-p tb) (null tb))
       (list p)
       (mapcar '(lambda (q) (kt:xform q p 1.0 1.0 a)) (kt:box-corners (list (car tb) (cadr tb))))))
    ((and (= typ "MTEXT") (setq p (kt:dxf 10 ed)))
     (setq a (max (cond ((kt:dxf 42 ed)) ((kt:dxf 41 ed)) (0.0)) 0.0)
           r (max (cond ((kt:dxf 43 ed)) ((kt:dxf 40 ed)) (0.0)) 0.0))
     (list (list (- (car p) a) (- (cadr p) r)) (list (+ (car p) a) (+ (cadr p) r))))
    ((and (= typ "INSERT") (< depth 4) (setq ins (kt:dxf 10 ed))
          (setq b (kt:blk-ext (kt:dxf 2 ed) depth)))
     (mapcar '(lambda (q)
                (kt:xform q ins (cond ((kt:dxf 41 ed)) (1.0)) (cond ((kt:dxf 42 ed)) (1.0))
                          (cond ((kt:dxf 50 ed)) (0.0))))
             (kt:box-corners b)))
    (T
     (foreach g ed
       (if (and (member (car g) '(10 11 12 13 14 15)) (listp (cdr g)) (numberp (cadr g)))
         (setq pts (cons (cdr g) pts))))
     pts))
)

(defun kt:blk-ext (nm depth / it e ed bp pts res)
  ;; hop bao dinh nghia block (toa do tuong doi diem goc), luu cache *KT:BEXT*
  (if (and nm (setq it (assoc (strcase nm) *KT:BEXT*)))
    (cdr it)
    (progn
      (if (and nm (setq e (tblobjname "BLOCK" nm)))
        (progn
          (setq bp (cond ((kt:dxf 10 (entget e))) ('(0.0 0.0 0.0))) e (entnext e))
          (while e
            (setq ed (entget e))
            (if (or (null ed) (= (kt:dxf 0 ed) "ENDBLK"))
              (setq e nil)
              (progn
                (if (/= (kt:dxf 0 ed) "ATTDEF")
                  (setq pts (append (kt:ent-pts ed (1+ depth)) pts)))
                (setq e (entnext e)))))
          (if (setq res (kt:pts-box pts))
            (setq res (list (list (- (car (car res)) (car bp)) (- (cadr (car res)) (cadr bp)))
                            (list (- (car (cadr res)) (car bp)) (- (cadr (cadr res)) (cadr bp))))))))
      (if nm (setq *KT:BEXT* (cons (cons (strcase nm) res) *KT:BEXT*)))
      res))
)

(defun kt:box-dxf (en / ed)
  (if (setq ed (entget en)) (kt:pts-box (kt:ent-pts ed 0)))
)

(defun kt:box (en / o mn mx r)
  ;; hop bao 2D (minpt maxpt); dung ActiveX, du phong bang DXF
  (setq r (vl-catch-all-apply
            '(lambda ()
               (setq o (vlax-ename->vla-object en))
               (vla-GetBoundingBox o 'mn 'mx)
               (list (kt:2d (vlax-safearray->list mn))
                     (kt:2d (vlax-safearray->list mx))))
            nil))
  (if (or (vl-catch-all-error-p r) (null r))
    (progn
      (setq r (vl-catch-all-apply 'kt:box-dxf (list en)))
      (if (vl-catch-all-error-p r) nil r))
    r)
)

(defun kt:cen (en / b)
  (if (setq b (kt:box en))
    (list (* 0.5 (+ (car (car b)) (car (cadr b))))
          (* 0.5 (+ (cadr (car b)) (cadr (cadr b)))))
    '(0.0 0.0))
)

(defun kt:boxsize (en / b)
  (if (setq b (kt:box en))
    (max (- (car (cadr b)) (car (car b))) (- (cadr (cadr b)) (cadr (car b))))
    0.0)
)

(defun kt:inbox (p mn mx)
  (and p mn mx
       (>= (car p) (car mn)) (<= (car p) (car mx))
       (>= (cadr p) (cadr mn)) (<= (cadr p) (cadr mx)))
)

;;; --- block ---
(defun kt:effname-dxf (en / nm b br x h)
  ;; ten that cua dynamic block khong can ActiveX: *U.. -> BLOCK_RECORD -> XData AcDbBlockRepBTag
  (setq nm (kt:dxf 2 (entget en)))
  (if (and nm (wcmatch nm "`*U*")
           (setq b (tblobjname "BLOCK" nm))
           (setq br (kt:dxf 330 (entget b)))
           (= (type br) 'ENAME)
           (setq x (entget br '("AcDbBlockRepBTag")))
           (setq x (cdr (assoc "AcDbBlockRepBTag" (cdr (assoc -3 x)))))
           (setq h (cdr (assoc 1005 x)))
           (setq h (handent h))
           (setq x (kt:dxf 2 (entget h))))
    x
    nm)
)

(defun kt:effname (en / r)
  ;; ten that cua block (ho tro dynamic block)
  (setq r (vl-catch-all-apply
            '(lambda () (vla-get-EffectiveName (vlax-ename->vla-object en))) nil)) ; lisplint: ignore=RISKY
  (if (or (vl-catch-all-error-p r) (/= (type r) 'STR) (= r ""))
    (progn
      (setq r (vl-catch-all-apply 'kt:effname-dxf (list en)))
      (if (vl-catch-all-error-p r) (kt:dxf 2 (entget en)) r))
    r)
)

(defun kt:attribs (en / ed e res)
  ;; danh sach (TAG . gia tri) cua block reference (dung tai SEQEND)
  (if (and en (setq ed (entget en)) (= (kt:dxf 0 ed) "INSERT") (= (kt:dxf 66 ed) 1))
    (progn
      (setq e (entnext en))
      (while (and e (setq ed (entget e)) (= (kt:dxf 0 ed) "ATTRIB"))
        (setq res (cons (cons (strcase (kt:str (kt:dxf 2 ed))) (kt:trim (kt:txt ed))) res)
              e   (entnext e)))))
  (reverse res)
)

(defun kt:attval (en tag)
  (if (and (= (type tag) 'STR) (/= tag ""))
    (cdr (assoc (strcase tag) (kt:attribs en))))
)

;;; ---------- File chuan cong ty ----------
;;; Dinh dang: moi dong  MUC|truong1|truong2|...   ; dong bat dau ';' la ghi chu
(defun kt:path (d f)
  ;; noi thu muc + ten file (khong nhan doi dau \)
  (if (member (substr d (max 1 (strlen d))) '("\\" "/"))
    (strcat d f)
    (strcat d "\\" f))
)

(defun kt:dir (/ f)
  ;; thu muc chua bo tool, khong co dau \ cuoi (tru goc o dia "C:\")
  ;; uu tien *KT:HOME* (KT_Load dat), roi Support path, cuoi cung thu muc ban ve
  (setq f (cond ((and (= (type *KT:HOME*) 'STR) (/= *KT:HOME* "")
                      (findfile (kt:path *KT:HOME* "KT_Core.lsp")))
                 *KT:HOME*)
                ((setq f (findfile "KT_Core.lsp")) (vl-filename-directory f))
                (T (getvar "DWGPREFIX"))))
  (while (and (> (strlen f) 3) (member (substr f (strlen f)) '("\\" "/")))
    (setq f (substr f 1 (1- (strlen f)))))
  f
)

(defun kt:cfg-file ()
  ;; file chuan: cung thu muc ban ve / Support path, roi thu muc bo tool
  (cond ((findfile *KT:CFGNAME*))
        ((findfile (kt:path (kt:dir) *KT:CFGNAME*)))
        (T (kt:path (kt:dir) *KT:CFGNAME*)))
)

(defun kt:cfg-load (/ f fh ln row sec res first it)
  (setq *KT:CFG* nil f (kt:cfg-file) first T)
  (if (and (findfile f) (setq fh (open f "r")))
    (progn
      (while (setq ln (read-line fh))
        ;; bo BOM UTF-8 (Notepad luu UTF-8) o dong dau
        (if (and first (>= (strlen ln) 3) (= (substr ln 1 3) "\357\273\277"))
          (setq ln (substr ln 4)))
        (setq first nil ln (kt:trim ln))
        (if (and (/= ln "") (/= (substr ln 1 1) ";"))
          (progn
            (setq row (kt:split ln "|")
                  sec (strcase (car row)))
            ;; bo dong khong co truong nao (vd "LAYER" hoac "LAYER|")
            (if (and (cdr row) (/= (kt:join (cdr row) "") ""))
              (if (setq it (assoc sec res))
                (setq res (subst (cons sec (cons (cdr row) (cdr it))) it res))
                (setq res (cons (list sec (cdr row)) res)))))))
      (close fh)
      ;; dao lai thu tu dong trong moi muc (da cons nguoc)
      (setq *KT:CFG* (mapcar '(lambda (s) (cons (car s) (reverse (cdr s)))) (reverse res)))
      T)
    (progn
      (princ (strcat "\n[KT] Chua co file chuan " (kt:str f)
                     ". Mo ban ve mau cong ty va chay lenh KTMAU de tao."))
      nil))
)

(defun kt:cfg-ok ()
  ;; nap neu chua nap; tra ve T neu co du lieu
  (if (not *KT:CFG*) (kt:cfg-load))
  (if *KT:CFG* T nil)
)

(defun kt:cfg (sec) (cdr (assoc (strcase sec) *KT:CFG*)))

(defun kt:cfg-names (sec)
  (mapcar '(lambda (r) (strcase (kt:str (car r)))) (kt:cfg sec))
)

(defun kt:cfg-row (sec name / up)
  ;; dong dau tien cua muc sec co truong 1 = name (khong phan biet hoa thuong)
  (if (= (type name) 'STR)
    (progn
      (setq up (strcase name))
      (car (vl-member-if
             '(lambda (r) (and (= (type (car r)) 'STR) (= (strcase (car r)) up)))
             (kt:cfg sec)))))
)

(defun kt:cfg-val (key def / r)
  ;; SETTING|KEY|gia tri  (gia tri duoc phep chua '|', vd *|* -> noi lai)
  (if (setq r (kt:cfg-row "SETTING" key))
    (progn
      (setq r (reverse (cdr r)))
      (while (and r (= (car r) "")) (setq r (cdr r)))   ; bo truong rong cuoi dong
      (setq r (reverse r))))
  (if (and r (/= (setq r (kt:join r "|")) ""))
    r
    def)
)

(defun kt:cfg-num (key def / v)
  (if (setq v (kt:num (kt:cfg-val key nil))) v def)
)

(defun kt:cfg-list (key / v)
  ;; SETTING|KEY|a,b,c -> ("a" "b" "c")
  (if (setq v (kt:cfg-val key nil))
    (vl-remove "" (kt:split v ",")))
)

(defun c:KTCFG ()
  (setq *KT:CFG* nil)
  (kt:reset-cache)
  (if (kt:cfg-load)
    (princ (strcat "\n[KT] Da nap " (kt:cfg-file) " - "
                   (itoa (length *KT:CFG*)) " muc.")))
  (princ)
)

;;; ---------- Ty le: khung ten va viewport ----------
(defun kt:numhead (s / i c res)
  ;; lay phan so o dau chuoi
  (setq i 1 res "")
  (while (and (<= i (strlen s))
              (or (wcmatch (setq c (substr s i 1)) "#") (= c ".")))
    (setq res (strcat res c) i (1+ i)))
  res
)

(defun kt:parse-scale (s / p b i st)
  ;; "1/100" "1:100" "TL 1/50" "TY LE: 1 / 100" -> 100.0 ; nil neu khong doc duoc
  ;; "11/100" khong doc thanh 1/100 (chu so dung truoc "1")
  (if (= (type s) 'STR)
    (progn
      (setq s (vl-string-translate ":" "/" (vl-string-subst "" " " (strcase s))))
      (while (vl-string-search " " s) (setq s (vl-string-subst "" " " s)))
      (setq st 0)
      (while (and (null b) (setq p (vl-string-search "1/" s st)))
        (if (or (= p 0) (not (wcmatch (substr s p 1) "#,`.")))
          (setq b (kt:num (kt:numhead (substr s (+ p 3))))))
        (setq st (1+ p)))
      (if (and b (> b 0)) b)))
)

(defun kt:frame-names ()
  ;; ten block khung ten tu muc KHUNG
  (vl-remove "" (mapcar '(lambda (r) (kt:str (car r))) (kt:cfg "KHUNG")))
)

(defun kt:frames (/ names flt raw res en ed row bx sct tsc agree disagree sc)
  ;; tim tat ca khung ten (moi khong gian), luu vao *KT:FRAMES*
  ;; ban ghi: (ename space minpt maxpt scale sohieu ten scale-ghi-trong-khung)
  ;; scale (Model): ty le THUC = |scale X| x he so goc; neu da so khung trong ban ve
  ;; co ty le ghi khac ty le thuc (he so goc trong file chuan sai) thi dung ty le ghi.
  (if (and (null *KT:FRAMES*) (setq names (kt:frame-names)))
    (progn
      ;; loc san theo ten (+ block dong *U) de khong phai duyet moi INSERT
      (setq flt (strcat (kt:join (mapcar 'kt:wcesc names) ",") ",`*U*"))
      (foreach en (kt:ss-all (list '(0 . "INSERT") (cons 2 flt)))
        (if (and (setq row (kt:cfg-row "KHUNG" (kt:effname en)))
                 (setq bx (kt:box en)))
          (progn
            (setq ed  (entget en)
                  ;; KHUNG|ten block|tag so hieu|tag ten ban ve|tag ty le|ty le goc
                  tsc (if (and (nth 3 row) (/= (nth 3 row) "")) (kt:parse-scale (kt:attval en (nth 3 row))))
                  sct (* (abs (cond ((kt:dxf 41 ed)) (1.0))) (cond ((kt:num (nth 4 row))) (1.0))))
            (if (and tsc (= (kt:space ed) "Model"))
              (if (equal tsc sct (* 0.01 tsc))
                (setq agree (1+ (cond (agree) (0))))
                (setq disagree (1+ (cond (disagree) (0))))))
            (setq raw (cons (list en (kt:space ed) (car bx) (cadr bx) sct
                                  (if (nth 1 row) (kt:attval en (nth 1 row)))
                                  (if (nth 2 row) (kt:attval en (nth 2 row)))
                                  tsc)
                            raw)))))
      (foreach f raw
        (setq sc (cond ((/= (nth 1 f) "Model") 1.0)
                       ((null (nth 7 f)) (nth 4 f))
                       ((or (null (nth 4 f)) (<= (nth 4 f) 0)) (nth 7 f))
                       ;; da so khung lech -> he so goc sai -> tin ty le ghi
                       ((> (cond (disagree) (0)) (cond (agree) (0))) (nth 7 f))
                       (T (nth 4 f))))
        (setq res (cons (list (nth 0 f) (nth 1 f) (nth 2 f) (nth 3 f) sc
                              (nth 5 f) (nth 6 f) (nth 7 f))
                        res)))
      (setq *KT:FRAMES* (if res res 'NONE))))
  (if (= *KT:FRAMES* 'NONE) nil *KT:FRAMES*)
)

(defun kt:frame-at (p space / res)
  ;; khung ten chua diem p trong khong gian space
  (if p
    (foreach f (kt:frames)
      (if (and (not res) (= (nth 1 f) space) (kt:inbox p (nth 2 f) (nth 3 f)))
        (setq res f))))
  res
)

(defun kt:viewports (/ res ed h vh c w sc tg tw dir hw hh pts)
  ;; (ename layout scale minpt maxpt) - vung model (WCS, hop bao) ma viewport nhin thay
  ;; scale = 45 (chieu cao view, don vi model) / 41 (chieu cao viewport, don vi giay)
  ;; tam view (12) theo DCS: goc DCS = diem target (17), xoay theo twist (51).
  (if (null *KT:VPS*)
    (progn
      (foreach en (kt:ss-all '((0 . "VIEWPORT")))
        (setq ed (entget en))
        (if (and (/= (kt:dxf 69 ed) 1)
                 (setq h (kt:dxf 41 ed)) (> h 0)
                 (setq w (kt:dxf 40 ed)) (> w 0)
                 (setq vh (kt:dxf 45 ed)) (> vh 0)
                 (kt:dxf 12 ed))
          (progn
            (setq sc  (/ (float vh) h)
                  c   (kt:2d (kt:dxf 12 ed))
                  tg  (cond ((kt:dxf 17 ed)) ('(0.0 0.0 0.0)))
                  tw  (cond ((kt:dxf 51 ed)) (0.0))
                  dir (cond ((kt:dxf 16 ed)) ('(0.0 0.0 1.0)))
                  hw  (* 0.5 w sc)
                  hh  (* 0.5 vh))
            ;; chi xoay/tinh tien khi nhin bang (plan); view 3D -> gan dung
            (if (not (and (equal (car dir) 0.0 1e-9) (equal (cadr dir) 0.0 1e-9)))
              (setq tw 0.0))
            (setq pts (mapcar '(lambda (q) (kt:xform q (kt:2d tg) 1.0 1.0 (- tw)))
                              (list (list (- (car c) hw) (- (cadr c) hh))
                                    (list (+ (car c) hw) (- (cadr c) hh))
                                    (list (+ (car c) hw) (+ (cadr c) hh))
                                    (list (- (car c) hw) (+ (cadr c) hh))))
                  pts (kt:pts-box pts))
            (setq res (cons (list en (kt:space ed) sc (car pts) (cadr pts)) res)))))
      (setq *KT:VPS* (if res (reverse res) 'NONE))))
  (if (= *KT:VPS* 'NONE) nil *KT:VPS*)
)

(defun kt:scales-at (p space / f scs)
  ;; TAT CA ty le ung vien tai diem p (khung ten + moi viewport nhin thay p), khong trung
  (cond
    ((/= space "Model") (list 1.0))
    ((null p) nil)
    (T
     (if (and (setq f (kt:frame-at p space)) (numberp (nth 4 f)) (> (nth 4 f) 0))
       (setq scs (list (nth 4 f))))
     (foreach v (kt:viewports)
       (if (and (kt:inbox p (nth 3 v) (nth 4 v))
                (not (vl-member-if '(lambda (s) (equal s (nth 2 v) (* 0.001 s))) scs)))
         (setq scs (append scs (list (nth 2 v))))))
     scs))
)

(defun kt:scale-at (p space / f scs)
  ;; ty le (vd 100.0) tai diem p; layout -> 1.0; nil neu khong xac dinh.
  ;; Model: khung ten chua diem; khong co khung -> viewport nhin thay diem.
  ;; Nhieu viewport khac ty le cung nhin thay diem (vd mat bang 1/100 + chi tiet 1/25)
  ;; -> tra ty le LON NHAT (thuong la ban ve chinh); module can xet them kt:scales-at.
  (cond
    ((/= space "Model") 1.0)
    ((null p) nil)
    ((and (setq f (kt:frame-at p space)) (nth 4 f)) (nth 4 f))
    ((setq scs (kt:scales-at p space)) (apply 'max scs)))
)

(defun kt:reset-cache ()
  (setq *KT:FRAMES* nil *KT:VPS* nil *KT:BEXT* nil)
)

;;; ---------- Danh sach loi ----------
;;; Loi: (module ma muc thongdiep (ename...) diem bankinh khonggian)
;;; muc: "LOI" (do) / "CANHBAO" (vang) / "GOIY" (xanh)
;;; diem = nil: loi cap ban ve (khong co doi tuong, khong ve danh dau).
(defun kt:begin (module)
  ;; goi dau moi lenh kiem tra: xoa loi cu cua module do
  (kt:reset-cache)
  (setq *KT:REDRAW* (kt:clear-module module))
  (setq *KT:PEND* nil *KT:CNT* nil
        *KT:CAP* (max 1 (fix (kt:cfg-num "MAX_LOI_MOI_MA" 300))))
)

(defun kt:add (module code sev msg ens pt r / sp key c e0 d)
  ;; ghi 1 loi. Moi ma loi chi luu toi da MAX_LOI_MOI_MA muc (mac dinh 300)
  ;; ens: ename / list ename / nil. pt nil + ens nil -> loi cap ban ve (khong danh dau)
  (if (= (type ens) 'ENAME) (setq ens (list ens)))
  (setq ens (vl-remove-if-not '(lambda (x) (= (type x) 'ENAME)) ens)
        module (kt:str module) code (kt:str code)
        key (strcat module ":" code)
        c   (1+ (cond ((cdr (assoc key *KT:CNT*))) (0)))
        *KT:CNT* (cons (cons key c) (vl-remove (assoc key *KT:CNT*) *KT:CNT*)))
  (if (<= c (cond (*KT:CAP*) (300)))
    (progn
      (setq e0 (if (and (car ens) (entget (car ens))) (car ens)))
      (setq sp (if e0 (kt:space (entget e0)) (kt:cur-space)))
      (if (and (null pt) e0) (setq pt (kt:cen e0)))
      (if pt
        (progn
          (setq pt (kt:2d pt) d (kt:defrad pt sp))
          (if (or (not (numberp r)) (<= r 0))
            (setq r (if e0 (min (max (* 0.6 (kt:boxsize e0)) d) (* 20.0 d)) d)))))
      (setq *KT:PEND* (cons (list module code (kt:str sev) (kt:str msg) ens pt r sp) *KT:PEND*))))
  c
)

(defun kt:defrad (pt sp / sc ds)
  ;; ban kinh mac dinh = 5mm giay x ty le (luon > 0)
  (setq sc (if pt (kt:scale-at pt sp))
        ds (getvar "DIMSCALE"))
  (* 5.0 (cond ((and (numberp sc) (> sc 0)) sc)
               ((and (numberp ds) (> ds 0)) ds)
               (1.0)))
)

(defun kt:clear-module (module / keep rm)
  ;; xoa loi cua module; T neu co loi bi xoa
  (foreach x *KT:ISSUES*
    (if (/= (car x) module) (setq keep (cons x keep)) (setq rm T)))
  (setq *KT:ISSUES* (reverse keep) *KT:IDX* -1)
  rm
)

(defun kt:color (sev)
  (cond ((= sev "LOI") 1) ((= sev "CANHBAO") 2) (T 4))
)

(defun kt:mklayer (/ e ed fl)
  ;; tao layer KT_CHECK (khong in); neu co roi: bat, tan bang, mo khoa
  (if (setq e (tblobjname "LAYER" *KT:LAYER*))
    (progn
      (setq ed (entget e) fl (cond ((kt:dxf 70 ed)) (0)))
      (if (or (/= 0 (logand fl 5)) (< (cond ((kt:dxf 62 ed)) (1)) 0))
        (progn
          (setq ed (subst (cons 70 (logand fl (~ 5))) (assoc 70 ed) ed))
          (if (assoc 62 ed) (setq ed (subst (cons 62 (abs (kt:dxf 62 ed))) (assoc 62 ed) ed)))
          (vl-catch-all-apply 'entmod (list ed)))))
    (entmake (list '(0 . "LAYER") '(100 . "AcDbSymbolTableRecord")
                   '(100 . "AcDbLayerTableRecord") (cons 2 *KT:LAYER*)
                   '(70 . 0) '(62 . 1) '(6 . "Continuous") '(290 . 0))))
)

(defun kt:mark (x / c r col sp sl)
  ;; ve vong tron + ma loi; loi cap ban ve (diem nil) -> khong ve
  (if (and (nth 5 x) (numberp (nth 6 x)) (> (nth 6 x) 0))
    (progn
      (setq c (kt:3d (nth 5 x)) r (nth 6 x) col (kt:color (nth 2 x)) sp (nth 7 x)
            sl (if (= sp "Model") nil (list '(67 . 1))))
      (entmake (append (list '(0 . "CIRCLE") (cons 8 *KT:LAYER*) (cons 62 col))
                       sl (list (cons 410 sp) (cons 10 c) (cons 40 r))))
      (entmake (append (list '(0 . "TEXT") (cons 8 *KT:LAYER*) (cons 62 col))
                       sl
                       (list (cons 410 sp)
                             (cons 10 (list (+ (car c) (* 0.75 r)) (+ (cadr c) (* 0.75 r)) 0.0))
                             (cons 40 (* 0.3 r)) (cons 1 (strcat (nth 0 x) ":" (nth 1 x))))))))
)

(defun kt:clear-marks (/ ss i)
  (if (setq ss (ssget "_X" (list (cons 8 (kt:wcesc *KT:LAYER*)))))
    (repeat (setq i (sslength ss)) (entdel (ssname ss (setq i (1- i))))))
)

(defun kt:nmarks (/ ss)
  (if (setq ss (ssget "_X" (list (cons 8 (kt:wcesc *KT:LAYER*))))) (sslength ss) 0)
)

(defun kt:doc (/ r)
  ;; ActiveDocument hoac nil (CAD khong ho tro ActiveX)
  (setq r (vl-catch-all-apply
            '(lambda () (vla-get-ActiveDocument (vlax-get-acad-object))) nil)) ; lisplint: ignore=RISKY
  (if (vl-catch-all-error-p r) nil r)
)

(defun kt:finish (module / doc new lst ss codes n nold cur)
  ;; ve danh dau, in tom tat cua module, chon doi tuong loi
  (setq doc (kt:doc) new (reverse *KT:PEND*) *KT:PEND* nil)
  (if doc (vl-catch-all-apply 'vla-StartUndoMark (list doc)))
  ;; chi ve lai toan bo khi loi cu cua module nay bi thay hoac danh dau bi xoa/undo;
  ;; nguoc lai chi ve them loi moi (KTALL tren ban ve lon nhanh hon nhieu)
  (setq nold (* 2 (length (vl-remove-if-not '(lambda (x) (nth 5 x)) *KT:ISSUES*))))
  (setq *KT:ISSUES* (append *KT:ISSUES* new))
  (if *KT:ISSUES* (kt:mklayer))
  (if (or *KT:REDRAW* (/= nold (kt:nmarks)))
    (progn (kt:clear-marks) (foreach x *KT:ISSUES* (kt:mark x)))
    (foreach x new (kt:mark x)))
  (setq *KT:REDRAW* nil)
  (if doc (vl-catch-all-apply 'vla-EndUndoMark (list doc)))
  (setq lst new)
  (princ (strcat "\n=== [" module "] phat hien " (itoa (length lst)) " muc ==="))
  (foreach x lst (if (not (member (cadr x) codes)) (setq codes (cons (cadr x) codes))))
  (foreach k (reverse codes)
    (setq n (cond ((cdr (assoc (strcat module ":" k) *KT:CNT*))) (0)))
    (princ (strcat "\n  " k ": " (itoa n)
                   (if (> n (cond (*KT:CAP*) (300)))
                     (strcat " (chi ghi " (itoa (cond (*KT:CAP*) (300))) " - MAX_LOI_MOI_MA)") "")
                   "   (vd: " (kt:str (nth 3 (car (vl-remove-if-not '(lambda (x) (= (cadr x) k)) lst))))
                   ")")))
  (setq ss (ssadd) cur (kt:cur-space))
  (foreach x lst
    (if (= (nth 7 x) cur)
      (foreach e (nth 4 x)
        (if (and e (entget e)) (ssadd e ss)))))
  (if (> (sslength ss) 0) (vl-catch-all-apply 'sssetfirst (list nil ss)))
  (setq *KT:IDX* -1)
  (if lst (princ "\nGo KTN de xem tung loi, KTBC de xuat bao cao, KTX de xoa danh dau."))
  (length lst)
)

;;; ---------- Xem tung loi ----------
(defun kt:zoom (pt h / r ce)
  (setq r (vl-catch-all-apply
            '(lambda ()
               (vla-ZoomCenter (vlax-get-acad-object) (vlax-3d-point (kt:3d pt)) h))
            nil))
  (if (vl-catch-all-error-p r)
    (progn
      (setq ce (getvar "CMDECHO"))
      (setvar "CMDECHO" 0)
      (vl-catch-all-apply 'command (list "_.ZOOM" "_C" (kt:3d pt) h))
      (setvar "CMDECHO" ce)))
)

(defun kt:goto (step / n x s r ce)
  (if *KT:ISSUES*
    (progn
      (setq n (length *KT:ISSUES*)
            *KT:IDX* (rem (+ n *KT:IDX* step) n)
            x (nth *KT:IDX* *KT:ISSUES*))
      ;; chuyen dung khong gian (Model / layout) cua loi
      (if (and (nth 5 x) (/= (nth 7 x) (kt:cur-space)))
        (progn
          (setq r (vl-catch-all-apply 'setvar
                    (if (= (nth 7 x) "Model") (list "TILEMODE" 1) (list "CTAB" (nth 7 x)))))
          (if (vl-catch-all-error-p r)
            (princ (strcat "\n[KT] Khong chuyen duoc sang " (nth 7 x) " (layout da bi xoa/doi ten?)")))))
      ;; dang o trong viewport (model space cua layout) -> ra paper space truoc khi zoom
      (if (and (nth 5 x) (/= (nth 7 x) "Model") (= 0 (getvar "TILEMODE")) (/= 1 (getvar "CVPORT")))
        (progn
          (setq ce (getvar "CMDECHO"))
          (setvar "CMDECHO" 0)
          (vl-catch-all-apply 'command (list "_.PSPACE"))
          (setvar "CMDECHO" ce)))
      (if (and (nth 5 x) (= (nth 7 x) (kt:cur-space)))
        (kt:zoom (nth 5 x) (* 6.0 (nth 6 x))))
      (setq s (ssadd))
      (foreach e (nth 4 x) (if (and e (entget e) (= (kt:space (entget e)) (kt:cur-space))) (ssadd e s)))
      (if (> (sslength s) 0) (vl-catch-all-apply 'sssetfirst (list nil s)))
      (princ (strcat "\nLoi " (itoa (1+ *KT:IDX*)) "/" (itoa n) " [" (nth 2 x) "] "
                     (nth 0 x) "-" (nth 1 x) ": " (nth 3 x)
                     (if (nth 5 x) "" "  (loi chung cua ban ve)"))))
    (princ "\nChua co ket qua. Chay KTALL hoac 1 lenh kiem tra truoc."))
  (princ)
)

(defun c:KTN () (kt:goto 1))
(defun c:KTP () (if (< *KT:IDX* 0) (setq *KT:IDX* 0)) (kt:goto -1))

(defun c:KTX ()
  (kt:clear-marks)
  (setq *KT:ISSUES* nil *KT:IDX* -1 *KT:PEND* nil)
  (princ "\n[KT] Da xoa danh dau va danh sach loi.")
  (princ)
)

;;; ---------- Bao cao ----------
(defun kt:fname-safe (s / i c r)
  ;; ten file ASCII an toan: bo dau, ky tu cam -> '_'
  (setq s (kt:ascii s) r "" i 1)
  (while (<= i (strlen s))
    (setq c (substr s i 1))
    (if (or (< (ascii c) 32) (> (ascii c) 126) (vl-string-search c "\\/:*?\"<>|"))
      (setq c "_"))
    (setq r (strcat r c) i (1+ i)))
  (if (= r "") "BanVe" r)
)

(defun kt:report-file ()
  (kt:path (getvar "DWGPREFIX")
           (strcat (kt:fname-safe (vl-filename-base (getvar "DWGNAME"))) "_KiemTra.csv"))
)

(defun kt:report-write (f / fh i)
  ;; ghi CSV; T neu thanh cong
  (if (setq fh (open f "w"))
    (progn
      ;; "sep=," : Excel (may dat vung Viet Nam dung dau ';') van tach dung cot
      (write-line "sep=," fh)
      (write-line "STT,Module,Ma loi,Muc do,Noi dung,Khong gian,X,Y,Handle" fh)
      (setq i 0)
      (foreach x *KT:ISSUES*
        (setq i (1+ i))
        (write-line
          (kt:join (list (itoa i) (kt:csvq (nth 0 x)) (kt:csvq (nth 1 x)) (kt:csvq (nth 2 x))
                         (kt:csvq (kt:ascii (nth 3 x))) (kt:csvq (kt:ascii (nth 7 x)))
                         ;; toa do lam tron so nguyen: tranh Excel VN doc "12.5" thanh ngay thang
                         (if (nth 5 x) (rtos (car (nth 5 x)) 2 0) "")
                         (if (nth 5 x) (rtos (cadr (nth 5 x)) 2 0) "")
                         (kt:csvq (if (and (car (nth 4 x)) (entget (car (nth 4 x))))
                                    (kt:str (car (nth 4 x))) "")))
                   ",")
          fh))
      (close fh)
      T))
)

(defun c:KTBC (/ f ok d)
  (if (not *KT:ISSUES*)
    (princ "\nChua co loi nao de xuat.")
    (progn
      (setq f (kt:report-file))
      (if (not (setq ok (kt:report-write f)))
        (progn
          ;; file dang mo trong Excel / thu muc chi doc / duong dan co dau -> ten khac, thu muc khac
          (setq d (rtos (getvar "CDATE") 2 6)
                d (vl-string-subst "-" "." d))
          (foreach dir (list (getvar "DWGPREFIX") (kt:dir) (getenv "TEMP"))
            (if (and (not ok) (= (type dir) 'STR) (/= dir ""))
              (progn
                (setq f (kt:path dir (strcat (kt:fname-safe (vl-filename-base (getvar "DWGNAME")))
                                             "_KiemTra_" d ".csv")))
                (setq ok (kt:report-write f)))))))
      (if ok
        (princ (strcat "\n[KT] Da xuat " (itoa (length *KT:ISSUES*)) " dong: " f))
        (princ (strcat "\n[KT] Khong ghi duoc file bao cao " f " (file dang mo / khong co quyen ghi?)")))))
  (princ)
)

;;; ---------- Do kha nang cua phan mem CAD (chay tren VinaCAD de kiem chung) ----------
(defun c:KTPROBE (/ fns ok bad r)
  (setq fns '(vl-catch-all-apply vl-sort vl-string-search vl-string-subst vl-remove
              vl-remove-if-not vl-member-if vl-string-translate vl-string->list vl-list->string
              vl-filename-directory vl-filename-base vl-princ-to-string vl-directory-files
              vlax-get-acad-object vlax-ename->vla-object vla-GetBoundingBox
              vla-get-EffectiveName vla-ZoomCenter vla-StartUndoMark vlax-3d-point
              vlax-safearray->list sssetfirst textbox layoutlist dictsearch namedobjdict handent))
  (foreach f fns
    (if (member (type (eval f)) '(SUBR USUBR EXRXSUBR))
      (setq ok (cons f ok))
      (setq bad (cons f bad))))
  (princ (strcat "\n[KTPROBE] " (kt:str (getvar "ACADVER")) " - co " (itoa (length ok))
                 "/" (itoa (length fns)) " ham."))
  (princ (strcat "\n  SYSCODEPAGE=" (kt:str (getvar "SYSCODEPAGE"))
                 "  LISPSYS=" (kt:str (getvar "LISPSYS"))))
  (if bad
    (progn (princ "\n  THIEU: ") (foreach f (reverse bad) (princ (strcat (vl-princ-to-string f) " ")))))
  (setq r (vl-catch-all-apply 'kt:box (list (entlast))))
  (princ (strcat "\n  Hop bao doi tuong cuoi: "
                 (if (vl-catch-all-error-p r) "LOI" (vl-princ-to-string r))))
  (setq r (vl-catch-all-apply 'kt:box-dxf (list (entlast))))
  (princ (strcat "\n  Hop bao (DXF du phong): "
                 (if (vl-catch-all-error-p r) "LOI" (vl-princ-to-string r))))
  (princ "\nGui ket qua nay cho nguoi phat trien neu co dong THIEU.")
  (princ)
)

(princ (strcat "\nKT_Core " *KT:VER* " da nap."))
(princ)
