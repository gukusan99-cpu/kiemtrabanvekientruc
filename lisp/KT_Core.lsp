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
;;; ============================================================

(vl-load-com)

(setq *KT:VER*   "1.0"
      *KT:LAYER* "KT_CHECK"
      *KT:CFGNAME* "KT_ChuanCongTy.txt")
(if (not *KT:ISSUES*) (setq *KT:ISSUES* nil))
(if (not *KT:IDX*)    (setq *KT:IDX* -1))

;;; ---------- Tien ich chuoi ----------
(defun kt:trim (s) (if s (vl-string-trim " \t\r\n" s) ""))

(defun kt:split (s d / p res)
  ;; tach chuoi s theo ky tu phan cach d (chuoi 1 ky tu)
  (while (setq p (vl-string-search d s))
    (setq res (cons (kt:trim (substr s 1 p)) res)
          s   (substr s (+ p 2))))
  (reverse (cons (kt:trim s) res))
)

(defun kt:join (lst d / res first)
  (setq res "" first T)
  (foreach x lst
    (setq res (strcat res (if first "" d) (kt:str x)) first nil))
  res
)

(defun kt:str (x)
  (cond ((= (type x) 'STR) x)
        ((= (type x) 'INT) (itoa x))
        ((= (type x) 'REAL) (rtos x 2 3))
        ((null x) "")
        ((= (type x) 'ENAME) (cdr (assoc 5 (entget x))))
        (T (vl-princ-to-string x)))
)

(defun kt:num (s / v)
  ;; chuoi -> so, nil neu khong phai so
  (if (and s (= (type s) 'STR) (/= (kt:trim s) ""))
    (progn (setq v (distof (kt:trim s) 2)) v)
    (if (numberp s) (float s))
  )
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

(defun kt:csvq (s)
  ;; dua chuoi vao o CSV
  (setq s (kt:str s))
  (while (vl-string-search "\"" s)
    (setq s (vl-string-subst "''" "\"" s)))
  (strcat "\"" s "\"")
)

;;; ---------- DXF / doi tuong ----------
(defun kt:dxf (code ed) (cdr (assoc code ed)))

(defun kt:ss->list (ss / i res)
  (if ss
    (repeat (setq i (sslength ss))
      (setq res (cons (ssname ss (setq i (1- i))) res))))
  res
)

(defun kt:ss-all (flt) (kt:ss->list (ssget "_X" flt)))

(defun kt:2d (p) (list (float (car p)) (float (cadr p))))
(defun kt:3d (p) (list (float (car p)) (float (cadr p)) 0.0))

(defun kt:space (ed / s)
  ;; ten khong gian cua doi tuong: "Model" hoac ten layout
  (setq s (kt:dxf 410 ed))
  (if (or (null s) (= (strcase s) "MODEL")) "Model" s)
)

(defun kt:cur-space ()
  (if (= 1 (getvar "TILEMODE")) "Model" (getvar "CTAB"))
)

(defun kt:box (en / o mn mx r ed p)
  ;; hop bao 2D (minpt maxpt); dung ActiveX, du phong bang DXF 10
  (setq r (vl-catch-all-apply
            '(lambda ()
               (setq o (vlax-ename->vla-object en))
               (vla-GetBoundingBox o 'mn 'mx)
               (list (kt:2d (vlax-safearray->list mn))
                     (kt:2d (vlax-safearray->list mx))))
            nil))
  (if (vl-catch-all-error-p r)
    (progn
      (setq ed (entget en) p (kt:dxf 10 ed))
      (if p (list (kt:2d p) (kt:2d p))))
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
  (and (>= (car p) (car mn)) (<= (car p) (car mx))
       (>= (cadr p) (cadr mn)) (<= (cadr p) (cadr mx)))
)

(defun kt:effname (en / r)
  ;; ten that cua block (ho tro dynamic block)
  (setq r (vl-catch-all-apply
            '(lambda () (vla-get-EffectiveName (vlax-ename->vla-object en))) nil)) ; lisplint: ignore=RISKY
  (if (or (vl-catch-all-error-p r) (null r))
    (kt:dxf 2 (entget en))
    r)
)

(defun kt:attribs (en / e ed res)
  ;; danh sach (TAG . gia tri) cua block reference
  (setq e (entnext en))
  (while (and e (setq ed (entget e)) (= (kt:dxf 0 ed) "ATTRIB"))
    (setq res (cons (cons (strcase (kt:dxf 2 ed)) (kt:trim (kt:dxf 1 ed))) res)
          e   (entnext e)))
  (reverse res)
)

(defun kt:attval (en tag) (cdr (assoc (strcase tag) (kt:attribs en))))

;;; ---------- File chuan cong ty ----------
;;; Dinh dang: moi dong  MUC|truong1|truong2|...   ; dong bat dau ';' la ghi chu
(defun kt:dir (/ f)
  ;; thu muc chua bo tool, khong co dau \ cuoi
  (setq f (if (setq f (findfile "KT_Core.lsp"))
            (vl-filename-directory f)
            (getvar "DWGPREFIX")))
  (while (and (> (strlen f) 3) (member (substr f (strlen f)) '("\\" "/")))
    (setq f (substr f 1 (1- (strlen f)))))
  f
)

(defun kt:cfg-file (/ f)
  (cond ((findfile *KT:CFGNAME*))
        ((findfile (strcat (kt:dir) "\\" *KT:CFGNAME*)))
        (T (strcat (kt:dir) "\\" *KT:CFGNAME*)))
)

(defun kt:cfg-load (/ f fh ln row sec res)
  (setq *KT:CFG* nil f (kt:cfg-file))
  (if (and (findfile f) (setq fh (open f "r")))
    (progn
      (while (setq ln (read-line fh))
        (setq ln (kt:trim ln))
        (if (and (/= ln "") (/= (substr ln 1 1) ";"))
          (progn
            (setq row (kt:split ln "|")
                  sec (strcase (car row)))
            (if (assoc sec res)
              (setq res (subst (cons sec (append (cdr (assoc sec res)) (list (cdr row))))
                               (assoc sec res) res))
              (setq res (cons (cons sec (list (cdr row))) res))))))
      (close fh)
      (setq *KT:CFG* res)
      T)
    (progn
      (princ (strcat "\n[KT] Chua co file chuan " f
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
  (mapcar '(lambda (r) (strcase (car r))) (kt:cfg sec))
)

(defun kt:cfg-row (sec name)
  ;; dong dau tien cua muc sec co truong 1 = name (khong phan biet hoa thuong)
  (if (= (type name) 'STR)
    (car (vl-remove-if-not
           '(lambda (r) (and (car r) (= (strcase (car r)) (strcase name))))
           (kt:cfg sec))))
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
  (setq *KT:CFG* nil *KT:FRAMES* nil)
  (if (kt:cfg-load)
    (princ (strcat "\n[KT] Da nap " (kt:cfg-file) " - "
                   (itoa (length *KT:CFG*)) " muc.")))
  (princ)
)

;;; ---------- Ty le: khung ten va viewport ----------
;;; Ban ghi khung: (ename space minpt maxpt scale sohieu ten)
(defun kt:parse-scale (s / p a b)
  ;; "1/100" "1:100" "TL 1/50" -> 100.0 ; nil neu khong doc duoc
  (if (and s (= (type s) 'STR))
    (progn
      (setq s (strcase s))
      (cond
        ((setq p (vl-string-search "1/" s)) (setq b (kt:num (kt:numhead (substr s (+ p 3))))))
        ((setq p (vl-string-search "1:" s)) (setq b (kt:num (kt:numhead (substr s (+ p 3)))))))
      (if (and b (> b 0)) b)))
)

(defun kt:numhead (s / i c res)
  ;; lay phan so o dau chuoi
  (setq i 1 res "")
  (while (and (<= i (strlen s))
              (or (wcmatch (setq c (substr s i 1)) "#") (= c ".")))
    (setq res (strcat res c) i (1+ i)))
  res
)

(defun kt:frame-names ()
  ;; ten block khung ten tu muc KHUNG
  (mapcar 'car (kt:cfg "KHUNG"))
)

(defun kt:frames (/ names res en ed row bx sc sct tsc)
  ;; tim tat ca khung ten (moi khong gian), luu vao *KT:FRAMES*
  (if (and (null *KT:FRAMES*) (setq names (kt:frame-names)))
    (progn
      (foreach en (kt:ss-all '((0 . "INSERT")))
        (if (and (setq row (kt:cfg-row "KHUNG" (kt:effname en)))
                 (setq bx (kt:box en)))
          (progn
            (setq ed  (entget en)
                  ;; KHUNG|ten block|tag so hieu|tag ten ban ve|tag ty le|ty le goc
                  tsc (if (and (nth 3 row) (/= (nth 3 row) "")) (kt:parse-scale (kt:attval en (nth 3 row))))
                  sct (* (abs (cond ((kt:dxf 41 ed)) (1.0))) (cond ((kt:num (nth 4 row))) (1.0)))
                  sc  (cond ((= (kt:space ed) "Model") (cond (tsc) (sct)))
                            (T 1.0)))
            (setq res (cons (list en (kt:space ed) (car bx) (cadr bx) sc
                                  (if (nth 1 row) (kt:attval en (nth 1 row)))
                                  (if (nth 2 row) (kt:attval en (nth 2 row)))
                                  tsc)
                            res)))))
      (setq *KT:FRAMES* (if res (reverse res) 'NONE))))
  (if (= *KT:FRAMES* 'NONE) nil *KT:FRAMES*)
)

(defun kt:frame-at (p space / res)
  ;; khung ten chua diem p trong khong gian space
  (foreach f (kt:frames)
    (if (and (not res) (= (nth 1 f) space) (kt:inbox p (nth 2 f) (nth 3 f)))
      (setq res f)))
  res
)

(defun kt:viewports (/ res ed h vh c w sc)
  ;; (ename layout scale minpt maxpt) - vung model ma viewport nhin thay
  (if (null *KT:VPS*)
    (progn
      (foreach en (kt:ss-all '((0 . "VIEWPORT")))
        (setq ed (entget en))
        (if (and (/= (kt:dxf 69 ed) 1) (> (cond ((kt:dxf 41 ed)) (0)) 0)
                 (setq vh (kt:dxf 45 ed)) (> vh 0))
          (progn
            (setq h  (kt:dxf 41 ed) w (kt:dxf 40 ed)
                  sc (/ vh h)
                  c  (kt:2d (kt:dxf 12 ed)))
            (setq res (cons (list en (kt:space ed) sc
                                  (list (- (car c) (* 0.5 w sc)) (- (cadr c) (* 0.5 vh)))
                                  (list (+ (car c) (* 0.5 w sc)) (+ (cadr c) (* 0.5 vh))))
                            res)))))
      (setq *KT:VPS* (if res res 'NONE))))
  (if (= *KT:VPS* 'NONE) nil *KT:VPS*)
)

(defun kt:scale-at (p space / f v res)
  ;; ty le (vd 100.0) tai diem p; nil neu khong xac dinh
  (cond
    ((/= space "Model") 1.0)
    ((and (setq f (kt:frame-at p space)) (nth 4 f)) (nth 4 f))
    (T
     (foreach v (kt:viewports)
       (if (and (not res) (kt:inbox p (nth 3 v) (nth 4 v))) (setq res (nth 2 v))))
     res))
)

(defun kt:reset-cache ()
  (setq *KT:FRAMES* nil *KT:VPS* nil)
)

;;; ---------- Danh sach loi ----------
;;; Loi: (module ma muc thongdiep (ename...) diem bankinh khonggian)
;;; muc: "LOI" (do) / "CANHBAO" (vang) / "GOIY" (xanh)
(defun kt:begin (module)
  ;; goi dau moi lenh kiem tra: xoa loi cu cua module do
  (kt:reset-cache)
  (kt:clear-module module)
  (setq *KT:PEND* nil *KT:CNT* nil
        *KT:CAP* (fix (kt:cfg-num "MAX_LOI_MOI_MA" 300)))
)

(defun kt:add (module code sev msg ens pt r / sp key c)
  ;; ghi 1 loi. Moi ma loi chi luu toi da MAX_LOI_MOI_MA muc (mac dinh 300)
  (if (= (type ens) 'ENAME) (setq ens (list ens)))
  (setq key (strcat module ":" code)
        c   (1+ (cond ((cdr (assoc key *KT:CNT*))) (0)))
        *KT:CNT* (cons (cons key c) (vl-remove (assoc key *KT:CNT*) *KT:CNT*)))
  (if (<= c (cond (*KT:CAP*) (300)))
    (progn
      (setq sp (if (car ens) (kt:space (entget (car ens))) (kt:cur-space)))
      (if (and (null pt) (car ens)) (setq pt (kt:cen (car ens))))
      (if (null pt) (setq pt '(0.0 0.0)))
      (if (or (null r) (<= r 0))
        (setq r (if (car ens) (max (* 0.6 (kt:boxsize (car ens))) (kt:defrad pt sp)) (kt:defrad pt sp))))
      (setq *KT:PEND* (cons (list module code sev msg ens (kt:2d pt) r sp) *KT:PEND*))))
  c
)

(defun kt:defrad (pt sp / sc)
  ;; ban kinh mac dinh = 5mm giay x ty le
  (setq sc (if pt (kt:scale-at pt sp)))
  (* 5.0 (cond (sc) ((getvar "DIMSCALE")) (1.0)))
)

(defun kt:clear-module (module / keep)
  (foreach x *KT:ISSUES*
    (if (/= (car x) module) (setq keep (cons x keep))))
  (setq *KT:ISSUES* (reverse keep) *KT:IDX* -1)
)

(defun kt:color (sev)
  (cond ((= sev "LOI") 1) ((= sev "CANHBAO") 2) (T 4))
)

(defun kt:mklayer ()
  (if (not (tblsearch "LAYER" *KT:LAYER*))
    (entmake (list '(0 . "LAYER") '(100 . "AcDbSymbolTableRecord")
                   '(100 . "AcDbLayerTableRecord") (cons 2 *KT:LAYER*)
                   '(70 . 0) '(62 . 1) '(6 . "Continuous") '(290 . 0))))
)

(defun kt:mark (x / c r col sp)
  (setq c (kt:3d (nth 5 x)) r (nth 6 x) col (kt:color (nth 2 x)) sp (nth 7 x))
  (entmake (list '(0 . "CIRCLE") (cons 8 *KT:LAYER*) (cons 62 col)
                 (cons 410 sp) (cons 10 c) (cons 40 r)))
  (entmake (list '(0 . "TEXT") (cons 8 *KT:LAYER*) (cons 62 col) (cons 410 sp)
                 (cons 10 (list (+ (car c) (* 0.75 r)) (+ (cadr c) (* 0.75 r)) 0.0))
                 (cons 40 (* 0.3 r)) (cons 1 (strcat (nth 0 x) ":" (nth 1 x)))))
)

(defun kt:clear-marks (/ ss i)
  (if (setq ss (ssget "_X" (list (cons 8 *KT:LAYER*))))
    (repeat (setq i (sslength ss)) (entdel (ssname ss (setq i (1- i))))))
)

(defun kt:doc (/ r)
  ;; ActiveDocument hoac nil (CAD khong ho tro ActiveX)
  (setq r (vl-catch-all-apply
            '(lambda () (vla-get-ActiveDocument (vlax-get-acad-object))) nil)) ; lisplint: ignore=RISKY
  (if (vl-catch-all-error-p r) nil r)
)

(defun kt:finish (module / doc lst ss codes n)
  ;; ve lai danh dau, in tom tat cua module, chon doi tuong loi
  (setq doc (kt:doc))
  (if doc (vl-catch-all-apply 'vla-StartUndoMark (list doc)))
  (kt:clear-marks)
  (setq *KT:ISSUES* (append *KT:ISSUES* (reverse *KT:PEND*)) *KT:PEND* nil)
  (if *KT:ISSUES* (kt:mklayer))
  (foreach x *KT:ISSUES* (kt:mark x))
  (if doc (vl-catch-all-apply 'vla-EndUndoMark (list doc)))
  (setq lst (vl-remove-if-not '(lambda (x) (= (car x) module)) *KT:ISSUES*))
  (princ (strcat "\n=== [" module "] phat hien " (itoa (length lst)) " muc ==="))
  (foreach x lst (if (not (member (cadr x) codes)) (setq codes (cons (cadr x) codes))))
  (foreach k (reverse codes)
    (setq n (cond ((cdr (assoc (strcat module ":" k) *KT:CNT*))) (0)))
    (princ (strcat "\n  " k ": " (itoa n)
                   "   (vd: " (nth 3 (car (vl-remove-if-not '(lambda (x) (= (cadr x) k)) lst))) ")")))
  (setq ss (ssadd))
  (foreach x lst
    (foreach e (nth 4 x)
      (if (and e (entget e) (= (nth 7 x) (kt:cur-space))) (ssadd e ss))))
  (if (> (sslength ss) 0) (vl-catch-all-apply 'sssetfirst (list nil ss)))
  (setq *KT:IDX* -1)
  (if lst (princ "\nGo KTN de xem tung loi, KTBC de xuat bao cao, KTX de xoa danh dau."))
  (length lst)
)

;;; ---------- Xem tung loi ----------
(defun kt:zoom (pt h / r)
  (setq r (vl-catch-all-apply 'vla-ZoomCenter
            (list (vlax-get-acad-object) (vlax-3d-point (kt:3d pt)) h)))
  (if (vl-catch-all-error-p r)
    (command "_.ZOOM" "_C" (kt:3d pt) h))
)

(defun kt:goto (step / n x s)
  (if *KT:ISSUES*
    (progn
      (setq n (length *KT:ISSUES*)
            *KT:IDX* (rem (+ n *KT:IDX* step) n)
            x (nth *KT:IDX* *KT:ISSUES*))
      (if (/= (nth 7 x) (kt:cur-space))
        (if (= (nth 7 x) "Model")
          (setvar "TILEMODE" 1)
          (setvar "CTAB" (nth 7 x))))
      (kt:zoom (nth 5 x) (* 6.0 (nth 6 x)))
      (setq s (ssadd))
      (foreach e (nth 4 x) (if (and e (entget e)) (ssadd e s)))
      (if (> (sslength s) 0) (vl-catch-all-apply 'sssetfirst (list nil s)))
      (princ (strcat "\nLoi " (itoa (1+ *KT:IDX*)) "/" (itoa n) " [" (nth 2 x) "] "
                     (nth 0 x) "-" (nth 1 x) ": " (nth 3 x))))
    (princ "\nChua co ket qua. Chay KTALL hoac 1 lenh kiem tra truoc."))
  (princ)
)

(defun c:KTN () (kt:goto 1))
(defun c:KTP () (if (< *KT:IDX* 0) (setq *KT:IDX* 0)) (kt:goto -1))

(defun c:KTX ()
  (kt:clear-marks)
  (setq *KT:ISSUES* nil *KT:IDX* -1)
  (princ "\n[KT] Da xoa danh dau va danh sach loi.")
  (princ)
)

;;; ---------- Bao cao ----------
(defun kt:report-file ()
  (strcat (getvar "DWGPREFIX")
          (vl-filename-base (getvar "DWGNAME")) "_KiemTra.csv")
)

(defun c:KTBC (/ f fh i x)
  (if (not *KT:ISSUES*)
    (princ "\nChua co loi nao de xuat.")
    (progn
      (setq f (kt:report-file))
      (if (setq fh (open f "w"))
        (progn
          (write-line "STT,Module,Ma loi,Muc do,Noi dung,Khong gian,X,Y,Handle" fh)
          (setq i 0)
          (foreach x *KT:ISSUES*
            (setq i (1+ i))
            (write-line
              (kt:join (list (itoa i) (kt:csvq (nth 0 x)) (kt:csvq (nth 1 x)) (kt:csvq (nth 2 x))
                             (kt:csvq (nth 3 x)) (kt:csvq (nth 7 x))
                             (rtos (car (nth 5 x)) 2 2) (rtos (cadr (nth 5 x)) 2 2)
                             (kt:csvq (if (and (car (nth 4 x)) (entget (car (nth 4 x))))
                                        (kt:str (car (nth 4 x))) "")))
                       ",")
              fh))
          (close fh)
          (princ (strcat "\n[KT] Da xuat " (itoa i) " dong: " f)))
        (princ (strcat "\n[KT] Khong ghi duoc file " f " (file dang mo?)")))))
  (princ)
)

;;; ---------- Do kha nang cua phan mem CAD (chay tren VinaCAD de kiem chung) ----------
(defun c:KTPROBE (/ fns ok bad r)
  (setq fns '(vl-catch-all-apply vl-sort vl-string-search vl-string-subst vl-remove
              vl-remove-if-not vl-filename-directory vl-filename-base vl-princ-to-string
              vlax-get-acad-object vlax-ename->vla-object vla-GetBoundingBox
              vla-get-EffectiveName vla-ZoomCenter vla-StartUndoMark vlax-3d-point
              vlax-safearray->list sssetfirst textbox layoutlist dictsearch namedobjdict))
  (foreach f fns
    (if (member (type (eval f)) '(SUBR USUBR EXRXSUBR))
      (setq ok (cons f ok))
      (setq bad (cons f bad))))
  (princ (strcat "\n[KTPROBE] " (getvar "ACADVER") " - co " (itoa (length ok))
                 "/" (itoa (length fns)) " ham."))
  (if bad
    (progn (princ "\n  THIEU: ") (foreach f (reverse bad) (princ (strcat (vl-princ-to-string f) " ")))))
  (setq r (vl-catch-all-apply 'kt:box (list (entlast))))
  (princ (strcat "\n  Hop bao doi tuong cuoi: "
                 (if (vl-catch-all-error-p r) "LOI" (vl-princ-to-string r))))
  (princ "\nGui ket qua nay cho nguoi phat trien neu co dong THIEU.")
  (princ)
)

(princ (strcat "\nKT_Core " *KT:VER* " da nap."))
(princ)
