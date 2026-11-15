;;; ============================================================
;;; KT_Dialog.lsp  -  Hop thoai tong hop bo KIEM TRA BAN VE (lenh KT / KTDLG)
;;; ------------------------------------------------------------
;;; KT    : mo hop thoai: chon module -> KIEM TRA -> xem bang tong hop + danh sach loi,
;;;         loc theo muc do / module / khong gian, Xem (zoom) / Loi truoc / Loi sau,
;;;         Xuat CSV, Xoa danh dau, Tao chuan (KTMAU), Nap lai chuan, Mo file chuan.
;;; KTDLG : ten khac cua KT.
;;;
;;; - File .dcl SINH TU DONG luc chay (thu muc TEMP / thu muc bo tool / thu muc ban ve)
;;;   nen chi can phat hanh .lsp. lisp/KT_Dialog.dcl chi de tham khao (giong het ban sinh).
;;; - Chi dung tile DCL co ban (dialog row column boxed_* button toggle popup_list
;;;   list_box text errtile) -> chay AutoCAD va VinaCAD. Khong image/slide/tabs/OpenDCL.
;;; - DCL khong cho zoom / chay lenh / hoi dong lenh khi hop thoai dang mo: moi viec do
;;;   lam theo kieu "dong hop thoai (done_dialog ma rieng) -> lam -> mo lai" trong vong
;;;   while quanh new_dialog; lua chon / bo loc / dong dang chon / vi tri giu nguyen.
;;; - load_dialog / new_dialog that bai -> che do dong lenh (KTALL + KTN/KTP).
;;; Can KT_Core.lsp (+ cac module, KT_Menu.lsp tuy chon).
;;; ============================================================

;; (key toggle | ham run | ten module trong *KT:ISSUES* | nhan)
(setq *KT:DLG-MODTAB*
  '(("m_lay" ktlay:run "LAYER" "Layer / mau / linetype   (KTLAYER)")
    ("m_txt" kttxt:run "TEXT"  "Chu / textstyle / font   (KTTEXT)")
    ("m_dim" ktdim:run "DIM"   "Kich thuoc / dimstyle    (KTDIM)")
    ("m_sh"  ktsh:run  "KHUNG" "Khung ten / so hieu / DM (KTKHUNG)")
    ("m_mat" ktmat:run "KHOP"  "Khop ban ve: truc/cao do (KTKHOP)")
    ("m_cl"  ktcl:run  "SACH"  "Lam sach file            (KTSACH)")))

(setq *KT:DLG-MAXROW* 500)                      ; so dong toi da trong list_box
(setq *KT:DLG-SEVS* '("" "LOI" "CANHBAO" "GOIY"))
;; lua chon nguoi dung (giu trong phien CAD)
(if (not *KT:DLG-MODS*)  (setq *KT:DLG-MODS* '("1" "1" "1" "1" "1" "1")))
(if (not *KT:DLG-FSEV*)  (setq *KT:DLG-FSEV* ""))     ; "" = tat ca
(if (not *KT:DLG-FMOD*)  (setq *KT:DLG-FMOD* ""))
(if (not *KT:DLG-FSP*)   (setq *KT:DLG-FSP* ""))
(if (not *KT:DLG-PAUSE*) (setq *KT:DLG-PAUSE* "1"))   ; dung lai sau khi zoom (Enter de quay lai)
;; *KT:DLG-SEL* : chi so (0-based) trong *KT:ISSUES* dang chon
;; *KT:DLG-POS* : vi tri hop thoai (tra ve tu done_dialog)
;; *KT:DLG-MSG* : thong bao hien o errtile khi mo lai

;;; ---------- Tien ich ----------
(defun ktdlg:defined (sym)
  (if (member (type (eval sym)) '(SUBR USUBR EXRXSUBR)) T nil)
)

(defun ktdlg:pad (s n)
  ;; can trai, cat bot cho vua n ky tu (con 1 khoang trang ngan cot)
  (setq s (kt:str s))
  (if (>= (strlen s) n) (setq s (substr s 1 (1- n))))
  (while (< (strlen s) n) (setq s (strcat s " ")))
  s
)

(defun ktdlg:lpad (s n)
  (setq s (kt:str s))
  (while (< (strlen s) n) (setq s (strcat " " s)))
  s
)

(defun ktdlg:short (s n)
  ;; chuoi dai -> "..." + n-3 ky tu cuoi
  (setq s (kt:str s))
  (if (> (strlen s) n) (strcat "..." (substr s (- (strlen s) n -4))) s)
)

(defun ktdlg:cut (s n)
  (setq s (kt:str s))
  (if (> (strlen s) n) (strcat (substr s 1 (- n 3)) "...") s)
)

(defun ktdlg:pos (x lst / i r)
  ;; vi tri 0-based cua x trong lst (thay vl-position)
  (setq i 0)
  (while (and lst (not r))
    (if (equal x (car lst)) (setq r i))
    (setq lst (cdr lst) i (1+ i)))
  r
)

(defun ktdlg:take (lst n / res)
  (while (and lst (> n 0))
    (setq res (cons (car lst) res) lst (cdr lst) n (1- n)))
  (reverse res)
)

(defun ktdlg:values (k / res v)
  ;; cac gia tri khac nhau cua truong k trong *KT:ISSUES* (theo thu tu xuat hien)
  (foreach x *KT:ISSUES*
    (setq v (kt:str (nth k x)))
    (if (not (member v res)) (setq res (cons v res))))
  (reverse res)
)

(defun ktdlg:count (k v / n)
  (setq n 0)
  (foreach x *KT:ISSUES* (if (= (kt:str (nth k x)) v) (setq n (1+ n))))
  n
)

;;; ---------- Noi dung file DCL ----------
(defun ktdlg:dcl-lines ()
  (list
    "// KT_Dialog.dcl - SINH TU DONG boi KT_Dialog.lsp (lenh KT). Khong can phat hanh file nay."
    "// Chi dung tile co ban de chay ca AutoCAD va VinaCAD."
    "kt_main : dialog {"
    (strcat "  label = \"KIEM TRA HO SO BAN VE - KT v" (kt:str *KT:VER*) "\";")
    "  : row {"
    "    : column {"
    "      : boxed_column {"
    "        label = \"Module kiem tra\";"
    "        : toggle { key = \"m_lay\"; label = \"Layer / mau / linetype   (KTLAYER)\"; }"
    "        : toggle { key = \"m_txt\"; label = \"Chu / textstyle / font   (KTTEXT)\"; }"
    "        : toggle { key = \"m_dim\"; label = \"Kich thuoc / dimstyle    (KTDIM)\"; }"
    "        : toggle { key = \"m_sh\";  label = \"Khung ten / so hieu / DM (KTKHUNG)\"; }"
    "        : toggle { key = \"m_mat\"; label = \"Khop ban ve: truc/cao do (KTKHOP)\"; }"
    "        : toggle { key = \"m_cl\";  label = \"Lam sach file            (KTSACH)\"; }"
    "        : row {"
    "          : button { key = \"b_all\";  label = \"Chon tat ca\"; }"
    "          : button { key = \"b_none\"; label = \"Bo chon\"; }"
    "        }"
    "      }"
    "      : button { key = \"b_run\"; label = \"KIEM TRA\"; is_default = true; }"
    "      : boxed_column {"
    "        label = \"Thong tin\";"
    "        : text { key = \"i_cfg\"; width = 46; }"
    "        : text { key = \"i_st\";  width = 46; }"
    "        : text { key = \"i_frm\"; width = 46; }"
    "        : text { key = \"i_res\"; width = 46; }"
    "      }"
    "      : boxed_column {"
    "        label = \"Tong hop (module x muc do)\";"
    "        : list_box { key = \"l_sum\"; height = 11; width = 46; fixed_width_font = true; }"
    "      }"
    "    }"
    "    : column {"
    "      : row {"
    "        : popup_list { key = \"f_sev\"; label = \"Muc do:\"; width = 26; edit_width = 14; }"
    "        : popup_list { key = \"f_mod\"; label = \"Module:\"; width = 26; edit_width = 14; }"
    "        : popup_list { key = \"f_sp\"; label = \"Khong gian:\"; width = 34; edit_width = 18; }"
    "      }"
    "      : list_box {"
    "        key = \"l_res\";"
    "        label = \"Ket qua (double-click hoac Xem de zoom toi loi)\";"
    "        height = 24; width = 104; fixed_width_font = true;"
    "      }"
    "      : text { key = \"t_note\"; width = 104; }"
    "      : row {"
    "        : button { key = \"b_view\"; label = \"Xem\"; }"
    "        : button { key = \"b_prev\"; label = \"<< Loi truoc\"; }"
    "        : button { key = \"b_next\"; label = \"Loi sau >>\"; }"
    "        : button { key = \"b_csv\";  label = \"Xuat CSV\"; }"
    "        : button { key = \"b_clr\";  label = \"Xoa danh dau\"; }"
    "        : toggle { key = \"o_pause\"; label = \"Dung lai sau khi zoom\"; }"
    "      }"
    "    }"
    "  }"
    "  : row {"
    "    : button { key = \"b_mau\";  label = \"Tao chuan tu ban ve mau...\"; }"
    "    : button { key = \"b_cfg\";  label = \"Nap lai chuan\"; }"
    "    : button { key = \"b_open\"; label = \"Mo file chuan\"; }"
    "    : button { key = \"b_help\"; label = \"Tro giup\"; }"
    "    : button { key = \"cancel\"; label = \"Dong\"; is_cancel = true; }"
    "  }"
    "  errtile;"
    "}")
)

(defun ktdlg:tmpname (d)
  (if (and (= (type d) 'STR) (/= d "")) (kt:path d "KT_Dialog_tmp.dcl"))
)

(defun ktdlg:delete (f)
  (if (and f (ktdlg:defined 'vl-file-delete) (findfile f))
    (vl-catch-all-apply 'vl-file-delete (list f)))
)

(defun ktdlg:load (/ cands f fh id r res)
  ;; ghi file DCL va load_dialog; thu lan luot nhieu thu muc (TEMP co the co dau / khong ghi duoc)
  ;; tra ve id (>= 0) hoac nil
  (if (not (ktdlg:defined 'load_dialog))
    (progn (princ "\n[KT] Phan mem CAD nay khong co ham load_dialog (DCL).") nil)
    (progn
      (if (ktdlg:defined 'vl-filename-mktemp)
        (progn
          (setq r (vl-catch-all-apply 'vl-filename-mktemp (list "kt" nil ".dcl")))
          (if (and (= (type r) 'STR) (/= r "")) (setq cands (list r)))))
      (setq cands (append cands
                          (list (ktdlg:tmpname (getenv "TEMP")) (ktdlg:tmpname (getenv "TMP"))
                                (ktdlg:tmpname (kt:dir)) (ktdlg:tmpname (getvar "DWGPREFIX")))))
      (foreach f cands
        (if (and f (not res) (setq fh (open f "w")))
          (progn
            (foreach ln (ktdlg:dcl-lines) (write-line ln fh))
            (close fh)
            (setq r (vl-catch-all-apply 'load_dialog (list f)))
            (if (and (numberp r) (>= r 0))
              (setq res r *KT:DLG-FILE* f)
              (progn
                (princ (strcat "\n[KT] load_dialog that bai voi " f))
                (ktdlg:delete f))))))
      (if (not res) (princ "\n[KT] Khong tao/nap duoc file hop thoai DCL."))
      res))
)

;;; ---------- Thong tin (tinh NGOAI hop thoai: co ssget) ----------
(defun ktdlg:info (/ f ok nf)
  (setq f (kt:cfg-file))
  (if (findfile f) (setq ok (kt:cfg-ok)))
  (if ok (setq nf (length (kt:frames))))
  (setq *KT:DLG-INFO*
    (list (strcat "File chuan: " (ktdlg:short f 34))
          (cond (ok (strcat "Trang thai: DA NAP (" (itoa (length *KT:CFG*)) " muc)"))
                ((findfile f) "Trang thai: FILE RONG/LOI - sua file hoac chay KTMAU")
                (T "CHUA CO CHUAN -> bam 'Tao chuan tu ban ve mau' (KTMAU)"))
          (if ok
            (strcat "Khung ten tim thay: " (itoa nf)
                    (if (= nf 0) "  (kiem tra muc KHUNG trong file chuan)" ""))
            "Khung ten tim thay: - (can file chuan)")
          (if *KT:ISSUES*
            (strcat "Ket qua: " (itoa (length *KT:ISSUES*)) " muc  (LOI "
                    (itoa (ktdlg:count 2 "LOI")) ", CANHBAO " (itoa (ktdlg:count 2 "CANHBAO"))
                    ", GOIY " (itoa (ktdlg:count 2 "GOIY")) ")")
            "Ket qua: chua co (bam KIEM TRA)")))
)

;;; ---------- Dien du lieu vao hop thoai ----------
(defun ktdlg:fill-sum (/ tot row n1 n2 n3)
  (setq tot (list 0 0 0))
  (start_list "l_sum")
  (add_list (strcat (ktdlg:pad "Module" 9) (ktdlg:lpad "LOI" 7) (ktdlg:lpad "CBAO" 7)
                    (ktdlg:lpad "GOIY" 7) (ktdlg:lpad "Cong" 7)))
  (add_list "-------------------------------------")
  (foreach m (ktdlg:values 0)
    (setq n1 0 n2 0 n3 0)
    (foreach x *KT:ISSUES*
      (if (= (nth 0 x) m)
        (cond ((= (nth 2 x) "LOI") (setq n1 (1+ n1)))
              ((= (nth 2 x) "CANHBAO") (setq n2 (1+ n2)))
              (T (setq n3 (1+ n3))))))
    (setq tot (list (+ n1 (nth 0 tot)) (+ n2 (nth 1 tot)) (+ n3 (nth 2 tot))))
    (add_list (strcat (ktdlg:pad m 9) (ktdlg:lpad (itoa n1) 7) (ktdlg:lpad (itoa n2) 7)
                      (ktdlg:lpad (itoa n3) 7) (ktdlg:lpad (itoa (+ n1 n2 n3)) 7))))
  (add_list "-------------------------------------")
  (setq row (strcat (ktdlg:pad "TONG" 9) (ktdlg:lpad (itoa (nth 0 tot)) 7)
                    (ktdlg:lpad (itoa (nth 1 tot)) 7) (ktdlg:lpad (itoa (nth 2 tot)) 7)
                    (ktdlg:lpad (itoa (apply '+ tot)) 7)))
  (add_list row)
  (end_list)
)

(defun ktdlg:fill-popup (key labels values cur / i)
  ;; nap popup_list; tra ve gia tri dang chon (cur neu con trong danh sach, nguoc lai "")
  (start_list key)
  (foreach s labels (add_list s))
  (end_list)
  (setq i (cond ((ktdlg:pos cur values)) (0)))
  (set_tile key (itoa i))
  (nth i values)
)

(defun ktdlg:fill-filters (/ mods sps)
  (setq *KT:DLG-FSEV* (ktdlg:fill-popup "f_sev" '("Tat ca" "LOI" "CANHBAO" "GOIY")
                                        *KT:DLG-SEVS* *KT:DLG-FSEV*))
  (setq mods (ktdlg:values 0) sps (ktdlg:values 7))
  (setq *KT:DLG-LMOD* (cons "" mods)
        *KT:DLG-LSP*  (cons "" sps))
  (setq *KT:DLG-FMOD*
         (ktdlg:fill-popup "f_mod"
           (cons "Tat ca" (mapcar '(lambda (m) (strcat m " (" (itoa (ktdlg:count 0 m)) ")")) mods))
           *KT:DLG-LMOD* *KT:DLG-FMOD*))
  (setq *KT:DLG-FSP*
         (ktdlg:fill-popup "f_sp"
           (cons "Tat ca" (mapcar '(lambda (s) (strcat s " (" (itoa (ktdlg:count 7 s)) ")")) sps))
           *KT:DLG-LSP* *KT:DLG-FSP*))
)

(defun ktdlg:filter (/ i res)
  ;; chi so goc (trong *KT:ISSUES*) cac muc thoa bo loc
  (setq i 0)
  (foreach x *KT:ISSUES*
    (if (and (or (= *KT:DLG-FSEV* "") (= (nth 2 x) *KT:DLG-FSEV*))
             (or (= *KT:DLG-FMOD* "") (= (nth 0 x) *KT:DLG-FMOD*))
             (or (= *KT:DLG-FSP* "") (= (kt:str (nth 7 x)) *KT:DLG-FSP*)))
      (setq res (cons i res)))
    (setq i (1+ i)))
  (reverse res)
)

(defun ktdlg:row (i x)
  (strcat (ktdlg:lpad (itoa (1+ i)) 5) "  " (ktdlg:pad (nth 2 x) 9) (ktdlg:pad (nth 0 x) 7)
          (ktdlg:pad (nth 1 x) 18) (ktdlg:cut (kt:ascii (kt:str (nth 3 x))) 150)
          (if (nth 5 x) "" "  (chung)"))
)

(defun ktdlg:fill-res (/ k)
  ;; *KT:DLG-FILT*: moi muc thoa loc; *KT:DLG-MAP*: muc hien trong list (dong 0 = tieu de)
  (setq *KT:DLG-FILT* (ktdlg:filter)
        *KT:DLG-MAP* (ktdlg:take *KT:DLG-FILT* *KT:DLG-MAXROW*))
  (start_list "l_res")
  (add_list (strcat (ktdlg:pad "  STT" 7) (ktdlg:pad "MUC" 9) (ktdlg:pad "MODULE" 7)
                    (ktdlg:pad "MA" 18) "NOI DUNG"))
  (foreach i *KT:DLG-MAP* (add_list (ktdlg:row i (nth i *KT:ISSUES*))))
  (if (> (length *KT:DLG-FILT*) (length *KT:DLG-MAP*))
    (add_list (strcat "  ... con " (itoa (- (length *KT:DLG-FILT*) (length *KT:DLG-MAP*)))
                      " muc nua khong hien - loc theo muc do/module hoac Xuat CSV de xem du.")))
  (end_list)
  (set_tile "t_note"
    (cond ((null *KT:ISSUES*) "Chua co ket qua. Chon module va bam KIEM TRA.")
          ((null *KT:DLG-FILT*) "Khong co muc nao thoa bo loc.")
          ((> (length *KT:DLG-FILT*) (length *KT:DLG-MAP*))
           (strcat "Hien " (itoa (length *KT:DLG-MAP*)) "/" (itoa (length *KT:DLG-FILT*))
                   " muc dau - loc them theo muc do/module hoac Xuat CSV de xem du."))
          (T (strcat "Hien " (itoa (length *KT:DLG-FILT*)) "/" (itoa (length *KT:ISSUES*))
                     " muc. Chon dong roi bam Xem (hoac double-click)."))))
  (if (and *KT:DLG-SEL* (setq k (ktdlg:pos *KT:DLG-SEL* *KT:DLG-MAP*)))
    (progn (set_tile "l_res" (itoa (1+ k))) (ktdlg:show-sel)))
)

(defun ktdlg:show-sel (/ x)
  (if (and *KT:DLG-SEL* (setq x (nth *KT:DLG-SEL* *KT:ISSUES*)))
    (set_tile "t_note"
      (ktdlg:cut (strcat "#" (itoa (1+ *KT:DLG-SEL*)) " [" (nth 2 x) "] " (nth 0 x) "-" (nth 1 x)
                         ": " (kt:ascii (kt:str (nth 3 x)))
                         (if (nth 5 x) (strcat "  @" (kt:str (nth 7 x))) "  (loi chung, khong co vi tri)"))
                 200)))
)

(defun ktdlg:modes (/ i dis)
  ;; bat/tat tile theo trang thai
  (setq i 0)
  (foreach m *KT:DLG-MODTAB*
    (if (ktdlg:defined (cadr m))
      (progn (set_tile (car m) (nth i *KT:DLG-MODS*)) (mode_tile (car m) 0))
      (progn (set_tile (car m) "0") (mode_tile (car m) 1)))
    (setq i (1+ i)))
  (setq dis (if *KT:ISSUES* 0 1))
  (foreach k '("b_view" "b_prev" "b_next" "b_csv" "b_clr" "f_sev" "f_mod" "f_sp")
    (mode_tile k dis))
  (mode_tile "b_mau" (if (ktdlg:defined 'c:KTMAU) 0 1))
)

;;; ---------- Hanh dong (goi tu action_tile, hop thoai DANG MO) ----------
(defun ktdlg:on-mod (key val / i res)
  (setq i 0)
  (foreach m *KT:DLG-MODTAB*
    (setq res (cons (if (= (car m) key) val (nth i *KT:DLG-MODS*)) res) i (1+ i)))
  (setq *KT:DLG-MODS* (reverse res))
)

(defun ktdlg:set-all (v)
  (foreach m *KT:DLG-MODTAB*
    (if (ktdlg:defined (cadr m))
      (progn (set_tile (car m) v) (ktdlg:on-mod (car m) v))))
)

(defun ktdlg:on-run (/ i ok)
  (setq i 0)
  (foreach m *KT:DLG-MODTAB*
    (if (and (= (nth i *KT:DLG-MODS*) "1") (ktdlg:defined (cadr m))) (setq ok T))
    (setq i (1+ i)))
  (if ok
    (setq *KT:DLG-POS* (done_dialog 2))
    (set_tile "error" "Chua chon module nao (hoac module chua nap)."))
)

(defun ktdlg:on-filter (which v / i)
  (setq i (atoi v))
  (cond ((= which "SEV") (setq *KT:DLG-FSEV* (cond ((nth i *KT:DLG-SEVS*)) (""))))
        ((= which "MOD") (setq *KT:DLG-FMOD* (cond ((nth i *KT:DLG-LMOD*)) (""))))
        (T               (setq *KT:DLG-FSP*  (cond ((nth i *KT:DLG-LSP*)) ("")))))
  (set_tile "error" "")
  (ktdlg:fill-res)
)

(defun ktdlg:on-list (v reason / k)
  (setq k (atoi v))
  (if (and (> k 0) (nth (1- k) *KT:DLG-MAP*))
    (progn
      (setq *KT:DLG-SEL* (nth (1- k) *KT:DLG-MAP*))
      (set_tile "error" "")
      (ktdlg:show-sel)
      (if (= reason 4) (ktdlg:view))))
)

(defun ktdlg:view ()
  (if (and *KT:DLG-SEL* (nth *KT:DLG-SEL* *KT:ISSUES*))
    (progn (setq *KT:DLG-GO* *KT:DLG-SEL*) (setq *KT:DLG-POS* (done_dialog 3)))
    (set_tile "error" "Chon 1 dong trong danh sach truoc."))
)

(defun ktdlg:step (d / filt n p)
  ;; loi truoc (d=-1) / sau (d=1) trong danh sach DA LOC
  (setq filt *KT:DLG-FILT* n (length filt))
  (if (= n 0)
    (set_tile "error" "Khong co muc nao trong danh sach.")
    (progn
      (setq p (ktdlg:pos *KT:DLG-SEL* filt))
      (setq p (cond ((null p) (if (> d 0) 0 (1- n)))
                    (T (rem (+ n p d) n))))
      (setq *KT:DLG-SEL* (nth p filt) *KT:DLG-GO* *KT:DLG-SEL*)
      (setq *KT:DLG-POS* (done_dialog 3))))
)

(defun ktdlg:on-csv (/ f)
  (if (not *KT:ISSUES*)
    (set_tile "error" "Chua co loi nao de xuat.")
    (progn
      (c:KTBC)
      (setq f (kt:report-file))
      (set_tile "error"
        (if (findfile f)
          (strcat "Da xuat CSV: " (ktdlg:short f 80))
          "Da xuat CSV (xem duong dan o dong lenh)."))))
)

(defun ktdlg:on-open (/ f r)
  (setq f (kt:cfg-file))
  (cond
    ((not (findfile f))
     (set_tile "error" "Chua co file chuan. Bam 'Tao chuan tu ban ve mau' (KTMAU) truoc."))
    ((not (ktdlg:defined 'startapp))
     (set_tile "error" (strcat "Mo bang tay: " (ktdlg:short f 90))))
    (T
     (setq r (vl-catch-all-apply 'startapp (list "notepad" (strcat "\"" f "\""))))
     (set_tile "error"
       (if (or (vl-catch-all-error-p r) (null r))
         (strcat "Khong mo duoc Notepad. File: " (ktdlg:short f 80))
         "Da mo file chuan bang Notepad. Sua xong luu lai roi bam 'Nap lai chuan'."))))
)

(defun ktdlg:help ()
  (alert (strcat
    "BO KIEM TRA HO SO BAN VE KT v" (kt:str *KT:VER*) "\n\n"
    "1. Lan dau: mo ban ve MAU cong ty, bam 'Tao chuan tu ban ve mau' (KTMAU)\n"
    "   -> sinh KT_ChuanCongTy.txt. 'Mo file chuan' de ra soat, 'Nap lai chuan' sau khi sua.\n"
    "2. Mo ban ve nhan vien, go KT, chon module, bam KIEM TRA.\n"
    "3. Loc theo Muc do / Module / Khong gian. Double-click hoac 'Xem' de zoom toi loi;\n"
    "   'Loi truoc' / 'Loi sau' di theo danh sach da loc. Hop thoai tu mo lai.\n"
    "   'Dung lai sau khi zoom': CAD cho Enter truoc khi mo lai hop thoai.\n"
    "4. 'Xuat CSV' -> <tenbanve>_KiemTra.csv (mo bang Excel). 'Xoa danh dau' xoa\n"
    "   vong tron tren layer KT_CHECK va danh sach loi.\n\n"
    "Muc do: LOI (do) phai sua / CANHBAO (vang) nen xem / GOIY (xanh) tham khao.\n"
    "Dong lenh: KTALL, KTN/KTP, KTBC, KTX, KTHELP."))
)

(defun ktdlg:init (/ m)
  ;; goi ngay sau new_dialog
  (ktdlg:modes)
  (set_tile "i_cfg" (nth 0 *KT:DLG-INFO*))
  (set_tile "i_st"  (nth 1 *KT:DLG-INFO*))
  (set_tile "i_frm" (nth 2 *KT:DLG-INFO*))
  (set_tile "i_res" (nth 3 *KT:DLG-INFO*))
  (set_tile "o_pause" *KT:DLG-PAUSE*)
  (ktdlg:fill-sum)
  (ktdlg:fill-filters)
  (ktdlg:fill-res)
  (foreach m *KT:DLG-MODTAB* (action_tile (car m) "(ktdlg:on-mod $key $value)"))
  (action_tile "b_all"  "(ktdlg:set-all \"1\")")
  (action_tile "b_none" "(ktdlg:set-all \"0\")")
  (action_tile "b_run"  "(ktdlg:on-run)")
  (action_tile "f_sev"  "(ktdlg:on-filter \"SEV\" $value)")
  (action_tile "f_mod"  "(ktdlg:on-filter \"MOD\" $value)")
  (action_tile "f_sp"   "(ktdlg:on-filter \"SP\" $value)")
  (action_tile "l_res"  "(ktdlg:on-list $value $reason)")
  (action_tile "b_view" "(ktdlg:view)")
  (action_tile "b_prev" "(ktdlg:step -1)")
  (action_tile "b_next" "(ktdlg:step 1)")
  (action_tile "b_csv"  "(ktdlg:on-csv)")
  (action_tile "b_clr"  "(setq *KT:DLG-POS* (done_dialog 5))")
  (action_tile "o_pause" "(setq *KT:DLG-PAUSE* $value)")
  (action_tile "b_mau"  "(setq *KT:DLG-POS* (done_dialog 8))")
  (action_tile "b_cfg"  "(setq *KT:DLG-POS* (done_dialog 7))")
  (action_tile "b_open" "(ktdlg:on-open)")
  (action_tile "b_help" "(ktdlg:help)")
  (action_tile "cancel" "(setq *KT:DLG-POS* (done_dialog 0))")
  (if (and (= (type *KT:DLG-MSG*) 'STR) (/= *KT:DLG-MSG* ""))
    (set_tile "error" (ktdlg:cut *KT:DLG-MSG* 160)))
  (setq *KT:DLG-MSG* nil)
)

;;; ---------- Viec lam khi hop thoai DA DONG ----------
(defun ktdlg:run (/ i sym r nrun failed)
  (if (not (kt:cfg-ok))
    (princ "\n[KT] CANH BAO: chua co file chuan cong ty - cac module bo qua phan so voi chuan."))
  (setq i 0 nrun 0)
  (foreach m *KT:DLG-MODTAB*
    (setq sym (cadr m))
    (if (and (= (nth i *KT:DLG-MODS*) "1") (ktdlg:defined sym))
      (progn
        (princ (strcat "\n\n>>> " (nth 3 m)))
        (setq r (vl-catch-all-apply sym nil))
        (if (vl-catch-all-error-p r)
          (progn
            (if (wcmatch (strcase (vl-catch-all-error-message r)) "*CANCEL*,*QUIT*,*EXIT*")
              (exit))
            (setq failed (cons (nth 2 m) failed))
            (princ (strcat "\n[KT] Module " (nth 2 m) " loi, bo qua: " (vl-catch-all-error-message r))))
          (setq nrun (1+ nrun)))))
    (setq i (1+ i)))
  (if (ktdlg:defined 'ktall:summary) (ktall:summary))
  (setq *KT:DLG-SEL* (if *KT:ISSUES* 0)
        *KT:DLG-MSG* (strcat "Da chay " (itoa nrun) " module - " (itoa (length *KT:ISSUES*)) " muc."
                             (if failed (strcat " Module loi: " (kt:join (reverse failed) ", ")) "")))
)

(defun ktdlg:goto (i / x)
  (if (setq x (nth i *KT:ISSUES*))
    (progn
      (setq *KT:IDX* (1- i))
      (kt:goto 1)
      (setq *KT:DLG-SEL* i
            *KT:DLG-MSG* (strcat "Loi " (itoa (1+ i)) "/" (itoa (length *KT:ISSUES*)) " [" (nth 2 x) "] "
                                 (nth 0 x) "-" (nth 1 x)
                                 (if (nth 5 x) "" " - loi chung cua ban ve, khong co vi tri de zoom")))
      (if (and (nth 5 x) (= *KT:DLG-PAUSE* "1"))
        (getstring "\n[KT] Da zoom toi loi. Nhan Enter de quay lai hop thoai KT...")))
    (setq *KT:DLG-MSG* "Muc nay khong con (danh sach loi da thay doi)."))
)

(defun ktdlg:fallback (/ k)
  (princ "\n[KT] Khong mo duoc hop thoai -> chuyen sang che do DONG LENH.")
  (initget "Co Khong")
  (setq k (getkword "\nChay tat ca kiem tra (KTALL) ngay? [Co/Khong] <Co>: "))
  (if (/= k "Khong")
    (if (ktdlg:defined 'c:KTALL)
      (c:KTALL)
      (princ "\n[KT] Chua nap KT_Menu.lsp (lenh KTALL).")))
  (princ "\nXem ket qua: KTN (loi tiep theo) / KTP (loi truoc), KTBC xuat CSV, KTX xoa danh dau, KTHELP.")
  (princ)
)

(defun ktdlg:main (/ *error* id st loop opened)
  (defun *error* (m)
    (if (and id (ktdlg:defined 'unload_dialog)) (vl-catch-all-apply 'unload_dialog (list id)))
    (ktdlg:delete *KT:DLG-FILE*)
    (if (not (wcmatch (strcase (kt:str m)) "*CANCEL*,*QUIT*,*EXIT*,*BREAK*"))
      (princ (strcat "\n[KT] Loi: " (kt:str m))))
    (princ))
  (cond
    ((not (ktdlg:defined 'kt:cfg-ok))
     (princ "\n[KT] Chua nap KT_Core.lsp. Hay nap KT_Load.lsp truoc."))
    ((not (setq id (ktdlg:load)))
     (ktdlg:fallback))
    (T
     (kt:reset-cache)
     (setq loop T)
     (while loop
       (ktdlg:info)
       (if (not (if *KT:DLG-POS*
                  (new_dialog "kt_main" id "" *KT:DLG-POS*)
                  (new_dialog "kt_main" id)))
         (progn
           (princ "\n[KT] new_dialog that bai (hop thoai kt_main).")
           (setq loop nil st -1))
         (progn
           (setq opened T)
           (ktdlg:init)
           (setq st (start_dialog))
           (cond
             ((= st 2) (ktdlg:run))
             ((= st 3) (ktdlg:goto *KT:DLG-GO*))
             ((= st 5)
              (c:KTX)
              (setq *KT:DLG-SEL* nil *KT:DLG-MSG* "Da xoa danh dau va danh sach loi."))
             ((= st 7)
              (c:KTCFG)
              (setq *KT:DLG-MSG* (if *KT:CFG* "Da nap lai file chuan." "Chua co / khong doc duoc file chuan.")))
             ((= st 8)
              (princ "\n[KT] Tao chuan tu ban ve mau (tra loi cac cau hoi o dong lenh)...")
              (c:KTMAU)
              (setq *KT:CFG* nil)
              (kt:reset-cache)
              (setq *KT:DLG-MSG* "Da chay KTMAU - xem lai thong tin file chuan."))
             (T (setq loop nil))))))
     (vl-catch-all-apply 'unload_dialog (list id))
     (setq id nil)
     (ktdlg:delete *KT:DLG-FILE*)
     (if (and (= st -1) (not opened)) (ktdlg:fallback))))
  (princ)
)

(defun c:KT () (ktdlg:main))
(defun c:KTDLG () (ktdlg:main))

(princ "\nKT_Dialog da nap. Lenh: KT (hop thoai tong hop), KTDLG")
(princ)
