;;; ============================================================
;;; KT_Clean.lsp  -  Module "SACH": ve sinh file ban ve
;;; ------------------------------------------------------------
;;; Lenh  : KTSACH           Ham khong hoi (cho KTALL): (ktcl:run)
;;; Can   : KT_Core.lsp nap truoc.
;;;
;;; Ma loi:
;;;   XREF-MAT     LOI     xref khong tim thay file
;;;   ANH-MAT      LOI     anh (IMAGEDEF) khong tim thay file
;;;   Z-KHAC0      CANHBAO doi tuong trong Model co cao do Z khac 0
;;;   LINE-0       GOIY    LINE dai 0
;;;   PLINE-0      GOIY    LWPOLYLINE 0/1 dinh hoac chieu dai 0
;;;   LINE-TRUNG   CANHBAO LINE trung hoan toan (copy chong), cung layer
;;;   BLOCK-TRUNG  CANHBAO INSERT trung ten + vi tri + scale + goc (copy chong)
;;;   BLOCK-THUA   GOIY    dinh nghia block khong duoc dung (chua purge) - 1 dong tong ket
;;;   LAYER-RONG   GOIY    layer khong co doi tuong nao (ngoai chuan) - 1 dong tong ket
;;;   HATCH-KLK    GOIY    HATCH khong lien ket bien (associative = 0) - 1 dong/khong gian
;;; ============================================================

(vl-load-com)

;;; ---------- Tien ich ----------
(defun ktcl:try (fn / r)
  (setq r (vl-catch-all-apply fn nil))
  (if (vl-catch-all-error-p r)
    (progn
      (princ (strcat "\n[SACH] Loi noi bo khi chay " (vl-princ-to-string fn)
                     ": " (vl-catch-all-error-message r)))
      nil)
    r)
)

(defun ktcl:wcesc (s / i c r)
  ;; thoat ky tu dac biet wcmatch de dung trong bo loc ssget
  (setq r "" i 1)
  (while (<= i (strlen s))
    (setq c (substr s i 1))
    (setq r (strcat r (if (vl-string-search c "#@.*?~[]-,`") "`" "") c)
          i (1+ i)))
  r
)

(defun ktcl:notmark ()
  (list '(-4 . "<NOT") (cons 8 (ktcl:wcesc *KT:LAYER*)) '(-4 . "NOT>"))
)

(defun ktcl:fmt (x / s)
  (setq s (rtos x 2 3))
  (if (vl-string-search "." s)
    (progn
      (setq s (vl-string-right-trim "0" s))
      (setq s (vl-string-right-trim "." s))))
  s
)

(defun ktcl:fname (f / p)
  ;; bo phan duong dan
  (setq f (kt:trim f))
  (while (setq p (vl-string-search "\\" f)) (setq f (substr f (+ p 2))))
  (while (setq p (vl-string-search "/" f)) (setq f (substr f (+ p 2))))
  f
)

(defun ktcl:filefound (p)
  ;; tim file theo: duong dan goc, tuong doi thu muc DWG, ten file trong support path
  (setq p (kt:trim p))
  (and (/= p "")
       (or (findfile p)
           (findfile (strcat (getvar "DWGPREFIX") p))
           (findfile (strcat (getvar "DWGPREFIX") (ktcl:fname p)))
           (findfile (ktcl:fname p))))
)

(defun ktcl:rk (x g / s)
  ;; lam tron x theo luoi g -> chuoi so nguyen (khoa so sanh)
  (setq s (rtos (/ x g) 2 0))
  (if (= s "-0") "0" s)
)

(defun ktcl:pk (p g)
  ;; khoa diem 3D
  (strcat (ktcl:rk (car p) g) "," (ktcl:rk (cadr p) g) ","
          (ktcl:rk (cond ((caddr p)) (0.0)) g))
)

;;; Merge sort tu viet (khong mat phan tu trung nhu vl-sort, chay ca tren clone)
;;; lst = ((khoa-chuoi . du lieu) ...)
(defun ktcl:merge (a b / res)
  (while (and a b)
    (if (< (car (car b)) (car (car a)))
      (setq res (cons (car b) res) b (cdr b))
      (setq res (cons (car a) res) a (cdr a))))
  (append (reverse res) a b)
)

(defun ktcl:sort (lst / runs nxt)
  (setq runs (mapcar 'list lst))
  (while (cdr runs)
    (setq nxt nil)
    (while runs
      (setq nxt  (cons (if (cdr runs) (ktcl:merge (car runs) (cadr runs)) (car runs)) nxt)
            runs (cddr runs)))
    (setq runs (reverse nxt)))
  (car runs)
)

(defun ktcl:groups (sorted / res cur)
  ;; gom cac phan tu lien ke cung khoa; tra ve list cac nhom >= 2 phan tu (list du lieu)
  (foreach x sorted
    (if (and cur (= (car x) (car (car cur))))
      (setq cur (cons x cur))
      (progn
        (if (cdr cur) (setq res (cons (reverse (mapcar 'cdr cur)) res)))
        (setq cur (list x)))))
  (if (cdr cur) (setq res (cons (reverse (mapcar 'cdr cur)) res)))
  (reverse res)
)

(defun ktcl:first-insert (name / ss)
  ;; 1 INSERT dai dien cua block name (nil neu khong co)
  (if (setq ss (ssget "_X" (list '(0 . "INSERT") (cons 2 (ktcl:wcesc name)))))
    (ssname ss 0))
)

;;; ---------- 1. Xref / anh mat file ----------
(defun ktcl:chk-xref (/ tb nm fl p)
  (setq tb (tblnext "BLOCK" T))
  (while tb
    (setq nm (kt:dxf 2 tb) fl (cond ((kt:dxf 70 tb)) (0)))
    (if (and nm (= 4 (logand 4 fl)))
      (progn
        (setq p (cond ((kt:dxf 1 tb)) ("")))
        ;; 70 bit 32 = xref da resolve (CAD da tim thay file, ke ca xref long co duong dan
        ;; tuong doi theo file cha) -> khong bao
        (if (and (= 0 (logand 32 fl)) (not (ktcl:filefound p)))
          (kt:add "SACH" "XREF-MAT" "LOI"
                  (strcat "Xref '" nm "' khong tim thay file: "
                          (if (= (kt:trim p) "") "(khong co duong dan)" p))
                  (ktcl:first-insert nm) nil nil))))
    (setq tb (tblnext "BLOCK")))
)

(defun ktcl:chk-image (/ dict nm defs ed p imgs en ref)
  (if (setq dict (dictsearch (namedobjdict) "ACAD_IMAGE_DICT"))
    (progn
      ;; (3 . ten) (350 . imagedef) ...
      (foreach x dict
        (cond ((= (car x) 3) (setq nm (cdr x)))
              ((and (member (car x) '(350 360)) nm)
               (setq defs (cons (cons nm (cdr x)) defs) nm nil))))
      (if defs
        (foreach en (kt:ss-all '((0 . "IMAGE")))
          (if (setq ref (kt:dxf 340 (entget en)))
            (setq imgs (cons (cons ref en) imgs)))))
      (foreach d (reverse defs)
        (if (setq ed (entget (cdr d)))
          (progn
            (setq p (cond ((kt:dxf 1 ed)) ("")))
            (if (not (ktcl:filefound p))
              (kt:add "SACH" "ANH-MAT" "LOI"
                      (strcat "Anh '" (car d) "' khong tim thay file: "
                              (if (= (kt:trim p) "") "(khong co duong dan)" p))
                      (cdr (assoc (cdr d) imgs)) nil nil)))))))
)

;;; ---------- 2. Z khac 0 trong Model ----------
(defun ktcl:zof (ed typ / zs)
  ;; danh sach cao do Z can kiem cua doi tuong
  (cond
    ((= typ "LWPOLYLINE") (list (cond ((kt:dxf 38 ed)) (0.0))))
    (T
     (foreach c '(10 11 13 14)
       (if (and (assoc c ed)
                (or (/= c 11) (= typ "LINE"))
                (or (member c '(10 11)) (= typ "DIMENSION")))
         (setq zs (cons (cond ((caddr (kt:dxf c ed))) (0.0)) zs))))
     zs))
)

(defun ktcl:chk-z (/ ss i en ed typ zmax)
  (if (setq ss (ssget "_X" (append '((0 . "LINE,LWPOLYLINE,INSERT,TEXT,MTEXT,CIRCLE,ARC,DIMENSION")
                                     (410 . "Model"))
                                   (ktcl:notmark))))
    (progn
      (setq i 0)
      (repeat (sslength ss)
        (setq en (ssname ss i) i (1+ i) ed (entget en) typ (kt:dxf 0 ed) zmax 0.0)
        (foreach z (ktcl:zof ed typ)
          (if (> (abs z) (abs zmax)) (setq zmax z)))
        (if (> (abs zmax) (kt:cfg-num "Z_DUNG_SAI" 0.001))   ; bo sai so so hoc
          (kt:add "SACH" "Z-KHAC0" "CANHBAO"
                  (strcat typ " (layer " (kt:dxf 8 ed) ") co cao do Z = " (ktcl:fmt zmax)
                          " (ban ve 2D can Z = 0)")
                  en nil nil)))))
)

;;; ---------- 3+4. LINE dai 0 + LINE trung ----------
(defun ktcl:chk-lines (/ ss i en ed p1 p2 k1 k2 key lst g)
  (if (setq ss (ssget "_X" (append '((0 . "LINE")) (ktcl:notmark))))
    (progn
      (setq i 0)
      (repeat (sslength ss)
        (setq en (ssname ss i) i (1+ i) ed (entget en)
              p1 (kt:dxf 10 ed) p2 (kt:dxf 11 ed))
        (if (and p1 p2)
          (if (< (distance p1 p2) 1e-4)
            (kt:add "SACH" "LINE-0" "GOIY"
                    (strcat "LINE dai 0 tren layer " (kt:dxf 8 ed) " (rac, nen xoa)")
                    en nil nil)
            (progn
              ;; khoa: khong gian | layer | 2 dau mut da sap xep (khong phu thuoc chieu ve)
              (setq k1 (ktcl:pk p1 0.01) k2 (ktcl:pk p2 0.01))
              (if (< k2 k1) (setq key k1 k1 k2 k2 key))
              (setq lst (cons (cons (strcat (kt:space ed) "|" (strcase (kt:dxf 8 ed)) "|" k1 "|" k2) en)
                              lst))))))
      (setq lst (ktcl:sort lst))
      (foreach g (ktcl:groups lst)
        (kt:add "SACH" "LINE-TRUNG" "CANHBAO"
                (strcat (itoa (length g)) " LINE trung khit nhau tren layer "
                        (kt:dxf 8 (entget (car g))) " (copy chong, nen xoa ban thua)")
                g nil nil))))
)

;;; ---------- 3. LWPOLYLINE suy bien ----------
(defun ktcl:chk-degenerate (/ ss i en ed pts p0 ok)
  (if (setq ss (ssget "_X" (append '((0 . "LWPOLYLINE")) (ktcl:notmark))))
    (progn
      (setq i 0)
      (repeat (sslength ss)
        (setq en (ssname ss i) i (1+ i) ed (entget en) pts nil)
        (foreach x ed (if (= (car x) 10) (setq pts (cons (cdr x) pts))))
        (setq ok nil)
        (if (> (length pts) 1)
          (progn
            (setq p0 (car pts))
            (foreach p (cdr pts) (if (and (not ok) (>= (distance p0 p) 1e-4)) (setq ok T)))))
        (if (not ok)
          (kt:add "SACH" "PLINE-0" "GOIY"
                  (strcat "LWPOLYLINE " (itoa (length pts)) " dinh, chieu dai 0 tren layer "
                          (kt:dxf 8 ed) " (rac, nen xoa)")
                  en nil nil)))))
  ;; TEXT rong: da kiem o module TEXT (TEXT-RONG) - khong bao trung o day
  T
)

;;; ---------- 5. INSERT copy chong ----------
(defun ktcl:chk-insert-dup (/ ss i en ed key lst)
  (if (setq ss (ssget "_X" '((0 . "INSERT"))))
    (progn
      (setq i 0)
      (repeat (sslength ss)
        (setq en (ssname ss i) i (1+ i) ed (entget en))
        (setq key (strcat (kt:space ed) "|" (strcase (cond ((kt:dxf 2 ed)) ("")))
                          "|" (ktcl:pk (kt:dxf 10 ed) 0.01)
                          "|" (ktcl:rk (cond ((kt:dxf 41 ed)) (1.0)) 1e-4)
                          "," (ktcl:rk (cond ((kt:dxf 42 ed)) (1.0)) 1e-4)
                          "," (ktcl:rk (cond ((kt:dxf 43 ed)) (1.0)) 1e-4)
                          "|" (ktcl:rk (* (/ 180.0 pi) (cond ((kt:dxf 50 ed)) (0.0))) 0.01))
              lst (cons (cons key en) lst)))
      (setq lst (ktcl:sort lst))
      (foreach g (ktcl:groups lst)
        (kt:add "SACH" "BLOCK-TRUNG" "CANHBAO"
                (strcat (itoa (length g)) " block '" (kt:dxf 2 (entget (car g)))
                        "' chen chong cung vi tri/ty le/goc (copy chong)")
                g nil nil))))
)

;;; ---------- Duyet noi dung cac dinh nghia block (dung chung 6+7) ----------
(defun ktcl:blkwalk (/ tb nm fl e ed up lays ins)
  ;; *KT:CLBW* = (layer-dung-trong-block  ten-block-chen-long)  (viet HOA)
  ;; Bo qua xref, block khong gian (*Model_Space/*Paper_Space - da co ssget)
  ;; va block kich thuoc an danh *D (mui ten xu ly rieng qua DIMSTYLE)
  (if (null *KT:CLBW*)
    (progn
      (setq tb (tblnext "BLOCK" T))
      (while tb
        (setq nm (kt:dxf 2 tb) fl (cond ((kt:dxf 70 tb)) (0)))
        (if (and nm (= 0 (logand fl (+ 4 16))) (not (wcmatch (strcase nm) "`*D*,`*MODEL_SPACE,`*PAPER_SPACE*")))
          (progn
            (setq e (kt:dxf -2 tb))
            (while e
              (setq ed (entget e))
              (if (or (null ed) (= (kt:dxf 0 ed) "ENDBLK"))
                (setq e nil)
                (progn
                  (setq up (strcase (cond ((kt:dxf 8 ed)) ("0"))))
                  (if (not (member up lays)) (setq lays (cons up lays)))
                  (if (= (kt:dxf 0 ed) "INSERT")
                    (progn
                      (setq up (strcase (cond ((kt:dxf 2 ed)) (""))))
                      (if (not (member up ins)) (setq ins (cons up ins)))))
                  (setq e (entnext e)))))))
        (setq tb (tblnext "BLOCK")))
      (setq *KT:CLBW* (list lays ins))))
  *KT:CLBW*
)

(defun ktcl:dynorig (nm / r)
  ;; ten block dong goc cua block an danh *U (qua xdata AcDbBlockRepBTag)
  (setq r (vl-catch-all-apply
            '(lambda (/ be br xd h e2)
               (setq be (tblobjname "BLOCK" nm)
                     br (kt:dxf 330 (entget be))
                     xd (cdr (assoc "AcDbBlockRepBTag"
                                    (cdr (assoc -3 (entget br '("AcDbBlockRepBTag"))))))
                     h  (cdr (assoc 1005 xd)))
               (if (and h (setq e2 (handent h)))
                 (kt:dxf 2 (entget e2))))
            nil))
  (if (or (vl-catch-all-error-p r) (/= (type r) 'STR)) nil r)
)

;;; ---------- 6. Block chua purge ----------
(defun ktcl:addused (nm used)
  (if (and nm (not (member (strcase nm) used))) (cons (strcase nm) used) used)
)

(defun ktcl:chk-unused-blocks (/ used tb nm fl en ed eff unused shown br)
  ;; ten block duoc dung: INSERT trong cac khong gian + chen long trong block
  (foreach en (kt:ss-all '((0 . "INSERT")))
    (setq nm (kt:dxf 2 (entget en)) used (ktcl:addused nm used))
    (if (and nm (wcmatch (strcase nm) "`*U*"))
      (progn
        (setq eff (kt:effname en))
        (if (and eff (/= (strcase eff) (strcase nm)))
          (setq used (ktcl:addused eff used))
          (setq used (ktcl:addused (ktcl:dynorig nm) used))))))
  (foreach nm (cadr (ktcl:blkwalk))
    (setq used (ktcl:addused nm used))
    (if (wcmatch nm "`*U*") (setq used (ktcl:addused (ktcl:dynorig nm) used))))
  ;; block mui ten / leader tham chieu tu DIMSTYLE
  (setq tb (tblnext "DIMSTYLE" T))
  (while tb
    (if (and (kt:dxf 2 tb) (setq ed (entget (tblobjname "DIMSTYLE" (kt:dxf 2 tb)))))
      (foreach x ed
        (if (and (member (car x) '(341 342 343 344))
                 (= (type (cdr x)) 'ENAME)
                 (setq br (entget (cdr x)))
                 (= (kt:dxf 0 br) "BLOCK_RECORD"))
          (setq used (ktcl:addused (kt:dxf 2 br) used)))))
    (setq tb (tblnext "DIMSTYLE")))
  ;; block dinh nghia khong duoc dung
  (setq tb (tblnext "BLOCK" T))
  (while tb
    (setq nm (kt:dxf 2 tb) fl (cond ((kt:dxf 70 tb)) (0)))
    (if (and nm
             (/= (substr nm 1 1) "*")             ; an danh, *Model_Space, *Paper_Space
             (/= (substr nm 1 1) "_")             ; mui ten he thong (_ArchTick, _Oblique...)
             (not (vl-string-search "|" nm))
             (= 0 (logand fl (+ 1 4 16)))
             (not (member (strcase nm) used)))
      (setq unused (cons nm unused)))
    (setq tb (tblnext "BLOCK")))
  (if unused
    (progn
      (setq unused (reverse unused) shown nil)
      (foreach nm unused (if (< (length shown) 8) (setq shown (cons nm shown))))
      (kt:add "SACH" "BLOCK-THUA" "GOIY"
              (strcat (itoa (length unused)) " block dinh nghia khong duoc dung (nen PURGE): "
                      (kt:join (reverse shown) ", ")
                      (if (> (length unused) 8) ", ..." ""))
              nil '(0.0 0.0) nil)))
)

;;; ---------- 7. Layer rong ----------
(defun ktcl:chk-empty-layers (/ tb nm up std cl cand blays empty shown)
  (setq std (kt:cfg-names "LAYER")
        cl  (strcase (getvar "CLAYER"))
        tb  (tblnext "LAYER" T))
  (while tb
    (setq nm (kt:dxf 2 tb) up (if nm (strcase nm) ""))
    (if (and nm
             (not (member up (list "0" "DEFPOINTS" cl (strcase *KT:LAYER*))))
             (not (vl-string-search "|" up))
             (not (member up std)))                      ; layer chuan de san trong mau: bo qua
      (setq cand (cons nm cand)))
    (setq tb (tblnext "LAYER")))
  ;; loc re (layer dung trong block) truoc, roi moi ssget "_X" tung layer con lai
  (if cand
    (progn
      (setq blays (car (ktcl:blkwalk)))
      (foreach nm (reverse cand)
        (if (and (not (member (strcase nm) blays))
                 (null (ssget "_X" (list (cons 8 (ktcl:wcesc nm))))))
          (setq empty (cons nm empty))))))
  (if empty
    (progn
      (setq empty (reverse empty) shown nil)
      (foreach nm empty (if (< (length shown) 8) (setq shown (cons nm shown))))
      (kt:add "SACH" "LAYER-RONG" "GOIY"
              (strcat (itoa (length empty)) " layer rong khong dung (nen PURGE): "
                      (kt:join (reverse shown) ", ")
                      (if (> (length empty) 8) ", ..." ""))
              nil '(0.0 0.0) nil)))
)

;;; ---------- 8. HATCH khong lien ket ----------
(defun ktcl:chk-hatch (/ ss i en ed sp grp g)
  ;; gom theo khong gian: hatch khong lien ket rat pho bien (copy/mirror lam mat lien ket),
  ;; khong phai loi ban ve -> 1 dong GOIY / khong gian (chon toi da 50 hatch)
  (if (setq ss (ssget "_X" (append '((0 . "HATCH") (71 . 0)) (ktcl:notmark))))
    (progn
      (setq i 0)
      (repeat (sslength ss)
        (setq en (ssname ss i) i (1+ i) ed (entget en) sp (kt:space ed))
        (if (setq g (assoc sp grp))
          (setq grp (subst (list sp (1+ (cadr g))
                                 (if (< (length (caddr g)) 50) (cons en (caddr g)) (caddr g)))
                           g grp))
          (setq grp (cons (list sp 1 (list en)) grp))))
      (foreach g (reverse grp)
        (kt:add "SACH" "HATCH-KLK" "GOIY"
                (strcat (itoa (cadr g)) " HATCH khong lien ket bien trong " (car g)
                        " (sua bien se khong cap nhat hatch)")
                (reverse (caddr g)) nil nil))))
)

;;; ---------- Chay ----------
(defun ktcl:run (/ n)
  (if (kt:cfg-ok)
    (progn
      (kt:begin "SACH")
      (setq *KT:CLBW* nil)
      (princ "\n[SACH] Dang kiem tra ve sinh file...")
      (ktcl:try 'ktcl:chk-xref)
      (ktcl:try 'ktcl:chk-image)
      (ktcl:try 'ktcl:chk-z)
      (ktcl:try 'ktcl:chk-lines)
      (ktcl:try 'ktcl:chk-degenerate)
      (ktcl:try 'ktcl:chk-insert-dup)
      (ktcl:try 'ktcl:chk-unused-blocks)
      (ktcl:try 'ktcl:chk-empty-layers)
      (ktcl:try 'ktcl:chk-hatch)
      (setq n (kt:finish "SACH"))
      (setq *KT:CLBW* nil)
      n)
    (progn (princ "\n[SACH] Khong co file chuan - bo qua.") nil))
)

(defun c:KTSACH () (kt:cmd 'ktcl:run) (princ))

(princ "\nKT_Clean da nap. Lenh: KTSACH")
(princ)
