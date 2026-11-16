;;; ============================================================
;;; KT_Text.lsp  -  Module "TEXT": textstyle, font, chieu cao chu
;;; ------------------------------------------------------------
;;; Lenh  : KTTEXT           Ham khong hoi (cho KTALL): (kttxt:run)
;;; Can   : KT_Core.lsp nap truoc.
;;;
;;; Ma loi:
;;;   TEXT-STYLE   LOI     chu dung textstyle khong co trong chuan (1 dong/style)
;;;   TEXT-FONT    LOI     textstyle chuan nhung font/bigfont khac chuan
;;;   TEXT-CAO     CANHBAO chieu cao chu quy ra giay khong thuoc CAO_CHU_GIAY
;;;                GOIY    neu khop 1 TY_LE_CHO_PHEP nho hon TL khung (chu hinh chi tiet)
;;;                (bo qua chu annotative, MTEXT co ma \H, chu tren LAYER_BO_QUA)
;;;   TEXT-RONG    GOIY    chu rong (chi co khoang trang)
;;;   TEXT-WIDTH   GOIY    width factor cua chu khac width factor chuan cua style
;;;   TEXT-FONTMAT CANHBAO khong tim thay file font .shx (1 dong/style)
;;;   TEXT-STYLECAO CANHBAO textstyle chuan nhung CHIEU CAO CO DINH khac chuan (vd '0 ARIAL 2.5' = 250
;;;                 trong template; ban ve dat 0 hoac 2.5 -> chu moi go se sai co; dim dung style co
;;;                 chieu cao co dinh se BO QUA DIMTXT)
;;;
;;; Pham vi: TEXT/MTEXT/ATTDEF trong Model va cac Layout (khong duyet chu
;;; nam trong dinh nghia block / ATTRIB).
;;; ============================================================

(vl-load-com)

;;; ---------- Tien ich ----------
(defun kttxt:try (fn / r)
  (setq r (vl-catch-all-apply fn nil))
  (if (vl-catch-all-error-p r)
    (progn
      (princ (strcat "\n[TEXT] Loi noi bo khi chay " (vl-princ-to-string fn)
                     ": " (vl-catch-all-error-message r)))
      nil)
    r)
)

(defun kttxt:fmt (x / s)
  ;; so -> chuoi gon: 2.50 -> "2.5", 100.00 -> "100"
  (setq s (rtos x 2 2))
  (if (vl-string-search "." s)
    (progn
      (setq s (vl-string-right-trim "0" s))
      (setq s (vl-string-right-trim "." s))))
  s
)

(defun kttxt:fname (f / p)
  ;; bo duong dan: "C:\\a\\romans.shx" -> "romans.shx"
  (setq f (kt:trim f))
  (while (setq p (vl-string-search "\\" f)) (setq f (substr f (+ p 2))))
  (while (setq p (vl-string-search "/" f)) (setq f (substr f (+ p 2))))
  f
)

(defun kttxt:ext (f / p r)
  ;; phan mo rong viet HOA khong dau cham ("" neu khong co)
  (setq f (kttxt:fname f) r "")
  (while (setq p (vl-string-search "." f))
    (setq r (substr f (+ p 2)) f (substr f (+ p 2))))
  (strcase r)
)

(defun kttxt:fkey (f / n e)
  ;; khoa so sanh font: ten file HOA, bo duong dan va phan mo rong
  (setq n (strcase (kttxt:fname (cond (f) ("")))) e (kttxt:ext n))
  (if (/= e "") (substr n 1 (- (strlen n) (strlen e) 1)) n)
)

(defun kttxt:stylefont (name / te ed xd fam f)
  ;; (font bigfont ttf-family) cua textstyle trong ban ve
  (setq te (tblobjname "STYLE" name)
        ed (if te (entget te '("ACAD")))
        f  (cond ((kt:dxf 3 ed)) ("")))
  ;; font TrueType theo ten ho (font file rong): doc xdata ACAD 1000
  (if (setq xd (cdr (assoc -3 ed)))
    (setq fam (cdr (assoc 1000 (cdr (assoc "ACAD" xd))))))
  (list f (cond ((kt:dxf 4 ed)) ("")) fam)
)

(defun kttxt:mtstr (ed / s)
  ;; noi dung day du cua MTEXT (cac doan 3 + 1)
  (setq s "")
  (foreach x ed (if (member (car x) '(3 1)) (setq s (strcat s (cdr x)))))
  s
)

(defun kttxt:blank (s / p)
  ;; T neu chuoi chi gom khoang trang / ma xuong dong MTEXT / ngoac nhom
  (foreach k '("\\P" "\\~" "{" "}")
    (while (setq p (vl-string-search k s))
      (setq s (strcat (substr s 1 p) " " (substr s (+ p 1 (strlen k)))))))
  (= (kt:trim s) "")
)

(defun kttxt:hok (hp lst / ok)
  ;; hp thuoc danh sach chieu cao giay (dung sai 3%)
  (foreach c lst
    (if (and (not ok) (<= (abs (- hp c)) (* 0.03 c))) (setq ok T)))
  ok
)

(defun kttxt:annop (ed / xd on vals)
  ;; T neu doi tuong annotative (XData AcadAnnotative: AnnotativeData { 1070 ver, 1070 flag=1 })
  (setq xd (cdr (assoc "AcadAnnotative" (cdr (assoc -3 ed)))))
  (while xd
    (cond
      ((equal (car xd) '(1000 . "AnnotativeData")) (setq on T))
      ((and on (equal (car xd) '(1002 . "}"))) (setq xd nil on nil))
      ((and on (= (car (car xd)) 1070)) (setq vals (cons (cdr (car xd)) vals))))
    (setq xd (cdr xd)))
  (setq vals (reverse vals))
  (and (cadr vals) (= (cadr vals) 1))
)

(defun kttxt:vp-at (p / res vps)
  ;; ty le cac viewport nhin thay diem model p
  (setq vps (vl-catch-all-apply 'kt:viewports nil))
  (if (vl-catch-all-error-p vps) (setq vps nil))
  (foreach v vps
    (if (and (listp v) (numberp (nth 2 v)) (> (nth 2 v) 0) (nth 3 v) (nth 4 v)
             (kt:inbox p (nth 3 v) (nth 4 v)))
      (setq res (cons (nth 2 v) res))))
  res
)

(defun kttxt:wcesc (s / i c r)
  ;; thoat ky tu dac biet wcmatch de dung trong bo loc ssget
  (setq r "" i 1)
  (while (<= i (strlen s))
    (setq c (substr s i 1))
    (setq r (strcat r (if (vl-string-search c "#@.*?~[]-,`") "`" "") c)
          i (1+ i)))
  r
)

(defun kttxt:width-std (sty / up c row sw)
  ;; width factor chuan cua style (cache *KT:TXWID*), nil neu khong co
  (setq up (strcase sty))
  (if (setq c (assoc up *KT:TXWID*))
    (cdr c)
    (progn
      (setq row (kt:cfg-row "TEXTSTYLE" sty)
            sw  (if row (kt:num (nth 4 row))))
      (if (not (and (numberp sw) (> sw 0))) (setq sw nil))
      (setq *KT:TXWID* (cons (cons up sw) *KT:TXWID*))
      sw))
)

(defun kttxt:style-of (ed)
  (cond ((kt:dxf 7 ed)) ("Standard"))
)

;;; ---------- Duyet chu 1 lan: gom style + kiem chieu cao/rong/width ----------
(defun kttxt:scan (/ ss i en ed typ sty up rec hs h hp sp sc pt s sw w lay cands alt skip)
  ;; *KT:TXFIRST* : ((STYLEHOA . ename dau tien) ...)
  ;; *KT:TXBAD*   : ((STYLEHOA ten so-luong (ename...)) ...) style khong chuan
  (setq *KT:TXFIRST* nil *KT:TXBAD* nil *KT:TXWID* nil
        skip (kt:cfg-list "LAYER_BO_QUA")
        hs (vl-remove-if '(lambda (x) (or (null x) (<= x 0)))
                         (mapcar 'kt:num (kt:cfg-list "CAO_CHU_GIAY")))
        alt (vl-remove-if '(lambda (x) (or (null x) (<= x 0)))
                          (mapcar 'kt:num (kt:cfg-list "TY_LE_CHO_PHEP"))))
  (if (setq ss (ssget "_X" (list '(0 . "TEXT,MTEXT,ATTDEF")
                                 '(-4 . "<NOT") (cons 8 (kttxt:wcesc *KT:LAYER*)) '(-4 . "NOT>"))))
    (progn
      (setq i 0)
      (repeat (sslength ss)
        (setq en (ssname ss i) i (1+ i) ed (entget en '("AcadAnnotative"))
              typ (kt:dxf 0 ed) sty (kttxt:style-of ed) up (kt:ukey sty)
              lay (cond ((kt:dxf 8 ed)) ("0")))
        (if (not (and skip (kt:wcmatch-any lay skip)))
          (progn
            (if (not (assoc up *KT:TXFIRST*))
              (setq *KT:TXFIRST* (cons (cons up en) *KT:TXFIRST*)))
            ;; --- style khong chuan ---
            (if (and *KT:TXSTD* (not (member up *KT:TXSTD*)))
              (if (setq rec (assoc up *KT:TXBAD*))
                (setq *KT:TXBAD*
                       (subst (list up (nth 1 rec) (1+ (nth 2 rec))
                                    (if (< (length (nth 3 rec)) 10) (cons en (nth 3 rec)) (nth 3 rec)))
                              rec *KT:TXBAD*))
                (setq *KT:TXBAD* (cons (list up sty 1 (list en)) *KT:TXBAD*))))
            ;; --- noi dung ---
            (setq s (if (= typ "MTEXT") (kttxt:mtstr ed) (cond ((kt:dxf 1 ed)) (""))))
            (if (and (/= typ "ATTDEF") (kttxt:blank s))
              (kt:add "TEXT" "TEXT-RONG" "GOIY"
                      (strcat typ " rong (khong co noi dung) tren layer " lay)
                      en nil nil))
            ;; --- chieu cao quy ra giay (bo qua chu annotative: 40 khong phai chieu cao giay) ---
            (setq h (kt:dxf 40 ed) pt (kt:dxf 10 ed))
            (if (and hs (numberp h) (> h 0) pt
                     (not (kttxt:annop ed))
                     (not (and (= typ "MTEXT") (vl-string-search "\\H" s))))
              (progn
                (setq sp (kt:space ed)
                      sc (if (= sp "Model") (kt:scale-at (kt:2d pt) sp) 1.0))
                (if (and (numberp sc) (> sc 0))
                  (progn
                    (setq hp (/ h sc)
                          ;; cac ty le khac nhin thay chu (viewport chi tiet chong len vung MB)
                          cands (if (= sp "Model") (kttxt:vp-at (kt:2d pt))))
                    (if (and (not (kttxt:hok hp hs))
                             (not (vl-remove-if-not '(lambda (c) (kttxt:hok (/ h c) hs)) cands)))
                      (progn
                        ;; khop 1 ty le cho phep nho hon (hinh chi tiet 1/20 trong khung 1/100) -> GOIY
                        (setq cands (if (= sp "Model")
                                      (vl-remove-if-not
                                        '(lambda (c) (and (< c sc) (kttxt:hok (/ h c) hs))) alt)))
                        (kt:add "TEXT" "TEXT-CAO" (if cands "GOIY" "CANHBAO")
                                (strcat typ " cao " (kttxt:fmt h)
                                        (if (= sp "Model")
                                          (strcat " o TL 1/" (kttxt:fmt sc))
                                          (strcat " trong layout " sp))
                                        " = " (kttxt:fmt hp) "mm giay, khong thuoc chuan ("
                                        (kt:join (mapcar 'kttxt:fmt hs) ", ") ")"
                                        (if cands
                                          (strcat " - hop TL 1/" (kttxt:fmt (car cands))
                                                  ", neu la chu cua hinh chi tiet thi bo qua")
                                          ""))
                                en nil nil)))))))
            ;; --- width factor so voi style chuan ---
            (if (and (member typ '("TEXT" "ATTDEF"))
                     (setq sw (kttxt:width-std sty)))
              (progn
                (setq w (cond ((kt:dxf 41 ed)) (1.0)))
                (if (> (abs (- w sw)) 0.005)
                  (kt:add "TEXT" "TEXT-WIDTH" "GOIY"
                          (strcat typ " style " sty " co width factor " (kttxt:fmt w)
                                  " (chuan " (kttxt:fmt sw) ")")
                          en nil nil)))))))))
  T
)

;;; ---------- 1. Style khong co trong chuan ----------
(defun kttxt:chk-badstyle ()
  (if (null *KT:TXSTD*)
    (princ "\n[TEXT] File chuan chua co muc TEXTSTYLE - bo qua kiem tra TEXT-STYLE.")
    (foreach x (reverse *KT:TXBAD*)
      ;; x = (STYLEHOA ten so-luong (ename...))
      (kt:add "TEXT" "TEXT-STYLE" "LOI"
              (strcat "Textstyle '" (nth 1 x) "' khong co trong chuan cong ty ("
                      (itoa (nth 2 x)) " doi tuong chu)")
              (reverse (nth 3 x)) nil nil)))
)

;;; ---------- 2+6. Font khac chuan / khong tim thay font ----------
(defun kttxt:found (f / e)
  ;; T neu tim thay file font (thu them .shx, thu ten khong duong dan)
  (setq e (kttxt:ext f))
  (or (findfile f)
      (findfile (kttxt:fname f))
      (and (= e "") (or (findfile (strcat f ".shx"))
                        (findfile (strcat (kttxt:fname f) ".shx")))))
)

(defun kttxt:chk-fonts (/ tb nm fl row sf act sbf abf en diffs miss e sh ah)
  (setq tb (tblnext "STYLE" T))
  (while tb
    (setq nm (kt:dxf 2 tb) fl (cond ((kt:dxf 70 tb)) (0)))
    (if (and nm (/= nm "")
             (= 0 (logand fl 1))                 ; bo style shape file
             (not (vl-string-search "|" nm)))
      (progn
        (setq act (kttxt:stylefont nm)
              en  (cdr (assoc (kt:ukey nm) *KT:TXFIRST*))
              diffs nil miss nil)
        ;; --- so font voi chuan ---
        ;; TEXTSTYLE|ten|font file|bigfont|chieu cao co dinh|width factor
        (if (setq row (kt:cfg-row "TEXTSTYLE" nm))
          (progn
            (setq sf  (kt:trim (nth 1 row))
                  sbf (kt:trim (nth 2 row)))
            (if (and (/= sf "")
                     (/= (kttxt:fkey sf)
                         (kttxt:fkey (if (= (car act) "") (cond ((nth 2 act)) ("")) (car act)))))
              (setq diffs (cons (strcat "font '" (if (= (car act) "") (cond ((nth 2 act)) ("")) (car act))
                                        "' (chuan '" sf "')")
                                diffs)))
            (if (and (/= sbf "") (/= (kttxt:fkey sbf) (kttxt:fkey (cadr act))))
              (setq diffs (cons (strcat "bigfont '" (cadr act) "' (chuan '" sbf "')") diffs)))
            ;; chieu cao co dinh (cot 4) - chi so khi file chuan co gia tri
            (setq sh (kt:num (nth 3 row)) ah (cond ((kt:dxf 40 tb)) (0.0)))
            (if (and sh (> (abs (- sh ah)) (max 1e-6 (* 0.005 (max sh ah)))))
              (kt:add "TEXT" "TEXT-STYLECAO" "CANHBAO"
                      (strcat "Textstyle '" nm "' co chieu cao co dinh " (kttxt:fmt ah)
                              " (chuan " (kttxt:fmt sh) ")"
                              (if (or (= sh 0) (= ah 0)) "" " - chu/dim dung style nay sai co"))
                      en nil nil))
            (if diffs
              (kt:add "TEXT" "TEXT-FONT" "LOI"
                      (strcat "Textstyle '" nm "' khac chuan: " (kt:join (reverse diffs) "; ")
                              (if en "" " (khong co TEXT/MTEXT ngoai block dung style nay)"))
                      en nil nil))))
        ;; --- file font co ton tai? (bo qua TrueType) ---
        (setq e (kttxt:ext (car act)))
        (if (and (/= (kt:trim (car act)) "")
                 (not (member e '("TTF" "TTC" "OTF")))
                 (not (kttxt:found (car act))))
          (setq miss (cons (car act) miss)))
        (if (and (/= (kt:trim (cadr act)) "") (not (kttxt:found (cadr act))))
          (setq miss (cons (cadr act) miss)))
        (if miss
          (kt:add "TEXT" "TEXT-FONTMAT" "CANHBAO"
                  (strcat "Textstyle '" nm "': khong tim thay file font "
                          (kt:join (reverse miss) ", ") " (chu se bi thay font khac)")
                  en nil nil))))
    (setq tb (tblnext "STYLE")))
)

;;; ---------- Chay ----------
(defun kttxt:prep ()
  (setq *KT:TXSTD* (kt:cfg-keys "TEXTSTYLE"))
  T
)

(defun kttxt:run (/ n)
  (if (kt:cfg-ok)
    (progn
      (kt:begin "TEXT")
      (setq *KT:TXSTD* nil *KT:TXFIRST* nil *KT:TXBAD* nil)
      (princ "\n[TEXT] Dang kiem tra chu...")
      (kttxt:try 'kttxt:prep)
      (kttxt:try 'kttxt:scan)
      (kttxt:try 'kttxt:chk-badstyle)
      (kttxt:try 'kttxt:chk-fonts)
      (setq n (kt:finish "TEXT"))
      (setq *KT:TXFIRST* nil *KT:TXBAD* nil *KT:TXWID* nil)
      n)
    (progn (princ "\n[TEXT] Khong co file chuan - bo qua.") nil))
)

(defun c:KTTEXT () (kttxt:run) (princ))

(princ "\nKT_Text da nap. Lenh: KTTEXT")
(princ)
