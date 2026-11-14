;;; ============================================================
;;; KT_Menu.lsp  -  Lenh KTALL (chay tat ca kiem tra) va KTHELP
;;; ------------------------------------------------------------
;;; KTALL : goi lan luot ham run cua cac module DA NAP (module chua nap -> bo qua),
;;;         moi ham boc vl-catch-all-apply (1 module loi khong dung ca lenh).
;;;         Moi ham run tu goi kt:begin / kt:finish cua rieng no.
;;;         Cuoi cung in bang tong hop: module x muc do (LOI/CANHBAO/GOIY).
;;; KTHELP: danh sach lenh.
;;; Can KT_Core.lsp.
;;; ============================================================

;; (ham run . mo ta) theo thu tu chay
(setq *KT:RUNS*
  '((ktlay:run "Layer / mau / linetype      (KTLAYER)")
    (kttxt:run "Chu / textstyle / font      (KTTEXT)")
    (ktdim:run "Kich thuoc / dimstyle       (KTDIM)")
    (ktsh:run  "Khung ten / so hieu / DM    (KTKHUNG)")
    (ktmat:run "Khop truc / cao do / KT     (KTKHOP)")
    (ktcl:run  "Ve sinh file                (KTSACH)")))

(defun ktall:defined (sym)
  ;; T neu sym dang la ham (SUBR/USUBR)
  (if (member (type (eval sym)) '(SUBR USUBR EXRXSUBR)) T nil)
)

(defun ktall:pad (s n)
  ;; can trai, them khoang trang cho du n ky tu
  (setq s (kt:str s))
  (while (< (strlen s) n) (setq s (strcat s " ")))
  s
)

(defun ktall:lpad (s n)
  ;; can phai
  (setq s (kt:str s))
  (while (< (strlen s) n) (setq s (strcat " " s)))
  s
)

(defun ktall:summary (/ mods m sev row tbl tot)
  ;; bang module x muc do tu *KT:ISSUES*
  (foreach x *KT:ISSUES*
    (setq m (nth 0 x) sev (nth 2 x)
          row (cond ((assoc m tbl)) (T (list m 0 0 0))))
    (if (not (member m mods)) (setq mods (cons m mods)))
    (setq row (cond ((= sev "LOI")     (list m (1+ (nth 1 row)) (nth 2 row) (nth 3 row)))
                    ((= sev "CANHBAO") (list m (nth 1 row) (1+ (nth 2 row)) (nth 3 row)))
                    (T                 (list m (nth 1 row) (nth 2 row) (1+ (nth 3 row))))))
    (setq tbl (cons row (vl-remove (assoc m tbl) tbl))))
  (setq tot (list "TONG" 0 0 0))
  (princ "\n\n================ KTALL - TONG HOP ================")
  (princ (strcat "\n" (ktall:pad "Module" 14) (ktall:lpad "LOI" 8) (ktall:lpad "CANHBAO" 10)
                 (ktall:lpad "GOIY" 8) (ktall:lpad "Cong" 8)))
  (princ "\n--------------------------------------------------")
  (foreach m (reverse mods)
    (setq row (assoc m tbl)
          tot (list "TONG" (+ (nth 1 tot) (nth 1 row)) (+ (nth 2 tot) (nth 2 row))
                    (+ (nth 3 tot) (nth 3 row))))
    (princ (strcat "\n" (ktall:pad m 14) (ktall:lpad (nth 1 row) 8) (ktall:lpad (nth 2 row) 10)
                   (ktall:lpad (nth 3 row) 8)
                   (ktall:lpad (+ (nth 1 row) (nth 2 row) (nth 3 row)) 8))))
  (princ "\n--------------------------------------------------")
  (princ (strcat "\n" (ktall:pad "TONG" 14) (ktall:lpad (nth 1 tot) 8) (ktall:lpad (nth 2 tot) 10)
                 (ktall:lpad (nth 3 tot) 8)
                 (ktall:lpad (+ (nth 1 tot) (nth 2 tot) (nth 3 tot)) 8)))
  (princ "\n==================================================")
  (if *KT:ISSUES*
    (princ "\nGo KTN / KTP de xem tung loi, KTBC de xuat bao cao CSV, KTX de xoa danh dau.")
    (princ "\nKhong phat hien loi nao."))
  (length *KT:ISSUES*)
)

(defun c:KTALL (/ sym r nRun skipped failed)
  (princ "\n=== KTALL: chay tat ca kiem tra ===")
  (if (not (member (type kt:cfg-ok) '(SUBR USUBR)))
    (princ "\n[KTALL] Chua nap KT_Core.lsp. Hay nap KT_Load.lsp truoc.")
    (progn
      (if (not (kt:cfg-ok))
        (princ "\n[KTALL] CANH BAO: chua co file chuan cong ty - cac module se bo qua phan so voi chuan."))
      (setq nRun 0)
      (foreach it *KT:RUNS*
        (setq sym (car it))
        (if (ktall:defined sym)
          (progn
            (princ (strcat "\n\n>>> " (cadr it)))
            (setq r (vl-catch-all-apply sym nil))
            (if (vl-catch-all-error-p r)
              (progn
                (if (wcmatch (strcase (vl-catch-all-error-message r)) "*CANCEL*,*QUIT*,*EXIT*")
                  (exit))
                (setq failed (cons (strcat (kt:str sym) ": " (vl-catch-all-error-message r)) failed))
                (princ (strcat "\n[KTALL] Module loi, bo qua: " (car failed))))
              (setq nRun (1+ nRun))))
          (setq skipped (cons (kt:str sym) skipped))))
      (if skipped
        (princ (strcat "\n\n[KTALL] Module chua nap (bo qua): " (kt:join (reverse skipped) ", "))))
      (if failed
        (progn
          (princ "\n[KTALL] Module bi loi khi chay:")
          (foreach x (reverse failed) (princ (strcat "\n   - " x)))))
      (princ (strcat "\n[KTALL] Da chay " (itoa nRun) " module."))
      (ktall:summary)))
  (princ)
)

(defun c:KTHELP (/ ok)
  (princ "\n================ BO KIEM TRA BAN VE KT ================")
  (foreach x '((c:KTMAU   "KTMAU   : trich chuan cong ty tu ban ve mau -> KT_ChuanCongTy.txt")
               (c:KTCFG   "KTCFG   : nap lai file chuan cong ty")
               (c:KTALL   "KTALL   : chay tat ca kiem tra + bang tong hop")
               (c:KTLAYER "KTLAYER : kiem tra layer / mau / linetype")
               (c:KTTEXT  "KTTEXT  : kiem tra chu, textstyle, font, chieu cao")
               (c:KTDIM   "KTDIM   : kiem tra kich thuoc, dimstyle, chong lan")
               (c:KTKHUNG "KTKHUNG : kiem tra khung ten, so hieu, danh muc")
               (c:KTKHOP  "KTKHOP  : kiem tra khop truc / cao do giua cac ban ve")
               (c:KTSACH  "KTSACH  : ve sinh file (xref, Z, rac, trung)")
               (c:KTN     "KTN/KTP : zoom toi loi tiep theo / truoc do")
               (c:KTX     "KTX     : xoa danh dau + danh sach loi")
               (c:KTBC    "KTBC    : xuat bao cao CSV")
               (c:KTPROBE "KTPROBE : do kha nang phan mem CAD (chay dau tien tren VinaCAD)")
               (c:KTHELP  "KTHELP  : danh sach lenh"))
    (setq ok (ktall:defined (car x)))
    (princ (strcat "\n  " (cadr x) (if ok "" "   (chua nap)"))))
  (princ "\nMuc do: LOI (do) / CANHBAO (vang) / GOIY (xanh). Danh dau tren layer KT_CHECK.")
  (princ)
)

(princ "\nKT_Menu da nap. Lenh: KTALL, KTHELP")
(princ)
