import math
def rem(a,b): return math.fmod(a,b)   # AutoLISP rem on reals = truncating remainder
def roundto(x,step):
    q=x/step; f=rem(q,1.0); i=q-f
    if f>=0.5: i+=1
    elif f<=-0.5: i-=1
    return i*step
def numstr(s):
    return any(c.isdigit() for c in s) and all(c in "0123456789.+-" for c in s)
def plain(s):
    i,n,res=0,len(s),""
    while i<n:
        c=s[i]
        if c in "{}": i+=1
        elif c=="\\" and i<n-1:
            d=s[i+1]
            if d in "\\{}": res+=d; i+=2
            elif d in "PX~": res+=" "; i+=2
            elif d in "LlOoKk": i+=2
            elif d in "ACFfHQTWSp":
                p=s.find(";",i); i = p+1 if p>=0 else n
            else: res+=c; i+=1
        else: res+=c; i+=1
    return res.strip()
def ghide(txt,meas,lf,dec,tol=1.0,typ=0):
    # mo phong ktdim:ghide (KT_Dim.lsp)
    if txt in("","<>") or "<>" in txt: return None
    if txt.strip()=="": return "CANHBAO-an"
    pl=plain(txt)
    if pl=="": return "CANHBAO-an"
    s=pl
    if typ in(3,4):
        if s.upper().startswith("%%C"): s=s[3:]
        elif s.upper().startswith("R"): s=s[1:]
    s=s.strip()
    num=None
    if typ in (0,1,3,4,6) and numstr(s):
        try: num=float(s)
        except ValueError: num=None      # distof "1-2" -> nil
    disp=roundto(meas*lf,10.0**-dec) if meas is not None else None
    if num is not None and pl[:1] in "+-": return "CANHBAO-caodo"
    if num is not None and disp is not None and abs(num-disp)<=tol: return None
    if num is not None and disp is not None and (abs(num*1000-disp)<=tol or abs(num*10-disp)<=tol):
        return "CANHBAO-donvi"
    if num is not None and disp is not None:
        return ("LOI","Ghi %s nhung do %.*f"%(pl,dec,disp))
    return "CANHBAO"
def intstep(x): return x>=0.999 and abs(x-roundto(x,1.0))<1e-6
def lex(meas,lf):
    # mo phong ktdim:lex
    return meas if (0<lf<0.999 and intstep(1.0/lf)) else meas*lf
def le(meas,lf,step=1.0,lech=0.05):
    v=lex(meas,lf); d=abs(v-roundto(v,step)); return d>lech, round(d,4)
assert roundto(3249.6,1)==3250 and roundto(3249.4,1)==3249 and roundto(-2.5,1)==-3
assert roundto(1234.5678,0.01)==1234.57 or abs(roundto(1234.5678,0.01)-1234.57)<1e-9
assert roundto(3247.4,5)==3245 and roundto(3247.6,5)==3250
assert roundto(1e12+0.6,1)==1e12+1   # khong tran so nhu fix
assert ghide("3300",3250,1,0)[0]=="LOI"
assert ghide("3250",3249.6,1,0) is None
assert ghide("3251",3249.6,1,0) is None          # trong dung sai 1
assert ghide("3252",3249.6,1,0)[0]=="LOI"
assert ghide("<> mm",3250,1,0) is None
assert ghide("TUONG",3250,1,0)=="CANHBAO"
assert ghide(" ",3250,1,0)=="CANHBAO-an"
assert ghide("\\A1;3300",3250,1,0)[0]=="LOI"
assert ghide("{\\H2.5;3250}",3250,1,0) is None
assert ghide("R500",500,1,0,typ=4) is None and ghide("%%c600",500,1,0,typ=3)[0]=="LOI"
assert ghide("33.00",3300,0.01,2) is None      # DIMLFAC 0.01 (m)
assert le(3249.6,1)==(True,0.4) and le(3250.0000001,1)[0] is False
assert le(3247.0,1,step=5,lech=0.5)==(True,2.0)
# --- Reviewer 2: cac truong hop bao nham ---
assert ghide("+3.600",3600,1,0,typ=6)=="CANHBAO-caodo"     # cao do ghi tay -> khong LOI
assert ghide("+3.600",3450,1,0)=="CANHBAO-caodo"
assert ghide("3.60",3600,1,0)=="CANHBAO-donvi"             # ghi theo m trong ban ve mm
assert ghide("360",3600,1,0)=="CANHBAO-donvi"              # ghi theo cm
assert ghide("3.25",3600,1,0)[0]=="LOI"
assert ghide("1-2",3600,1,0)=="CANHBAO"
assert ghide("{}",3600,1,0)=="CANHBAO-an"
assert ghide("3600",3600,1,0,typ=2)=="CANHBAO"             # dim goc: khong so so
assert le(3600.0,0.001)[0] is False                         # DIMLFAC 0.001 (hien m): xet tren mm goc
assert le(3600.4,0.001)[0] is True
assert le(1100.0,0.2)[0] is False                           # chi tiet ve x5, DIMLFAC 0.2
assert le(22.0,100)[0] is False                             # dim layout do xuyen VP 1/100
assert le(22.0003,100)[0] is False and le(22.002,100)[0] is True
assert lex(1000.0,0.4)==400.0                               # 1/0.4 khong nguyen -> dung gia tri hien
print("OK")
