// KT_Dialog.dcl - BAN THAM KHAO. Ban that SINH TU DONG boi KT_Dialog.lsp (lenh KT). Khong can phat hanh file nay.
// Chi dung tile co ban de chay ca AutoCAD va VinaCAD.
kt_main : dialog {
  label = "KIEM TRA HO SO BAN VE - KT v1.1";
  : row {
    : column {
      : boxed_column {
        label = "Module kiem tra";
        : toggle { key = "m_lay"; label = "Layer / mau / linetype   (KTLAYER)"; }
        : toggle { key = "m_txt"; label = "Chu / textstyle / font   (KTTEXT)"; }
        : toggle { key = "m_dim"; label = "Kich thuoc / dimstyle    (KTDIM)"; }
        : toggle { key = "m_sh";  label = "Khung ten / so hieu / DM (KTKHUNG)"; }
        : toggle { key = "m_mat"; label = "Khop ban ve: truc/cao do (KTKHOP)"; }
        : toggle { key = "m_cl";  label = "Lam sach file            (KTSACH)"; }
        : row {
          : button { key = "b_all";  label = "Chon tat ca"; }
          : button { key = "b_none"; label = "Bo chon"; }
        }
      }
      : boxed_radio_row {
        label = "Pham vi kiem tra";
        : radio_button { key = "sc_all"; label = "Toan ban ve"; }
        : radio_button { key = "sc_win"; label = "Chon vung (cua so)"; }
      }
      : button { key = "b_run"; label = "KIEM TRA"; is_default = true; }
      : boxed_column {
        label = "Thong tin";
        : text { key = "i_cfg"; width = 46; }
        : text { key = "i_st";  width = 46; }
        : text { key = "i_frm"; width = 46; }
        : text { key = "i_res"; width = 46; }
        : text { key = "i_scope"; width = 46; }
      }
      : boxed_column {
        label = "Tong hop (module x muc do)";
        : list_box { key = "l_sum"; height = 11; width = 46; fixed_width_font = true; }
      }
    }
    : column {
      : row {
        : popup_list { key = "f_sev"; label = "Muc do:"; width = 26; edit_width = 14; }
        : popup_list { key = "f_mod"; label = "Module:"; width = 26; edit_width = 14; }
        : popup_list { key = "f_sp"; label = "Khong gian:"; width = 34; edit_width = 18; }
      }
      : list_box {
        key = "l_res";
        label = "Ket qua (double-click hoac Xem de zoom toi loi)";
        height = 24; width = 104; fixed_width_font = true;
      }
      : text { key = "t_note"; width = 104; }
      : row {
        : button { key = "b_view"; label = "Xem"; }
        : button { key = "b_prev"; label = "<< Loi truoc"; }
        : button { key = "b_next"; label = "Loi sau >>"; }
        : button { key = "b_csv";  label = "Xuat CSV"; }
        : button { key = "b_clr";  label = "Xoa danh dau"; }
        : toggle { key = "o_pause"; label = "Dung lai sau khi zoom"; }
      }
    }
  }
  : row {
    : button { key = "b_mau";  label = "Tao chuan tu ban ve mau..."; }
    : button { key = "b_cfg";  label = "Nap lai chuan"; }
    : button { key = "b_open"; label = "Mo file chuan"; }
    : button { key = "b_help"; label = "Tro giup"; }
    : button { key = "cancel"; label = "Dong"; is_cancel = true; }
  }
  errtile;
}
