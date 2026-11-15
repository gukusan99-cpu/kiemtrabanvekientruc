;;; ============================================================
;;; KT_Load.lsp  -  Nap toan bo bo KIEM TRA BAN VE KT
;;; ------------------------------------------------------------
;;; Nap KT_Core.lsp truoc, sau do moi module KT_*.lsp co trong cung thu muc.
;;; Moi file nap trong vl-catch-all-apply: 1 file loi khong lam hong ca bo,
;;; cuoi cung in danh sach file loi.
;;;
;;; CAI DAT (lam 1 lan tren moi may):
;;;  Chep ca thu muc lisp (vd C:\KT\lisp) - duong dan KHONG dau, khong ky tu la.
;;;
;;;  AutoCAD (2018 tro len):
;;;   1. OPTIONS > tab Files > Support File Search Path > Add > Browse -> chon C:\KT\lisp.
;;;   2. (AutoCAD 2014+) cung tab Files > Trusted Locations > Add -> C:\KT\lisp
;;;      (neu khong, moi lan nap se hien canh bao SECURELOAD).
;;;   3. Go APPLOAD > Startup Suite (Contents...) > Add -> chon KT_Load.lsp > Close.
;;;      Tu lan mo CAD sau, bo KT tu nap. Hoac APPLOAD > chon KT_Load.lsp > Load
;;;      de nap ngay.
;;;
;;;  VinaCAD:
;;;   1. Options (OPTIONS / Tuy chon) > Files/Tep > duong dan Support (tim kiem)
;;;      -> them C:\KT\lisp (ten muc co the khac tuy phien ban).
;;;   2. Go APLOAD (hoac APPLOAD) > chon KT_Load.lsp > Load (Nap).
;;;      De tu nap: dung muc Startup Suite / "Nap khi khoi dong" trong hop thoai
;;;      APLOAD neu co; neu khong co, them dong sau vao file lisp khoi dong cua
;;;      VinaCAD (tuong duong acaddoc.lsp):  (load "C:/KT/lisp/KT_Load.lsp")
;;;   3. Chay lenh KTPROBE (neu co) / KTHELP de kiem tra.
;;;
;;; Neu KT_Load.lsp khong nam trong Support path, lenh se hoi duong dan thu muc.
;;; Co the dat truoc: (setq *KT:HOME* "C:/KT/lisp") roi (load "C:/KT/lisp/KT_Load.lsp").
;;; ============================================================

(defun ktload:dirof (path / i c res)
  ;; thu muc cua duong dan file (khong co dau \ cuoi); khong dung vl-filename-*
  (setq i (strlen path) res nil)
  (while (and (> i 0) (not res))
    (setq c (substr path i 1))
    (if (or (= c "\\") (= c "/"))
      (setq res (substr path 1 (1- i))))
    (setq i (1- i)))
  res
)

(defun ktload:norm (d / c)
  ;; bo dau nhay va dau \ / o cuoi
  (if d
    (progn
      (setq d (vl-string-trim " \t\"" d))
      (while (and (> (strlen d) 0)
                  (or (= (setq c (substr d (strlen d) 1)) "\\") (= c "/")))
        (setq d (substr d 1 (1- (strlen d)))))
      (if (/= d "") d)))
)

(defun ktload:okdir (d)
  (and d (findfile (strcat d "\\KT_Core.lsp")))
)

(defun ktload:home (/ f d)
  ;; thu muc chua bo KT
  (cond
    ((and (setq f (findfile "KT_Load.lsp")) (ktload:okdir (setq d (ktload:dirof f)))) d)
    ((and (setq f (findfile "KT_Core.lsp")) (ktload:okdir (setq d (ktload:dirof f)))) d)
    ((ktload:okdir (setq d (ktload:norm *KT:HOME*))) d)
    (T
     (princ "\n[KT] Khong tim thay thu muc bo KT trong Support path.")
     (setq d (ktload:norm (getstring T "\nNhap duong dan thu muc chua KT_Core.lsp (vd C:\\KT\\lisp): ")))
     (if (ktload:okdir d)
       d
       (progn (princ (strcat "\n[KT] Khong co KT_Core.lsp trong: " (if d d ""))) nil))))
)

(defun ktload:file (path / r)
  ;; nap 1 file; tra ve nil neu thanh cong, chuoi loi neu that bai
  (if (findfile path)
    (if (member (type vl-catch-all-apply) '(SUBR EXRXSUBR))
      (progn
        (setq r (vl-catch-all-apply 'load (list path)))
        (if (vl-catch-all-error-p r) (vl-catch-all-error-message r)))
      (progn (load path) nil))
    "khong tim thay file")
)

(defun ktload:run (/ d mods extra files err e nOK fn)
  (setq d (ktload:home))
  (if d
    (progn
      (setq *KT:HOME* d nOK 0)
      ;; 1. Loi bat buoc
      (if (setq e (ktload:file (strcat d "\\KT_Core.lsp")))
        (princ (strcat "\n[KT] LOI nap KT_Core.lsp: " e " -> dung nap."))
        (progn
          (setq nOK 1)
          ;; 2. Module theo thu tu co dinh
          (setq mods '("KT_Layer.lsp" "KT_Text.lsp" "KT_Dim.lsp" "KT_Sheet.lsp"
                       "KT_Match.lsp" "KT_Clean.lsp" "KT_Template.lsp" "KT_Menu.lsp"
                       "KT_Dialog.lsp"))
          ;; 3. Them cac KT_*.lsp khac co trong thu muc (neu ham liet ke file co)
          (if (member (type vl-directory-files) '(SUBR EXRXSUBR))
            (progn
              (setq files (vl-catch-all-apply 'vl-directory-files (list d "KT_*.lsp" 1)))
              (if (and files (not (vl-catch-all-error-p files)))
                (foreach fn files
                  (if (and (not (member (strcase fn) (mapcar 'strcase mods)))
                           (not (member (strcase fn) '("KT_CORE.LSP" "KT_LOAD.LSP"))))
                    (setq extra (cons fn extra)))))))
          (foreach fn (append mods (reverse extra))
            (if (findfile (strcat d "\\" fn))
              (if (setq e (ktload:file (strcat d "\\" fn)))
                (setq err (cons (strcat fn ": " e) err))
                (setq nOK (1+ nOK)))))
          (princ (strcat "\n[KT] Da nap " (itoa nOK) " file tu " d))
          (if err
            (progn
              (princ (strcat "\n[KT] " (itoa (length err)) " file LOI (bao lai cho nhom phat trien):"))
              (foreach x (reverse err) (princ (strcat "\n   - " x)))))
          (princ "\n[KT] Go KT de mo hop thoai tong hop, KTHELP xem danh sach lenh, KTALL kiem tra tat ca."))))
    (princ "\n[KT] Chua nap bo KT."))
  (princ)
)

(ktload:run)
(princ)
