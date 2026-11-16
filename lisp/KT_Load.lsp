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
;;; QUAN TRONG: Startup Suite CHI chua KT_Load.lsp (no tu nap cac file con lai).
;;;  Neu da lo them TAT CA file .lsp vao Startup Suite: APPLOAD > Contents... > Remove
;;;  cac file khac, chi giu KT_Load.lsp.
;;;
;;; Tim thu muc bo KT (KHONG BAO GIO hoi khi nap - Startup Suite se nuot cau hoi):
;;;  *KT:HOME* -> (getenv "KT_HOME") (luu tu lan truoc) -> Support path (findfile)
;;;  -> doan: C:\KT\lisp C:\KT D:\KT\lisp D:\KT, C:\KT_Tool* / D:\KT_Tool* (thu muc moi nhat).
;;;  Tim thay -> setenv KT_HOME + them vao Support path / TRUSTEDPATHS (neu duoc) -> lan sau nap ngay.
;;;  Khong tim thay -> in huong dan: go lenh KTSETUP (chon file KT_Load.lsp 1 lan).
;;; Nap lai nhieu lan an toan (chi in 1 dong tong ket tu lan thu 2).
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

(defun ktload:fnp (sym / v)
  ;; ham co ton tai? (khong so ten kieu: VinaCAD/LMS tra ve ten khac SUBR)
  (setq v (if (= (type sym) 'SYM) (eval sym) sym))
  (if (and v (not (member (type v) '(STR INT REAL ENAME PICKSET FILE)))) T nil)
)

(defun ktload:try (f args / r)
  ;; goi f; nil neu loi / ham khong co
  (if (ktload:fnp f)
    (if (ktload:fnp 'vl-catch-all-apply)
      (progn (setq r (vl-catch-all-apply f args)) (if (not (vl-catch-all-error-p r)) r))
      (apply f args)))
)

(defun ktload:okdir (d)
  (and (= (type d) 'STR) (/= d "") (findfile (strcat d "\\KT_Core.lsp")))
)

(defun ktload:sub (d)
  ;; d hoac d\lisp neu chua bo KT
  (cond ((ktload:okdir d) d)
        ((and d (ktload:okdir (strcat d "\\lisp"))) (strcat d "\\lisp")))
)

(defun ktload:guess (/ d res lst)
  ;; thu muc hay dung + C:\KT_Tool* / D:\KT_Tool* (lay ten sap xep cuoi = phien ban moi nhat)
  (foreach g '("C:\\KT\\lisp" "C:\\KT" "D:\\KT\\lisp" "D:\\KT")
    (if (and (not res) (ktload:okdir g)) (setq res g)))
  (foreach drv '("C:\\" "D:\\")
    (if (not res)
      (progn
        (setq lst (ktload:try 'vl-directory-files (list drv "KT_Tool*" -1)))
        (if (listp lst)
          (foreach f (if (ktload:fnp 'acad_strlsort) (ktload:try 'acad_strlsort (list lst)) lst)
            (if (setq d (ktload:sub (strcat drv f))) (setq res d)))))))
  res
)

(defun ktload:home (/ f d)
  ;; thu muc chua bo KT; KHONG hoi nguoi dung. *KT:HOME-SRC* = nguon tim thay
  (cond
    ((setq d (ktload:sub (ktload:norm *KT:HOME*))) (setq *KT:HOME-SRC* "*KT:HOME*") d)
    ((setq d (ktload:sub (ktload:norm (ktload:try 'getenv (list "KT_HOME")))))
     (setq *KT:HOME-SRC* "KT_HOME") d)
    ((and (setq f (findfile "KT_Load.lsp")) (setq d (ktload:sub (ktload:dirof f))))
     (setq *KT:HOME-SRC* "Support") d)
    ((and (setq f (findfile "KT_Core.lsp")) (setq d (ktload:sub (ktload:dirof f))))
     (setq *KT:HOME-SRC* "Support") d)
    ((setq d (ktload:guess)) (setq *KT:HOME-SRC* "doan") d))
)

(defun ktload:has (lst d / ok)
  (foreach x lst (if (= (strcase (ktload:norm x)) (strcase d)) (setq ok T)))
  ok
)

(defun ktload:remember (d / files sp tp)
  ;; luu thu muc cho lan sau: KT_HOME (registry), Support path, TRUSTEDPATHS. Loi -> bo qua.
  (ktload:try 'setenv (list "KT_HOME" d))
  (setq files (ktload:try '(lambda () (vlax-get-property (vlax-get-property (vlax-get-acad-object) 'Preferences) 'Files)) nil))
  (if files
    (progn
      (setq sp (ktload:try 'vlax-get-property (list files 'SupportPath)))
      (if (and (= (type sp) 'STR) (not (ktload:has (ktload:split sp) d)))
        (ktload:try 'vlax-put-property (list files 'SupportPath (strcat sp (if (= sp "") "" ";") d))))))
  (setq tp (ktload:try 'getvar (list "TRUSTEDPATHS")))
  (if (and (= (type tp) 'STR) (not (ktload:has (ktload:split tp) d)))
    (ktload:try 'setvar (list "TRUSTEDPATHS" (strcat tp (if (= tp "") "" ";") d))))
  d
)

(defun ktload:split (s / p res)
  (while (setq p (vl-string-search ";" s))
    (if (> p 0) (setq res (cons (substr s 1 p) res)))
    (setq s (substr s (+ p 2))))
  (if (/= s "") (setq res (cons s res)))
  (reverse res)
)

(defun ktload:file (path / r)
  ;; nap 1 file; tra ve nil neu thanh cong, chuoi loi neu that bai
  (if (findfile path)
    (if (and vl-catch-all-apply (not (member (type vl-catch-all-apply) '(STR INT REAL ENAME PICKSET FILE))))
      (progn
        (setq r (vl-catch-all-apply 'load (list path)))
        (if (vl-catch-all-error-p r) (vl-catch-all-error-message r)))
      (progn (load path) nil))
    "khong tim thay file")
)

(defun ktload:run (/ d mods extra files err e nOK fn again)
  (setq d (ktload:home) again *KT:LOADED*)
  (if d
    (progn
      (setq *KT:HOME* d nOK 0)
      (ktload:remember d)
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
          (if (and vl-directory-files (not (member (type vl-directory-files) '(STR INT REAL ENAME PICKSET FILE))))
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
          (setq *KT:LOADED* T)
          (princ (strcat "\n[KT] Da nap " (if again "lai " "") (itoa nOK) " file tu " d
                         (if again " (bo KT da nap truoc do - Startup Suite chi can KT_Load.lsp)" "")))
          (if err
            (progn
              (princ (strcat "\n[KT] " (itoa (length err)) " file LOI (bao lai cho nhom phat trien):"))
              (foreach x (reverse err) (princ (strcat "\n   - " x)))))
          (if (not again)
            (princ "\n[KT] Go KT de mo hop thoai tong hop, KTHELP xem danh sach lenh, KTALL kiem tra tat ca.")))))
    (princ "\n[KT] Chua nap bo KT: khong tim thay thu muc chua KT_Core.lsp -> go lenh KTSETUP de chon file KT_Load.lsp (1 lan)."))
  (princ)
)

(if (ktload:fnp 'vl-load-com) (vl-load-com))

(defun c:KTSETUP (/ f d)
  ;; chon thu muc bo KT 1 lan (luu KT_HOME + Support path), roi nap
  (if (ktload:fnp 'getfiled)
    (setq f (ktload:try 'getfiled (list "Chon file KT_Load.lsp cua bo KT" "" "lsp" 0))))
  (if (= (type f) 'STR)
    (setq d (ktload:dirof f))
    (setq d (ktload:norm (getstring T "\nDuong dan thu muc chua KT_Core.lsp (vd C:\\KT\\lisp) <huy>: "))))
  (cond
    ((null d) (princ "\n[KT] Huy KTSETUP."))
    ((not (setq d (ktload:sub d))) (princ "\n[KT] Thu muc nay khong co KT_Core.lsp."))
    (T
     (setq *KT:HOME* d)
     (ktload:remember d)
     (princ (strcat "\n[KT] Da luu thu muc bo KT: " d " (lan sau tu nap)."))
     (ktload:run)))
  (princ)
)

(ktload:run)
(princ)
