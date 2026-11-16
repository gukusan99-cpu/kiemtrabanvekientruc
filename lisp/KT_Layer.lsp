;;; ============================================================
;;; KT_Layer.lsp  -  Module "LAYER": kiem tra layer / mau / linetype
;;; ------------------------------------------------------------
;;; Lenh  : KTLAYER          Ham khong hoi (cho KTALL): (ktlay:run)
;;; Can   : KT_Core.lsp nap truoc.
;;;
;;; Ma loi:
;;;   LAYER-LA    LOI     layer co doi tuong nhung khong co trong muc LAYER cua chuan
;;;   LAYER-TT    CANHBAO layer chuan nhung mau/linetype/lineweight/plot khac chuan
;;;   LAYER-0     LOI     doi tuong ve tren layer 0 (Model/Layout)
;;;   MAU-BYOBJ   CANHBAO doi tuong gan mau/linetype/lineweight rieng (khong ByLayer)
;;;   LAYER-DEFPT CANHBAO doi tuong hinh hoc tren DEFPOINTS (se khong in)
;;;   LAYER-TAT   GOIY    layer dang tat/dong bang nhung co doi tuong
;;;   BLOCK-LAYER GOIY    trong dinh nghia block co doi tuong o layer khong chuan
;;;
;;; Chi doc ban ve, khong sua. Danh dau tren layer KT_CHECK (qua kt:add).
;;; ============================================================

(vl-load-com)

;;; ---------- Tien ich ----------
(defun ktlay:try (fn / r)
  ;; chay 1 kiem tra con, bat loi de khong hong ca lenh
  (setq r (vl-catch-all-apply fn nil))
  (if (vl-catch-all-error-p r)
    (progn
      (princ (strcat "\n[LAYER] Loi noi bo khi chay " (vl-princ-to-string fn)
                     ": " (vl-catch-all-error-message r)))
      nil)
    r)
)

(defun ktlay:wcesc (s / i c r)
  ;; thoat ky tu dac biet cua wcmatch de dung trong bo loc ssget
  (setq r "" i 1)
  (while (<= i (strlen s))
    (setq c (substr s i 1))
    (setq r (strcat r (if (vl-string-search c "#@.*?~[]-,`") "`" "") c)
          i (1+ i)))
  r
)

(defun ktlay:notmark ()
  ;; bo loc ssget: loai doi tuong danh dau tren layer KT_CHECK
  (list '(-4 . "<NOT") (cons 8 (ktlay:wcesc *KT:LAYER*)) '(-4 . "NOT>"))
)

(defun ktlay:skip-pats ()
  ;; mau LAYER_BO_QUA. Bo mau "*" don le: thuong do "*|*" bi tach sai boi dau '|'
  (vl-remove-if '(lambda (x) (member (kt:trim x) '("" "*")))
                (kt:cfg-list "LAYER_BO_QUA"))
)

(defun ktlay:ignored (up)
  ;; up = ten layer viet HOA. T neu bo qua (xref, KT_CHECK, LAYER_BO_QUA)
  (or (vl-string-search "|" up)
      (= up (strcase *KT:LAYER*))
      (= up "CHECK_DIM_OVERLAP")                       ; layer danh dau cua lisp CDO
      (and *KT:LAYSKIP* (kt:wcmatch-any up *KT:LAYSKIP*)))
)

(defun ktlay:laycount (name / ss)
  ;; (so doi tuong . doi tuong dai dien) tren layer name (moi khong gian)
  (if (setq ss (ssget "_X" (list (cons 8 (ktlay:wcesc name)))))
    (cons (sslength ss) (ssname ss 0))
    (cons 0 nil))
)

(defun ktlay:lwstr (lw)
  (cond ((null lw) "?")
        ((= lw -1) "ByLayer")
        ((= lw -2) "ByBlock")
        ((= lw -3) "Default")
        (T (strcat (rtos (/ lw 100.0) 2 2) "mm")))
)

(defun ktlay:tbl (/ tb res)
  ;; danh sach layer trong ban ve: (ten TENHOA mau(62) co70 linetype)
  (setq tb (tblnext "LAYER" T))
  (while tb
    (if (kt:dxf 2 tb)
      (setq res (cons (list (kt:dxf 2 tb) (strcase (kt:dxf 2 tb))
                            (cond ((kt:dxf 62 tb)) (7))
                            (cond ((kt:dxf 70 tb)) (0))
                            (cond ((kt:dxf 6 tb)) ("Continuous")))
                      res)))
    (setq tb (tblnext "LAYER")))
  (reverse res)
)

;;; ---------- 1. Layer co doi tuong nhung khong co trong chuan ----------
(defun ktlay:chk-notstd (/ up cr)
  (if (null *KT:LAYSTD*)
    (princ "\n[LAYER] File chuan chua co muc LAYER - bo qua kiem tra LAYER-LA.")
    (foreach L *KT:LAYTBL*
      (setq up (nth 1 L))
      (if (and (not (member up '("0" "DEFPOINTS")))
               (not (ktlay:ignored up))
               (not (member (kt:ukey (car L)) *KT:LAYSTD*)))
        (progn
          (setq cr (ktlay:laycount (car L)))
          (if (> (car cr) 0)
            (kt:add "LAYER" "LAYER-LA" "LOI"
                    (strcat "Layer '" (car L) "' khong co trong chuan cong ty ("
                            (itoa (car cr)) " doi tuong)")
                    (cdr cr) nil nil))))))
)

;;; ---------- 2. Layer chuan nhung thuoc tinh khac chuan ----------
(defun ktlay:chk-prop (/ row ed sc slt slw spl col ltp lw pl tc diffs cr)
  (if *KT:LAYSTD*
    (foreach L *KT:LAYTBL*
      (if (and (not (ktlay:ignored (nth 1 L)))
               (setq row (kt:cfg-row "LAYER" (car L))))
        (progn
          ;; LAYER|ten|mau|linetype|lineweight|plot
          (setq ed    (entget (tblobjname "LAYER" (car L)))
                col   (abs (nth 2 L))
                tc    (kt:dxf 420 ed)
                ltp   (nth 4 L)
                lw    (cond ((kt:dxf 370 ed)) (-3))
                pl    (cond ((kt:dxf 290 ed)) (1))
                sc    (kt:num (nth 1 row))
                slt   (kt:trim (nth 2 row))
                slw   (kt:num (nth 3 row))
                spl   (kt:num (nth 4 row))
                diffs nil)
          (if (and sc (/= (fix sc) col))   ; TrueColor: chi so mau ACI (file chuan khong luu TC)
            (setq diffs (cons (strcat "mau " (itoa col) (if tc " (TrueColor)" "")
                                      " (chuan " (itoa (fix sc)) ")")
                              diffs)))
          (if (and (/= slt "") (/= (strcase slt) (strcase ltp)))
            (setq diffs (cons (strcat "linetype " ltp " (chuan " slt ")") diffs)))
          (if (and slw (/= (fix slw) lw))
            (setq diffs (cons (strcat "lineweight " (ktlay:lwstr lw)
                                      " (chuan " (ktlay:lwstr (fix slw)) ")")
                              diffs)))
          (if (and spl (/= (if (= (fix spl) 0) 0 1) (if (= pl 0) 0 1)))
            (setq diffs (cons (strcat "plot " (if (= pl 0) "tat" "bat")
                                      " (chuan " (if (= (fix spl) 0) "tat" "bat") ")")
                              diffs)))
          (if diffs
            (progn
              (setq cr (ktlay:laycount (car L)))
              (kt:add "LAYER" "LAYER-TT" "CANHBAO"
                      (strcat "Layer '" (car L) "' khac chuan: " (kt:join (reverse diffs) "; "))
                      (cdr cr) nil nil)))))))
)

;;; ---------- 3. Doi tuong tren layer 0 ----------
(defun ktlay:chk-layer0 (/ ss i en ed kh sp)
  ;; Model -> LOI; layout -> CANHBAO. Bo qua block khung ten (thuong chen o layer 0 tren layout)
  (setq kh (kt:frame-names))
  (if (setq ss (ssget "_X" '((8 . "0") (-4 . "<NOT") (0 . "VIEWPORT") (-4 . "NOT>"))))
    (progn
      (setq i 0)
      (repeat (sslength ss)
        (setq en (ssname ss i) ed (entget en) i (1+ i) sp (kt:space ed))
        (if (not (and kh (= (kt:dxf 0 ed) "INSERT") (kt:wcmatch-any (kt:effname en) (mapcar 'kt:wcesc kh))))
          (kt:add "LAYER" "LAYER-0" (if (= sp "Model") "LOI" "CANHBAO")
                  (strcat (kt:dxf 0 ed) " ve tren layer 0 (" sp
                          "), can chuyen sang layer chuan")
                  en nil nil)))))
)

;;; ---------- 4. Mau/linetype/lineweight gan rieng (ByObject) ----------
(defun ktlay:typekeys (typ)
  ;; cac ten nhom de so voi MAU_BYOBJ_BO_QUA (vd DIM, TEXT)
  (cond ((wcmatch typ "*DIMENSION,LEADER,MULTILEADER,TOLERANCE") (list typ "DIM" "DIMENSION"))
        ((member typ '("MTEXT" "ATTDEF")) (list typ "TEXT"))
        (T (list typ)))
)

(defun ktlay:skiptype (typ pats / ok)
  (if pats
    (foreach k (ktlay:typekeys typ)
      (if (and (not ok) (kt:wcmatch-any k pats)) (setq ok T))))
  ok
)

(defun ktlay:chk-byobj (/ ss i en ed typ c62 lt lw parts pats)
  (if (= 1 (fix (kt:cfg-num "LAYER_MAU_BYLAYER" 0)))
    (progn
      (setq pats (kt:cfg-list "MAU_BYOBJ_BO_QUA"))
      (if (setq ss (ssget "_X" (append '((-4 . "<NOT") (0 . "VIEWPORT") (-4 . "NOT>"))
                                       (ktlay:notmark))))
        (progn
          (setq i 0)
          (repeat (sslength ss)
            (setq en (ssname ss i) i (1+ i) ed (entget en) typ (kt:dxf 0 ed))
            (if (and (not (ktlay:skiptype typ pats))
                     (not (ktlay:ignored (strcase (cond ((kt:dxf 8 ed)) ("0"))))))
              (progn
                (setq c62 (kt:dxf 62 ed) lt (kt:dxf 6 ed) lw (kt:dxf 370 ed) parts nil)
                (if (and c62 (/= c62 256))
                  (setq parts (cons (strcat "mau=" (if (= c62 0) "ByBlock" (itoa c62))) parts)))
                (if (and lt (/= (strcase lt) "BYLAYER"))
                  (setq parts (cons (strcat "linetype=" lt) parts)))
                (if (and lw (/= lw -1))
                  (setq parts (cons (strcat "lineweight=" (ktlay:lwstr lw)) parts)))
                (if parts
                  (kt:add "LAYER" "MAU-BYOBJ" "CANHBAO"
                          (strcat typ " (layer " (kt:dxf 8 ed) ") gan "
                                  (kt:join (reverse parts) ", ") " - chuan yeu cau ByLayer")
                          en nil nil)))))))))
)

;;; ---------- 5. Doi tuong hinh hoc tren DEFPOINTS ----------
(defun ktlay:chk-defpoints (/ ss i en ed)
  (if (setq ss (ssget "_X" '((8 . "DEFPOINTS")
                             (-4 . "<NOT") (0 . "VIEWPORT,*DIMENSION") (-4 . "NOT>"))))
    (progn
      (setq i 0)
      (repeat (sslength ss)
        (setq en (ssname ss i) ed (entget en) i (1+ i))
        (kt:add "LAYER" "LAYER-DEFPT" "CANHBAO"
                (strcat (kt:dxf 0 ed) " nam tren layer DEFPOINTS (" (kt:space ed)
                        ") - se KHONG in ra")
                en nil nil))))
)

;;; ---------- 6. Layer tat / dong bang nhung co doi tuong ----------
(defun ktlay:chk-offfrz (/ off frz cr st)
  (foreach L *KT:LAYTBL*
    (setq off (< (nth 2 L) 0)
          frz (= 1 (logand 1 (nth 3 L))))
    (if (and (or off frz)
             (not (ktlay:ignored (nth 1 L))))
      (progn
        (setq cr (ktlay:laycount (car L))
              st (cond ((and off frz) "tat + dong bang") (off "tat") (T "dong bang")))
        (if (> (car cr) 0)
          (kt:add "LAYER" "LAYER-TAT" "GOIY"
                  (strcat "Layer '" (car L) "' dang " st " nhung co " (itoa (car cr))
                          " doi tuong (co the che giau loi)")
                  (cdr cr) nil nil)))))
)

;;; ---------- 7. Doi tuong trong dinh nghia block o layer khong chuan ----------
(defun ktlay:blkbad (first / e ed up n bad)
  ;; tra ve (so doi tuong sai . danh sach layer sai) cua 1 dinh nghia block
  (setq e first n 0)
  (while e
    (setq ed (entget e))
    (if (or (null ed) (= (kt:dxf 0 ed) "ENDBLK"))
      (setq e nil)
      (progn
        (setq up (strcase (cond ((kt:dxf 8 ed)) ("0"))))
        (if (and (/= up "0")
                 (not (member (kt:ukey (kt:dxf 8 ed)) *KT:LAYSTD*))
                 (not (ktlay:ignored up)))
          (progn
            (setq n (1+ n))
            (if (not (member up bad)) (setq bad (cons up bad)))))
        (setq e (entnext e)))))
  (cons n (reverse bad))
)

(defun ktlay:chk-blocks (/ tb nm fl res r names found ss i en up shown)
  (if *KT:LAYSTD*
    (progn
      (setq tb (tblnext "BLOCK" T))
      (while tb
        (setq nm (kt:dxf 2 tb) fl (cond ((kt:dxf 70 tb)) (0)))
        (if (and nm
                 (/= (substr nm 1 1) "*")
                 (not (vl-string-search "|" nm))
                 (= 0 (logand fl (+ 1 4 16))))
          (progn
            (setq r (ktlay:blkbad (kt:dxf -2 tb)))
            (if (> (car r) 0) (setq res (cons (cons nm r) res)))))
        (setq tb (tblnext "BLOCK")))
      (if res
        (progn
          ;; tim 1 INSERT dai dien cho moi block bi danh dau (1 lan duyet)
          (setq names (mapcar '(lambda (x) (strcase (car x))) res))
          (if (setq ss (ssget "_X" '((0 . "INSERT"))))
            (progn
              (setq i 0)
              (while (and (< i (sslength ss)) (< (length found) (length names)))
                (setq en (ssname ss i) i (1+ i)
                      up (strcase (cond ((kt:dxf 2 (entget en))) (""))))
                ;; dynamic block: ten *U.. -> ten that
                (if (wcmatch up "`*U*") (setq up (strcase (kt:str (kt:effname en)))))
                (if (and (member up names) (not (assoc up found)))
                  (setq found (cons (cons up en) found))))))
          (foreach x (reverse res)
            (setq shown (cddr x))
            (if (> (length shown) 5)
              (setq shown (list (nth 0 shown) (nth 1 shown) (nth 2 shown) (nth 3 shown) (nth 4 shown)
                                (strcat "... (+" (itoa (- (length shown) 5)) ")"))))
            (kt:add "LAYER" "BLOCK-LAYER" "GOIY"
                    (strcat "Block '" (car x) "' co " (itoa (nth 1 x))
                            " doi tuong ben trong o layer khong chuan: " (kt:join shown ", ")
                            (if (cdr (assoc (strcase (car x)) found)) "" " (block khong duoc chen truc tiep)"))
                    (cdr (assoc (strcase (car x)) found)) nil nil))))))
)

;;; ---------- Chay ----------
(defun ktlay:prep ()
  (setq *KT:LAYSKIP* (ktlay:skip-pats)
        *KT:LAYSTD*  (kt:cfg-keys "LAYER")   ; so bang kt:ukey (ten co dau)
        *KT:LAYTBL*  (ktlay:tbl))
  T
)

(defun ktlay:run (/ n)
  (if (kt:cfg-ok)
    (progn
      (kt:begin "LAYER")
      (setq *KT:LAYSKIP* nil *KT:LAYSTD* nil *KT:LAYTBL* nil)
      (princ "\n[LAYER] Dang kiem tra layer...")
      (ktlay:try 'ktlay:prep)
      (ktlay:try 'ktlay:chk-notstd)
      (ktlay:try 'ktlay:chk-prop)
      (ktlay:try 'ktlay:chk-layer0)
      (ktlay:try 'ktlay:chk-byobj)
      (ktlay:try 'ktlay:chk-defpoints)
      (ktlay:try 'ktlay:chk-offfrz)
      (ktlay:try 'ktlay:chk-blocks)
      (setq n (kt:finish "LAYER"))
      (setq *KT:LAYTBL* nil)
      n)
    (progn (princ "\n[LAYER] Khong co file chuan - bo qua.") nil))
)

(defun c:KTLAYER () (kt:cmd 'ktlay:run) (princ))

(princ "\nKT_Layer da nap. Lenh: KTLAYER")
(princ)
