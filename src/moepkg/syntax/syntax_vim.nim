#[###################### GNU General Public License 3.0 ######################]#
#                                                                              #
#  Copyright (C) 2017─2026 Shuhei Nogawa                                       #
#                                                                              #
#  This program is free software: you can redistribute it and/or modify        #
#  it under the terms of the GNU General Public License as published by        #
#  the Free Software Foundation, either version 3 of the License, or           #
#  (at your option) any later version.                                         #
#                                                                              #
#  This program is distributed in the hope that it will be useful,             #
#  but WITHOUT ANY WARRANTY; without even the implied warranty of              #
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the               #
#  GNU General Public License for more details.                                #
#                                                                              #
#  You should have received a copy of the GNU General Public License           #
#  along with this program.  If not, see <https://www.gnu.org/licenses/>.      #
#                                                                              #
#[############################################################################]#

## Vim script, legacy and Vim9. `"` opens a line comment in command position
## and a string in an expression, and Ex commands share names with builtin
## functions (`map`, `filter`), so the lexer tracks where on the line it is in
## `g.lang.vim.line`.

import std/[algorithm, strutils]
import tokenizer
from lexer/end_lexer import endLine, endLWS

# Vim's `fu[nction]` notation: what precedes `[` is the shortest abbreviation.
# Byte-sorted by full name, which `vimCommand` binary-searches.
const vimCommandSpecs* = [
  "N[ext]", "P[rint]", "X", "ab[breviate]", "abc[lear]", "abo[veleft]", "abs[tract]",
  "al[l]", "am[enu]", "an[oremenu]", "a[ppend]", "arga[dd]", "argded[upe]",
  "argd[elete]", "argdo", "arge[dit]", "argg[lobal]", "argl[ocal]", "ar[gs]",
  "argu[ment]", "as[cii]", "aug[roup]", "aun[menu]", "au[tocmd]", "bN[ext]", "bad[d]",
  "ba[ll]", "balt", "bd[elete]", "be[have]", "bel[owright]", "bf[irst]", "bl[ast]",
  "bm[odified]", "bn[ext]", "bo[tright]", "bp[revious]", "brea[k]", "breaka[dd]",
  "breakd[el]", "breakl[ist]", "br[ewind]", "bro[wse]", "bufd[o]", "b[uffer]",
  "buffers", "bun[load]", "bw[ipeout]", "cN[ext]", "cNf[ile]", "ca[bbrev]",
  "cabc[lear]", "cabo[ve]", "cad[dbuffer]", "cadde[xpr]", "caddf[ile]", "caf[ter]",
  "cal[l]", "cat[ch]", "cbe[fore]", "cbel[ow]", "cbo[ttom]", "cb[uffer]", "cc",
  "ccl[ose]", "cd", "cdo", "ce[nter]", "cex[pr]", "cfd[o]", "cf[ile]", "cfir[st]",
  "cgetb[uffer]", "cgete[xpr]", "cg[etfile]", "c[hange]", "changes", "chd[ir]",
  "che[ckpath]", "checkt[ime]", "chi[story]", "class", "cla[st]", "cle[arjumps]",
  "clip[reset]", "cl[ist]", "clo[se]", "cm[ap]", "cmapc[lear]", "cme[nu]", "cnew[er]",
  "cn[ext]", "cnf[ile]", "cnorea[bbrev]", "cno[remap]", "cnoreme[nu]", "col[der]",
  "colo[rscheme]", "comc[lear]", "com[mand]", "comp[iler]", "conf[irm]", "cons[t]",
  "con[tinue]", "cope[n]", "co[py]", "cpf[ile]", "cp[revious]", "cq[uit]", "cr[ewind]",
  "cs[cope]", "cst[ag]", "cuna[bbrev]", "cu[nmap]", "cunme[nu]", "cw[indow]", "deb[ug]",
  "debugg[reedy]", "def", "defc[ompile]", "defe[r]", "delc[ommand]", "d[elete]",
  "delf[unction]", "delm[arks]", "diffg[et]", "diffo[ff]", "diffp[atch]", "diffpu[t]",
  "diffs[plit]", "difft[his]", "dif[fupdate]", "dig[raphs]", "disa[ssemble]",
  "di[splay]", "dj[ump]", "dli[st]", "doautoa[ll]", "do[autocmd]", "dr[op]",
  "ds[earch]", "dsp[lit]", "ea[rlier]", "ec[ho]", "echoc[onsole]", "echoe[rr]",
  "echoh[l]", "echom[sg]", "echon", "echow[indow]", "e[dit]", "el[se]", "elsei[f]",
  "em[enu]", "endc[lass]", "endd[ef]", "ende[num]", "endfo[r]", "endf[unction]",
  "en[dif]", "endin[terface]", "endt[ry]", "endw[hile]", "ene[w]", "enu[m]", "ev[al]",
  "ex", "exe[cute]", "exi[t]", "exp[ort]", "exu[sage]", "f[ile]", "files", "filet[ype]",
  "filt[er]", "final", "fina[lly]", "fin[d]", "fini[sh]", "fir[st]", "fix[del]",
  "fo[ld]", "foldc[lose]", "folddoc[losed]", "foldd[oopen]", "foldo[pen]", "for",
  "fu[nction]", "g[lobal]", "go[to]", "gr[ep]", "grepa[dd]", "gu[i]", "gv[im]",
  "ha[rdcopy]", "h[elp]", "helpc[lose]", "helpf[ind]", "helpg[rep]", "helpt[ags]",
  "hid[e]", "hi[ghlight]", "his[tory]", "hor[izontal]", "ia[bbrev]", "iabc[lear]", "if",
  "ij[ump]", "il[ist]", "im[ap]", "imapc[lear]", "ime[nu]", "imp[ort]", "inorea[bbrev]",
  "ino[remap]", "inoreme[nu]", "i[nsert]", "inte[rface]", "int[ro]", "ip[ut]",
  "is[earch]", "isp[lit]", "iuna[bbrev]", "iu[nmap]", "iunme[nu]", "j[oin]", "ju[mps]",
  "k", "keepa[lt]", "keepj[umps]", "kee[pmarks]", "keepp[atterns]", "lN[ext]",
  "lNf[ile]", "lab[ove]", "laddb[uffer]", "lad[dexpr]", "laddf[ile]", "laf[ter]",
  "lan[guage]", "la[st]", "lat[er]", "lbe[fore]", "lbel[ow]", "lbo[ttom]", "lb[uffer]",
  "lc[d]", "lch[dir]", "lcl[ose]", "lcs[cope]", "ld[o]", "le[ft]", "lefta[bove]",
  "leg[acy]", "let", "lex[pr]", "lfd[o]", "lf[ile]", "lfir[st]", "lgetb[uffer]",
  "lgete[xpr]", "lg[etfile]", "lgr[ep]", "lgrepa[dd]", "lh[elpgrep]", "lhi[story]",
  "l[ist]", "ll", "lla[st]", "lli[st]", "lmak[e]", "lm[ap]", "lmapc[lear]", "lnew[er]",
  "lne[xt]", "lnf[ile]", "ln[oremap]", "loadk[eymap]", "lo[adview]", "loc[kmarks]",
  "lockv[ar]", "lol[der]", "lop[en]", "lpf[ile]", "lp[revious]", "lr[ewind]", "ls",
  "lt[ag]", "lua", "luad[o]", "luaf[ile]", "lu[nmap]", "lv[imgrep]", "lvimgrepa[dd]",
  "lw[indow]", "mak[e]", "map", "mapc[lear]", "ma[rk]", "marks", "mat[ch]", "me[nu]",
  "menut[ranslate]", "mes[sages]", "mk[exrc]", "mks[ession]", "mksp[ell]", "mkvie[w]",
  "mkv[imrc]", "mod[e]", "m[ove]", "mzf[ile]", "mz[scheme]", "nbc[lose]", "nb[key]",
  "nbs[tart]", "new", "n[ext]", "nm[ap]", "nmapc[lear]", "nme[nu]", "nn[oremap]",
  "nnoreme[nu]", "noa[utocmd]", "noh[lsearch]", "norea[bbrev]", "no[remap]",
  "noreme[nu]", "norm[al]", "nos[wapfile]", "nu[mber]", "nun[map]", "nunme[nu]",
  "ol[dfiles]", "om[ap]", "omapc[lear]", "ome[nu]", "on[ly]", "ono[remap]",
  "onoreme[nu]", "o[pen]", "opt[ions]", "ou[nmap]", "ounme[nu]", "ow[nsyntax]",
  "pa[ckadd]", "packl[oadall]", "pb[uffer]", "pc[lose]", "ped[it]", "pe[rl]",
  "perld[o]", "po[p]", "popu[p]", "pp[op]", "pre[serve]", "prev[ious]", "p[rint]",
  "profd[el]", "prof[ile]", "pro[mptfind]", "promptr[epl]", "ps[earch]", "ptN[ext]",
  "pt[ag]", "ptf[irst]", "ptj[ump]", "ptl[ast]", "ptn[ext]", "ptp[revious]",
  "ptr[ewind]", "pts[elect]", "pub[lic]", "pu[t]", "pw[d]", "py3", "py3d[o]",
  "py3f[ile]", "pyd[o]", "pyf[ile]", "py[thon]", "python3", "pythonx", "pyx", "pyxd[o]",
  "pyxf[ile]", "qa[ll]", "q[uit]", "quita[ll]", "r[ead]", "rec[over]", "redi[r]",
  "red[o]", "redr[aw]", "redraws[tatus]", "redrawt[abline]", "redrawtabp[anel]",
  "reg[isters]", "res[ize]", "ret[ab]", "retu[rn]", "rew[ind]", "ri[ght]",
  "rightb[elow]", "rsh[ada]", "rub[y]", "rubyd[o]", "rubyf[ile]", "rund[o]",
  "ru[ntime]", "rv[iminfo]", "sN[ext]", "sal[l]", "san[dbox]", "sa[rgument]",
  "sav[eas]", "sbN[ext]", "sba[ll]", "sbf[irst]", "sbl[ast]", "sbm[odified]",
  "sbn[ext]", "sbp[revious]", "sbr[ewind]", "sb[uffer]", "scripte[ncoding]",
  "scr[iptnames]", "scriptv[ersion]", "scs[cope]", "se[t]", "setf[iletype]",
  "setg[lobal]", "setl[ocal]", "sf[ind]", "sfir[st]", "sh[ell]", "sig[n]", "sil[ent]",
  "sim[alt]", "sla[st]", "sl[eep]", "sm[agic]", "smap", "smapc[lear]", "sme[nu]",
  "smi[le]", "sn[ext]", "sno[magic]", "snor[emap]", "snoreme[nu]", "sor[t]", "so[urce]",
  "spelld[ump]", "spe[llgood]", "spelli[nfo]", "spellra[re]", "spellr[epall]",
  "spellu[ndo]", "spellw[rong]", "sp[lit]", "spr[evious]", "sre[wind]", "sta[g]",
  "startg[replace]", "star[tinsert]", "startr[eplace]", "stat[ic]", "stj[ump]",
  "st[op]", "stopi[nsert]", "sts[elect]", "s[ubstitute]", "sun[hide]", "sunm[ap]",
  "sunme[nu]", "sus[pend]", "sv[iew]", "sw[apname]", "sync[bind]", "sy[ntax]",
  "synti[me]", "t", "tN[ext]", "tab", "tabN[ext]", "tabc[lose]", "tabd[o]", "tabe[dit]",
  "tabf[ind]", "tabfir[st]", "tabl[ast]", "tabm[ove]", "tabnew", "tabn[ext]",
  "tabo[nly]", "tabp[revious]", "tabr[ewind]", "tabs", "ta[g]", "tags", "tc[d]",
  "tch[dir]", "tcl", "tcld[o]", "tclf[ile]", "te[aroff]", "ter[minal]", "tf[irst]",
  "thi[s]", "th[row]", "tj[ump]", "tl[ast]", "tlm[enu]", "tln[oremenu]", "tlu[nmenu]",
  "tma[p]", "tmapc[lear]", "tm[enu]", "tn[ext]", "tno[remap]", "to[pleft]",
  "tp[revious]", "tr[ewind]", "try", "ts[elect]", "tunma[p]", "tu[nmenu]", "ty[pe]",
  "una[bbreviate]", "u[ndo]", "undoj[oin]", "undol[ist]", "unh[ide]", "uni[q]",
  "unl[et]", "unlo[ckvar]", "unm[ap]", "unme[nu]", "uns[ilent]", "up[date]", "va[r]",
  "verb[ose]", "ve[rsion]", "vert[ical]", "v[global]", "vie[w]", "vim9[cmd]",
  "vim9s[cript]", "vim[grep]", "vimgrepa[dd]", "vi[sual]", "viu[sage]", "vm[ap]",
  "vmapc[lear]", "vme[nu]", "vne[w]", "vn[oremap]", "vnoreme[nu]", "vs[plit]",
  "vu[nmap]", "vunme[nu]", "wN[ext]", "wa[ll]", "wh[ile]", "winc[md]", "wind[o]",
  "winp[os]", "wi[nsize]", "wl[restore]", "wn[ext]", "wp[revious]", "wq", "wqa[ll]",
  "w[rite]", "wsh[ada]", "wu[ndo]", "wv[iminfo]", "xa[ll]", "x[it]", "xm[ap]",
  "xmapc[lear]", "xme[nu]", "xn[oremap]", "xnoreme[nu]", "xr[estore]", "xu[nmap]",
  "xunme[nu]", "y[ank]", "z",
]

func commandNames(): array[vimCommandSpecs.len, string] =
  for i, spec in vimCommandSpecs:
    result[i] = spec.multiReplace(("[", ""), ("]", ""))

func abbrevLens(): array[vimCommandSpecs.len, int] =
  for i, spec in vimCommandSpecs:
    let bracket = spec.find('[')
    result[i] = if bracket < 0: spec.len else: bracket

const
  vimCommands* = commandNames()
  vimCommandMinLens = abbrevLens()

# `isKeyword` binary-searches these, so they must stay byte-sorted. The command
# subsets hold full names, so resolve abbreviations with `vimCommand` first.
const
  vimModifiers* = [
    "aboveleft", "abstract", "belowright", "botright", "browse", "confirm", "debug",
    "export", "hide", "horizontal", "keepalt", "keepjumps", "keepmarks", "keeppatterns",
    "leftabove", "legacy", "lockmarks", "noautocmd", "noswapfile", "public",
    "rightbelow", "sandbox", "silent", "static", "tab", "topleft", "unsilent",
    "verbose", "vertical", "vim9cmd",
  ]

  vimMapCommands* = [
    "abbreviate", "cabbrev", "cmap", "cnoreabbrev", "cnoremap", "cunabbrev", "cunmap",
    "iabbrev", "imap", "inoreabbrev", "inoremap", "iunabbrev", "iunmap", "lmap",
    "lnoremap", "lunmap", "map", "nmap", "nnoremap", "noreabbrev", "noremap", "nunmap",
    "omap", "onoremap", "ounmap", "smap", "snoremap", "sunmap", "tmap", "tnoremap",
    "tunmap", "unabbreviate", "unmap", "vmap", "vnoremap", "vunmap", "xmap", "xnoremap",
    "xunmap",
  ]

  vimExprCommands* = [
    "caddexpr", "call", "cexpr", "cgetexpr", "const", "echo", "echoconsole", "echoerr",
    "echomsg", "echon", "echowindow", "elseif", "eval", "execute", "final", "if",
    "laddexpr", "let", "lexpr", "lgetexpr", "return", "throw", "var", "while",
  ]

  vimScriptCommands* = [
    "lua", "mzscheme", "perl", "py3", "python", "python3", "pythonx", "pyx", "ruby",
    "tcl",
  ]

  # Not commands in Vim9, which reads them as variable names: `vim9-invalid-Ex-commands`
  vim9InvalidCommands* =
    ["Print", "append", "change", "insert", "k", "mode", "open", "t", "xit"]

  vimBuiltins* = [
    "abs", "acos", "add", "and", "append", "appendbufline", "argc", "argv", "asin",
    "atan", "bufadd", "bufexists", "buflisted", "bufload", "bufloaded", "bufname",
    "bufnr", "bufwinid", "bufwinnr", "byte2line", "call", "ceil", "changenr", "char2nr",
    "charidx", "chdir", "cindent", "col", "complete", "copy", "cos", "count", "cursor",
    "deepcopy", "delete", "deletebufline", "did_filetype", "empty", "environ", "escape",
    "eval", "eventhandler", "executable", "execute", "exepath", "exists", "exp",
    "expand", "expandcmd", "extend", "extendnew", "feedkeys", "filereadable",
    "filewritable", "filter", "finddir", "findfile", "flatten", "float2nr", "floor",
    "fmod", "fnameescape", "fnamemodify", "foldclosed", "foldlevel", "foreach",
    "funcref", "function", "garbagecollect", "get", "getbufinfo", "getbufline",
    "getbufvar", "getchar", "getcharpos", "getcmdline", "getcmdpos", "getcmdtype",
    "getcompletion", "getcurpos", "getcwd", "getenv", "getfsize", "getftime",
    "getftype", "getline", "getloclist", "getmarklist", "getpos", "getqflist", "getreg",
    "getregtype", "gettabinfo", "gettabvar", "getwininfo", "getwinvar", "glob",
    "glob2regpat", "globpath", "has", "has_key", "haslocaldir", "hasmapto", "histadd",
    "histdel", "histget", "hlID", "hlexists", "hostname", "iconv", "indent", "index",
    "input", "inputlist", "insert", "invert", "isdirectory", "isinf", "islocked",
    "isnan", "items", "job_start", "job_stop", "jobstart", "jobstop", "join",
    "js_decode", "js_encode", "json_decode", "json_encode", "keys", "keytrans", "len",
    "line", "line2byte", "list2str", "localtime", "log", "log10", "luaeval", "map",
    "maparg", "mapcheck", "mapnew", "mapset", "match", "matchadd", "matchaddpos",
    "matchdelete", "matchend", "matchfuzzy", "matchlist", "matchstr", "matchstrpos",
    "max", "min", "mkdir", "mode", "nr2char", "or", "pathshorten", "popup_close",
    "popup_create", "prevnonblank", "printf", "pumvisible", "py3eval", "pyeval",
    "range", "readdir", "readfile", "reduce", "reg_executing", "reg_recording",
    "reltime", "reltimestr", "remove", "rename", "repeat", "resolve", "reverse",
    "round", "screencol", "screenrow", "search", "searchcount", "searchpair",
    "searchpairpos", "searchpos", "setbufline", "setbufvar", "setcharpos", "setcmdpos",
    "setenv", "setline", "setloclist", "setpos", "setqflist", "setreg", "settabvar",
    "setwinvar", "sha256", "shellescape", "shiftwidth", "simplify", "sin", "slice",
    "sort", "split", "sqrt", "str2float", "str2list", "str2nr", "strcharlen",
    "strcharpart", "strchars", "strdisplaywidth", "strftime", "strgetchar", "stridx",
    "string", "strlen", "strpart", "strptime", "strridx", "strtrans", "strwidth",
    "submatch", "substitute", "synID", "synIDattr", "synIDtrans", "synstack", "system",
    "systemlist", "tabpagebuflist", "tabpagenr", "tabpagewinnr", "tagfiles", "taglist",
    "tan", "tempname", "term_start", "termopen", "timer_start", "timer_stop", "tolower",
    "toupper", "tr", "trim", "trunc", "type", "typename", "undofile", "undotree",
    "uniq", "values", "virtcol", "visualmode", "win_execute", "win_findbuf",
    "win_getid", "win_gotoid", "win_id2win", "wincol", "winheight", "winlayout",
    "winline", "winnr", "winrestcmd", "winrestview", "winsaveview", "winwidth",
    "wordcount", "writefile", "xor",
  ]

  vimBooleans* = [
    "false", "null", "null_blob", "null_channel", "null_class", "null_dict",
    "null_function", "null_job", "null_list", "null_object", "null_partial",
    "null_string", "null_tuple", "true", "v:false", "v:none", "v:null", "v:true",
  ]

  vimSpecialVars* = ["super", "this"]

  # No Vim9 continuation line starts with these: a bracket left open above one
  # was never closed.
  vim9Statements* = [
    "abstract", "catch", "class", "const", "def", "else", "elseif", "endclass",
    "enddef", "endenum", "endfor", "endfunction", "endif", "endinterface", "endtry",
    "endwhile", "enum", "export", "final", "finally", "for", "function", "if", "import",
    "interface", "public", "return", "static", "try", "var", "while",
  ]

  vimTypes* = [
    "any", "blob", "bool", "channel", "dict", "float", "func", "job", "list", "number",
    "object", "string", "tuple", "void",
  ]

  # Lowercase. The keys Vim or Neovim translates in `"\<Name>"`, and the map
  # arguments and placeholders: `<silent>`, `<q-args>`, `<sfile>`
  vimKeyNames* = [
    "abuf", "afile", "amatch", "args", "backspace", "bang", "bar", "bs", "bslash",
    "buffer", "cexpr", "cfile", "client", "cmd", "count", "cr", "csi", "cursorhold",
    "cword", "decmouse", "del", "delete", "down", "drop", "end", "enter", "esc", "expr",
    "f-args", "find", "focusgained", "focuslost", "help", "home", "ignore", "ins",
    "insert", "k0", "k1", "k2", "k3", "k4", "k5", "k6", "k7", "k8", "k9", "kcomma",
    "kdel", "kdivide", "kdown", "kend", "kenter", "kequal", "khome", "kinsert", "kleft",
    "kminus", "kmultiply", "korigin", "kpagedown", "kpageup", "kplus", "kpoint",
    "kright", "kup", "leader", "left", "leftdrag", "leftmouse", "leftmousenm",
    "leftrelease", "leftreleasenm", "lf", "line1", "line2", "linefeed", "localleader",
    "lt", "middledrag", "middlemouse", "middlerelease", "mods", "mouse", "mousedown",
    "mousemove", "mouseup", "netmouse", "newline", "nl", "nop", "nowait", "nul", "osc",
    "pagedown", "pageup", "pasteend", "pastestart", "plug", "q-args", "q-mods", "range",
    "reg", "register", "return", "right", "rightdrag", "rightmouse", "rightrelease",
    "script", "scriptcmd", "scrollwheeldown", "scrollwheelleft", "scrollwheelright",
    "scrollwheelup", "select", "sfile", "sflnum", "sgrmouse", "sgrmouserelease", "sid",
    "silent", "slnum", "snr", "space", "special", "stack", "tab", "undo", "unique",
    "up", "urxvtmouse", "x1drag", "x1mouse", "x1release", "x2drag", "x2mouse",
    "x2release", "xcsi", "xdown", "xend", "xf1", "xf2", "xf3", "xf4", "xhome", "xleft",
    "xosc", "xright", "xup", "zend", "zhome",
  ]

  # Lowercase: event names ignore case. Vim's and Neovim's.
  vimAutocmdEvents* = [
    "bufadd", "bufcreate", "bufdelete", "bufenter", "buffilepost", "buffilepre",
    "bufhidden", "bufleave", "bufmodifiedset", "bufnew", "bufnewfile", "bufread",
    "bufreadcmd", "bufreadpost", "bufreadpre", "bufunload", "bufwinenter",
    "bufwinleave", "bufwipeout", "bufwrite", "bufwritecmd", "bufwritepost",
    "bufwritepre", "chaninfo", "chanopen", "cmdlinechanged", "cmdlineenter",
    "cmdlineleave", "cmdlineleavepre", "cmdundefined", "cmdwinenter", "cmdwinleave",
    "colorscheme", "colorschemepre", "completechanged", "completedone",
    "completedonepre", "cursorhold", "cursorholdi", "cursormoved", "cursormovedc",
    "cursormovedi", "diagnosticchanged", "diffupdated", "dirchanged", "dirchangedpre",
    "encodingchanged", "exitpre", "fileappendcmd", "fileappendpost", "fileappendpre",
    "filechangedro", "filechangedshell", "filechangedshellpost", "fileencoding",
    "filereadcmd", "filereadpost", "filereadpre", "filetype", "filewritecmd",
    "filewritepost", "filewritepre", "filterreadpost", "filterreadpre",
    "filterwritepost", "filterwritepre", "focusgained", "focuslost", "funcundefined",
    "guienter", "guifailed", "insertchange", "insertcharpre", "insertenter",
    "insertleave", "insertleavepre", "keyinputpre", "lspattach", "lspdetach",
    "lspnotify", "lspprogress", "lsprequest", "lsptokenupdate", "markset", "menupopup",
    "modechanged", "optionset", "packchanged", "packchangedpre", "progress",
    "quickfixcmdpost", "quickfixcmdpre", "quitpre", "recordingenter", "recordingleave",
    "remotereply", "safestate", "safestateagain", "searchwrapped", "sessionloadpost",
    "sessionloadpre", "sessionwritepost", "shellcmdpost", "shellfilterpost", "signal",
    "sigusr1", "sourcecmd", "sourcepost", "sourcepre", "spellfilemissing",
    "stdinreadpost", "stdinreadpre", "swapexists", "syntax", "tabclosed",
    "tabclosedpre", "tabenter", "tableave", "tabnew", "tabnewentered", "termchanged",
    "termclose", "termenter", "terminalopen", "terminalwinopen", "termleave",
    "termopen", "termrequest", "termresponse", "termresponseall", "textchanged",
    "textchangedi", "textchangedp", "textchangedt", "textputpost", "textputpre",
    "textyankpost", "uienter", "uileave", "user", "vimenter", "vimleave", "vimleavepre",
    "vimresized", "vimresume", "vimsuspend", "winclosed", "winenter", "winleave",
    "winnew", "winnewpre", "winresized", "winscrolled",
  ]

  letters = {'a' .. 'z', 'A' .. 'Z'}
  hexChars = {'0' .. '9', 'A' .. 'F', 'a' .. 'f'}
  scopeChars = {'a', 'b', 'g', 'l', 's', 't', 'v', 'w'}
  registerChars =
    {'a' .. 'z', 'A' .. 'Z', '0' .. '9'} +
    {'"', '-', '*', '+', ':', '.', '%', '#', '=', '/', '_', '@'}
  # What follows the `:` that opens a command line in keys: a command or a range.
  cmdlineStartChars = letters + Digits + {'%', '\'', '!', '.', '$', '+', '-', ',', ';'}
  # `|`, `&`, `$`, `@`, `:` and `\` have branches of their own.
  vimOpChars = {'+', '-', '*', '/', '<', '>', '!', '?', '^', '.', '=', '%', '~'}
  # `:s` and `:g` take any single-byte delimiter but these.
  patternDelims = {'!' .. '~'} - {'0' .. '9', 'A' .. 'Z', 'a' .. 'z', '\\', '"', '|'}
  # They take no bang, so a `!` is their delimiter: `s!a!b!`
  substituteCommands = ["smagic", "snomagic", "substitute"]

func has(words: openArray[string], word: string): bool =
  isKeyword(words, word) >= 0

func vimCommand*(word: string): string =
  ## Full name of the Ex command `word` spells or abbreviates, or "".
  ## A full name wins over a command it abbreviates: `final`, `fina[lly]`.
  var i = vimCommands.lowerBound(word)
  while i < vimCommands.len and vimCommands[i].startsWith(word):
    if vimCommands[i].len == word.len or word.len >= vimCommandMinLens[i]:
      return vimCommands[i]
    inc(i)

func vim9Scope(g: GeneralTokenizer): bool =
  ## The innermost function body, or the file, is Vim9 script.
  if g.lang.vim.bodies.len > 0:
    g.lang.vim.bodies[^1] == 'd'
  else:
    g.lang.vim.vim9

func vim9Mode(g: GeneralTokenizer): bool =
  vlfLegacy notin g.lang.vim.line and g.vim9Scope

func inMapCmdline(g: GeneralTokenizer): bool =
  ## A map's rhs past `:` or `<Cmd>`, where `\|` and `<Bar>` separate commands.
  vlfMap in g.lang.vim.line and g.lang.vim.line * {vlfKeys, vlfForeign} == {}

func typed(g: GeneralTokenizer): bool =
  ## Keys, or a command line typed in them. They run later, so they open no
  ## heredoc, body or multi-line bracket.
  g.lang.vim.line * {vlfKeys, vlfMap, vlfTyped} != {}

const commandScope = {vlfMap, vlfLegacy, vlfTyped}
  ## What a command takes on from the command line it is on or wrapped in.

proc enterTypedCmdline(g: var GeneralTokenizer, legacy: bool) =
  ## Past `:` or `<Cmd>` in keys. A map's command line is typed, so `legacy`
  ## script even in a Vim9 file; `<ScriptCmd>` runs in the script's syntax.
  g.lang.vim.line = g.lang.vim.line * {vlfMap} + {vlfTyped}
  if legacy and vlfMap in g.lang.vim.line:
    g.lang.vim.line.incl vlfLegacy

proc text(g: GeneralTokenizer, first, last: int): string =
  result = newString(last - first)
  for i in 0 ..< result.len:
    result[i] = g.buf[first + i]

proc atLineStart(g: GeneralTokenizer, pos: int): bool =
  ## Only blanks precede `pos` on its line. Markdown lexes the newlines of a
  ## fenced block itself, so this is how the per-line state learns of a new line.
  var i = pos - 1
  while i >= 0 and g.buf[i] in lwsChars:
    dec(i)
  i < 0 or g.buf[i] == '\n'

func charKey(name: string): bool =
  ## `<Char-65>`, `<Char-0x41>`, `<Char-0101>`, `<Char-0b1000001>`
  if not name.startsWith("char-") or name.len == 5:
    return false
  let n = name[5 ..^ 1]
  if n.len > 2 and n[0] == '0' and n[1] in {'x', 'b'}:
    n[2 ..^ 1].allCharsInSet(
      if n[1] == 'x':
        hexChars
      else:
        {'0', '1'}
    )
  else:
    n.allCharsInSet(Digits)

proc keyNotationEnd(g: GeneralTokenizer, pos: int): int =
  ## End of the `<...>` key at `pos` (`<CR>`, `<C-w>`, `<SID>`), or -1.
  # `2` to `4` count clicks: `<2-LeftMouse>`
  const modifierChars =
    {'2' .. '4', 'A', 'C', 'D', 'M', 'S', 'T', 'a', 'c', 'd', 'm', 's', 't'}
  var p = pos + 1
  var modified = false
  while g.buf[p] in modifierChars and g.peek(p) == '-' and
      g.peek(p, 2) notin wsChars + {'\0'}:
    inc(p, 2)
    modified = true
  let nameStart = p
  var nameEnd = p
  while g.buf[nameEnd] in {'a' .. 'z', 'A' .. 'Z', '0' .. '9', '-'}:
    inc(nameEnd)
  let name = g.text(nameStart, nameEnd).toLowerAscii
  if g.buf[nameEnd] == '>' and name.charKey:
    return nameEnd + 1
  if modified:
    if g.buf[p] in symChars:
      while g.buf[p] in symChars:
        inc(p)
    elif g.buf[p] != '>':
      inc(p)
  else:
    p = nameEnd
    if g.buf[p] != '>':
      return -1
    let functionKey =
      name.len in 2 .. 3 and name[0] == 'f' and name[1 ..^ 1].allCharsInSet(Digits)
    if not functionKey and not vimKeyNames.has(name):
      return -1
  if g.buf[p] == '>':
    p + 1
  else:
    -1

proc afterKeyNotation(g: GeneralTokenizer, pos: int): bool =
  ## A `<...>` key ends right before `pos`. Not a mark: `'<,'>`
  if pos == 0 or g.buf[pos - 1] != '>':
    return false
  var p = pos - 2
  while p >= 0 and g.buf[p] notin wsChars + {'<'}:
    dec(p)
  p >= 0 and g.buf[p] == '<' and g.keyNotationEnd(p) == pos

proc spacedAssignment(g: GeneralTokenizer, pos: int, command: bool): bool =
  ## An assignment operator at `pos` with an operand after it: `= 1`, `..= x`,
  ## `=<< END`. Not `/=` alone, which is an argument: `Tabularize /=`. After a
  ## `command` name, the operand must be on the line: `wincmd = # c` is `:wincmd`
  var p = pos
  if g.buf[p] == '.' and g.peek(p) == '.':
    inc(p, 2)
  elif g.buf[p] in {'+', '-', '*', '/', '%', '.'}:
    inc(p)
  if g.buf[p] != '=':
    false
  elif p == pos and g.peek(p) == '<' and g.peek(p, 2) == '<':
    true
  else:
    let operand = g.buf[g.endLWS(p + 1)]
    g.peek(p) in lwsChars and operand notin eolChars and
      not (command and operand in {'#', '|'})

proc startsExpression(g: GeneralTokenizer, word, command: string, pos: int): bool =
  ## Whether the Vim9 statement `word`, ending at `pos`, is an expression:
  ## `d[k] = 1`, `F()`, `x->F()`, `s = 'x'`. A call even if `word` names a
  ## command, as Vim reads `if(1)`, but not a map command, which may map `=`:
  ## `nnoremap = <C-w>=`
  if word.len > 2 and word[1] == ':':
    return true
  case g.buf[pos]
  of '(':
    true
  of '[', '.':
    not vimMapCommands.has(command)
  of '-':
    g.peek(pos) == '>'
  of ' ', '\t':
    not vimMapCommands.has(command) and
      g.spacedAssignment(g.endLWS(pos), command.len > 0)
  else:
    false

proc heredocSpec(
    g: GeneralTokenizer, pos: int, script: bool
): tuple[marker: string, trim: bool] =
  ## Options and end marker after `=<<`, or `<<` for a `script` command, up to
  ## a comment. The marker is empty when the rest of the line is not a header.
  let commentChar = if g.vim9Mode: '#' else: '"'
  var p = pos
  while true:
    p = g.endLWS(p)
    if g.buf[p] in eolChars or g.buf[p] == commentChar:
      break
    let wordStart = p
    while g.buf[p] notin eolChars + lwsChars:
      inc(p)
    if result.marker.len > 0:
      return ("", false)
    let word = g.text(wordStart, p)
    if word == "trim":
      result.trim = true
    elif word != "eval":
      if not script and word[0] in {'a' .. 'z'}:
        return ("", false) # E221
      result.marker = word
  if result.marker.len == 0 and script:
    result.marker = "."

proc lineIndent(g: GeneralTokenizer, pos: int): string =
  var lineStart = pos
  while lineStart > 0 and g.buf[lineStart - 1] != '\n':
    dec(lineStart)
  g.text(lineStart, g.endLWS(lineStart))

proc heredocBody(g: var GeneralTokenizer, position: int): int =
  result = position
  case g.buf[result]
  of '\n', '\r':
    g.kind = gtWhitespace
    inc(result)
  of ' ', '\t':
    g.kind = gtWhitespace
    result = g.endLWS(result)
  else:
    let
      lineEnd = g.endLine(result)
      marker = g.lang.vim.heredocMarker
      # Vim compares the indent byte for byte, so a tab is not two spaces.
      ends =
        lineEnd - result == marker.len and g.text(result, lineEnd) == marker and
        g.lineIndent(result) in ["", g.lang.vim.cmdlineIndent]
    if ends:
      g.kind = gtKeyword
      g.state = gtNone
      g.lang.vim.heredocMarker = ""
      g.lang.vim.cmdlineIndent = ""
    else:
      g.kind = gtLongStringLit
    result = lineEnd

proc stringEscape(g: GeneralTokenizer, position: int): int =
  ## Escape at the backslash `position` in a `"` string.
  result = position + 1
  template digits(chars: set[char], limit: int) =
    var n = 0
    while n < limit and g.buf[result] in chars:
      inc(result)
      inc(n)

  case g.buf[result]
  of '\0', '\r', '\n':
    discard
  of 'x', 'X':
    inc(result)
    digits(hexChars, 2)
  of 'u':
    inc(result)
    digits(hexChars, 4)
  of 'U':
    inc(result)
    digits(hexChars, 8)
  of '0' .. '7':
    digits({'0' .. '7'}, 3)
  of '<':
    # `\<C-W>`, `\<lt>`
    var p = result + 1
    while g.buf[p] notin {'>', '"', '\\', ' ', '\t', '\0', '\r', '\n'}:
      inc(p)
    result =
      if g.buf[p] == '>' and p > result + 1:
        p + 1
      else:
        result + 1
  else:
    inc(result)

proc singleQuoted(g: GeneralTokenizer, position: int): int =
  ## A `'` string from its opening quote; `''` is an escaped quote.
  result = position + 1
  while true:
    case g.buf[result]
    of '\0', '\r', '\n':
      break
    of '\'':
      inc(result)
      if g.buf[result] != '\'':
        break
      inc(result)
    else:
      inc(result)

proc interpolatedBody(g: var GeneralTokenizer, position: int, quote: char): int =
  ## A `$"` or `$'` string from past its opening quote, whose `{expr}` parts
  ## may hold strings with the quote: `$"a {x ?? "b"}"`. `{{` and `}}` are
  ## literal braces. Parks on an escape outside `{expr}` like `scanStringBody`.
  result = position
  g.lang.vim.line.excl vlfInterpolated
  var depth = 0
  while g.buf[result] notin eolChars:
    let c = g.buf[result]
    if depth > 0:
      case c
      of '{':
        inc(depth)
      of '}':
        dec(depth)
      of '"':
        inc(result)
        while g.buf[result] notin eolChars + {'"'}:
          if g.buf[result] == '\\':
            inc(result)
            g.skipEscapedChar(result)
          else:
            inc(result)
        if g.buf[result] == '"':
          inc(result)
        continue
      of '\'':
        result = g.singleQuoted(result)
        continue
      else:
        discard
      inc(result)
    elif c == quote:
      inc(result)
      if quote == '"' or g.buf[result] != '\'':
        break
      inc(result)
    elif c == '\\' and quote == '"':
      g.state = gtStringLit
      g.lang.vim.line.incl vlfInterpolated
      break
    elif c in {'{', '}'} and g.peek(result) == c:
      inc(result, 2)
    else:
      if c == '{':
        inc(depth)
      inc(result)

proc collectionEnd(g: GeneralTokenizer, position: int): int =
  ## Vim's `skip_anyof`: from past a `[`, the `]` that closes the collection,
  ## or the line's end.
  result = position
  if g.buf[result] == '^':
    inc(result)
  if g.buf[result] in {']', '-'}:
    inc(result)
  while g.buf[result] notin eolChars + {']'}:
    case g.buf[result]
    of '-':
      inc(result)
      if g.buf[result] notin eolChars + {']'}:
        inc(result)
    of '\\':
      const escapes =
        {']', '^', '-', '\\', 'n', 'r', 't', 'e', 'b', 'd', 'o', 'x', 'u', 'U'}
      inc(result, if g.peek(result) in escapes: 2 else: 1)
    of '[':
      # `[:alpha:]`, `[=a=]`, `[.a.]`
      let kind = g.peek(result)
      var p = result + 2
      if kind == ':':
        while g.buf[p] in letters:
          inc(p)
      elif kind in {'=', '.'} and g.buf[p] notin eolChars:
        inc(p)
        while g.buf[p] in {'\x80' .. '\xBF'}:
          inc(p)
      let closes =
        kind in {':', '=', '.'} and p > result + 2 and g.buf[p] == kind and
        g.peek(p) == ']'
      result =
        if closes:
          p + 2
        else:
          result + 1
    else:
      inc(result)

proc scanPattern(g: GeneralTokenizer, position: int, fields: int): int =
  ## `fields` delimited fields from the delimiter at `position`: `/pat/` is
  ## one, `/pat/rep/` two. As in Vim's `skip_regexp`, a collection in the
  ## pattern may hold the delimiter: `s/[/]/-/`
  let delim = g.buf[position]
  result = position + 1
  var
    closed = 0
    veryNomagic = false
  while g.buf[result] notin eolChars:
    let c = g.buf[result]
    if c == delim:
      inc(result)
      inc(closed)
      if closed == fields:
        break
    elif closed == 0 and (
      (c == '[' and not veryNomagic) or
      (c == '\\' and g.peek(result) == '[' and veryNomagic)
    ):
      result = g.collectionEnd(result + (if c == '[': 1 else: 2))
      if g.buf[result] == ']':
        inc(result)
    elif c == '\\':
      inc(result)
      if closed == 0 and g.buf[result] in {'v', 'V'}:
        veryNomagic = g.buf[result] == 'V'
      g.skipEscapedChar(result)
    else:
      inc(result)

proc vimNumber(g: var GeneralTokenizer, position: int): int =
  ## Not `scanRadixNumber`'s rules: Vim reads `019` as decimal, and `1.` and
  ## `1e5` are not floats.
  const decChars = {'0' .. '9'}
  # Vim9 separates digits with `'`: 1'000'000, 0xff'ff. In keys, `'` jumps to
  # a mark.
  let quoteSeparates = g.vim9Mode and vlfKeys notin g.lang.vim.line
  template digits(chars: set[char]) =
    while g.buf[result] in chars or
        (quoteSeparates and g.buf[result] == '\'' and g.peek(result) in chars):
      inc(result)

  result = position
  if g.buf[result] == '0' and g.peek(result) in {'z', 'Z'} and
      g.peek(result, 2) in hexChars:
    # A blob: `0zFF00.ED01`. A `.` only separates bytes: `0zFF.` ends at `F`
    g.kind = gtHexNumber
    inc(result, 2)
    while g.buf[result] in hexChars:
      inc(result)
      if g.buf[result] == '.' and g.peek(result) in hexChars:
        inc(result)
    return
  if g.buf[result] == '0':
    let (kind, chars) =
      case g.peek(result)
      of 'x', 'X':
        (gtHexNumber, hexChars)
      of 'b', 'B':
        (gtBinNumber, {'0', '1'})
      of 'o', 'O':
        (gtOctNumber, {'0' .. '7'})
      else:
        (gtNone, {})
    if kind != gtNone and g.peek(result, 2) in chars:
      g.kind = kind
      inc(result, 2)
      digits(chars)
      return

  g.kind = gtDecNumber
  digits(decChars)
  # Legacy `017` is octal, but not in a range or a count: `:010`, `normal! 017j`
  if not g.vim9Mode and g.lang.vim.line * {vlfMidCommand, vlfKeys} == {vlfMidCommand} and
      g.buf[position] == '0' and result - position > 1 and
      g.text(position + 1, result).allCharsInSet({'0' .. '7'}):
    g.kind = gtOctNumber
  if g.buf[result] == '.' and g.peek(result) in decChars:
    g.kind = gtFloatNumber
    inc(result)
    while g.buf[result] in decChars:
      inc(result)
    if g.buf[result] in {'e', 'E'}:
      var p = result + 1
      if g.buf[p] in {'+', '-'}:
        inc(p)
      if g.buf[p] in decChars:
        result = p
        while g.buf[result] in decChars:
          inc(result)

template operand(g: var GeneralTokenizer, isValue: bool) =
  ## A token past the command name; `isValue` when it ends an operand.
  g.lang.vim.line.incl vlfMidCommand
  if isValue:
    g.lang.vim.line.incl vlfAfterValue
  else:
    g.lang.vim.line.excl vlfAfterValue

proc definesFunction(g: GeneralTokenizer, pos: int, spacedParen: bool): bool =
  ## A `:def` name with its parameters, which open a body. `:def F` lists F.
  ## `spacedParen` allows blanks before `(`: `function F (x)`
  var p = g.endLWS(pos)
  if g.buf[p] == '<':
    p = max(p, g.keyNotationEnd(p)) # <SID>
  let nameStart = p
  while g.buf[p] in symChars + {':', '#', '.'}:
    inc(p)
  if p > nameStart and g.buf[p] == '<':
    # A generic function: `def F<T>(`
    while g.buf[p] notin eolChars + {'>'}:
      inc(p)
    if g.buf[p] == '>':
      inc(p)
  let paren =
    if spacedParen:
      g.endLWS(p)
    else:
      p
  p > nameStart and g.buf[paren] == '('

proc closeBody(g: var GeneralTokenizer, kind: char) =
  ## Also closes the bodies opened inside it that lack their end.
  let i = g.lang.vim.bodies.rfind(kind)
  if i >= 0:
    g.lang.vim.bodies.setLen(i)

proc scopeCommand(g: var GeneralTokenizer, command: string, pos: int) =
  ## What `command` changes past its line: bodies, interfaces, `:vim9script`.
  if g.typed:
    return
  case command
  of "function":
    # Vim9 rejects a blank before `(` with E1068, as for `:def`.
    if g.definesFunction(pos, spacedParen = not g.vim9Mode):
      g.lang.vim.bodies.add 'f'
  of "endfunction":
    g.closeBody('f')
  of "def":
    if not g.lang.vim.inInterface and vlfAbstract notin g.lang.vim.line and
        g.definesFunction(pos, spacedParen = false):
      g.lang.vim.bodies.add 'd'
  of "enddef":
    g.closeBody('d')
    g.lang.vim.brackets = ""
  of "vim9script":
    g.lang.vim.vim9 = true
  of "interface":
    g.lang.vim.inInterface = true
  of "endinterface":
    g.lang.vim.inInterface = false
  else:
    discard

proc matchTakesPattern(g: GeneralTokenizer, pos: int): bool =
  ## `:match {group} /pat/`. Not `:match` or `:match none`, which clear.
  let start = g.endLWS(pos)
  var p = start
  while g.buf[p] notin wsChars + {'\0', '|'}:
    inc(p)
  let commentChar = if g.vim9Mode: '#' else: '"'
  p > start and g.buf[start] != commentChar and g.text(start, p).toLowerAscii != "none"

proc commandWord(g: var GeneralTokenizer, command: string, pos: int) =
  ## Flags for the full command name `command`, whose token ends at `pos`.
  g.scopeCommand(command, pos)
  let exprCommand = vimExprCommands.has(command)
  if vimModifiers.has(command):
    # The command follows.
    g.lang.vim.line.excl vlfAfterValue
    case command
    of "abstract":
      g.lang.vim.line.incl vlfAbstract
    of "legacy":
      g.lang.vim.line.incl vlfLegacy
    else:
      discard
  else:
    # `:let` and `:const` end at a comment, unlike `:return`: `let " c` lists
    # the variables, `return " c` is E114.
    g.operand(not exprCommand or command in ["const", "let"])
  # Outside an expression a spaced `"` opens a comment even after an operator:
  # `set path+=** " c`
  if exprCommand or command in ["def", "for", "function", "type"]:
    g.lang.vim.line.incl vlfExpr

  if vimMapCommands.has(command):
    g.lang.vim.line.incl {vlfKeys, vlfMap}
  elif vimScriptCommands.has(command):
    # The rest of the line is the other language's.
    g.lang.vim.line.incl {vlfScriptCmd, vlfQuoteString, vlfForeign}
  else:
    case command
    of "normal":
      g.lang.vim.line.incl vlfKeys
    of "function":
      g.lang.vim.line.incl {vlfFuncDef, vlfFuncName}
    of "def":
      g.lang.vim.line.incl vlfFuncName
    of "catch":
      # Vim9 reads a spaced `#` as a comment, so a catch-all: `catch # all`
      if not (g.vim9Mode and g.buf[pos] in lwsChars and g.buf[g.endLWS(pos)] == '#'):
        g.lang.vim.line.incl vlfPattern
    of "filter", "global", "vglobal":
      g.lang.vim.line.incl vlfPattern
    of substituteCommands:
      g.lang.vim.line.incl vlfSubstitute
    of "match":
      if g.matchTakesPattern(pos):
        g.lang.vim.line.incl vlfSpacedPattern
    of "sort":
      g.lang.vim.line.incl vlfSortPattern
    of "lvimgrep", "lvimgrepadd", "vimgrep", "vimgrepadd":
      g.lang.vim.line.incl vlfArgPattern
    of "const", "final", "let", "var":
      g.lang.vim.line.incl vlfAssignTarget
    of "echo", "echoconsole", "echoerr", "echomsg", "echon", "echowindow", "execute":
      g.lang.vim.line.incl vlfQuoteString
    of "luado", "perldo", "py3do", "pydo", "pyxdo", "rubydo", "tcldo":
      # As after `:lua`.
      g.lang.vim.line.incl {vlfQuoteString, vlfForeign}
    of "autocmd":
      g.lang.vim.line.incl {vlfAuGroup, vlfAuEvent}
    of "command":
      g.lang.vim.line.incl vlfComAttrs
    of "read", "write":
      if command == "read" and g.buf[pos - 1] == '!':
        # `:r!ls`, unlike `:w!`, reads a shell command.
        g.lang.vim.line.incl vlfForeign
      else:
        g.lang.vim.line.incl vlfFileCmd
    of "syntax":
      g.lang.vim.line.incl vlfSyntax
    of "argdo", "bufdo", "cdo", "cfdo", "folddoclosed", "folddoopen", "ldo", "lfdo",
        "tabdo", "windo":
      # The command follows: `windo set nowrap`
      g.lang.vim.line.excl {vlfMidCommand, vlfAfterValue}
    else:
      discard

const vimCmdlineEndKeys = ["cr", "enter", "esc", "nl", "return"]
  ## Keys that leave a map's command line and return to its keys.

proc keyName(g: GeneralTokenizer, pos: int): string =
  ## Lowercase name of the `<...>` key at `pos`, or "".
  if g.buf[pos] == '<':
    let keyEnd = g.keyNotationEnd(pos)
    if keyEnd > 0:
      return g.text(pos + 1, keyEnd - 1).toLowerAscii

proc commentEnd(g: GeneralTokenizer, pos: int): int =
  ## A comment in a map's `:cmd` ends where the keys leave the command line or
  ## a `|` ends the map.
  if vlfMap notin g.lang.vim.line:
    return g.endLine(pos)
  result = pos + 1
  while g.buf[result] notin eolChars:
    if g.buf[result] == '|' and g.buf[result - 1] != '\\':
      return
    if g.keyName(result) in vimCmdlineEndKeys:
      return
    inc(result)

proc mapArgument(g: GeneralTokenizer, pos: int): bool =
  ## `<silent>` and the like, which come before a map's lhs.
  g.keyName(pos) in [
    "buffer", "expr", "nowait", "script", "silent", "special", "unique"
  ]

proc exprMapRhs(g: var GeneralTokenizer, pos: int) =
  ## In an `<expr>` map, switch to an expression at the word after the lhs.
  let line = g.lang.vim.line
  if vlfExprMap notin line:
    return
  if vlfMapLhs notin line:
    if not g.mapArgument(pos):
      g.lang.vim.line.incl vlfMapLhs
  elif g.buf[pos - 1] in wsChars:
    g.lang.vim.line = line - {vlfKeys, vlfMap, vlfExprMap, vlfMapLhs} + {vlfQuoteString}

proc wrapperArg(g: var GeneralTokenizer, position: int): int =
  ## A word of `:autocmd`'s or `:command`'s arguments, or -1 where the
  ## command they wrap starts. In a map, a key that leaves the command line
  ## or separates commands ends them like a `|`: `:au BufRead<CR>`
  let inMap = vlfMap in g.lang.vim.line
  template endsArgs(pos: int): bool =
    inMap and (let name = g.keyName(pos); name == "bar" or name in vimCmdlineEndKeys)

  result = position
  while g.buf[result] notin wsChars + {'\0', '|'} and not endsArgs(result):
    inc(result)
  if result == position:
    return -1
  let
    word = g.text(position, result)
    line = g.lang.vim.line
  if vlfComAttrs in line:
    if word[0] == '-':
      g.kind = gtSpecialVar
    else:
      g.kind = gtFunctionName
      g.lang.vim.line = line * commandScope
  elif vlfAuEvent in line:
    let event = word.split(',')[0].toLowerAscii
    if vlfAuGroup in line and event != "*" and not vimAutocmdEvents.has(event):
      g.kind = gtIdentifier
      g.lang.vim.line.excl vlfAuGroup
    else:
      g.kind = gtTypeName
      g.lang.vim.line = line - {vlfAuGroup, vlfAuEvent} + {vlfAuPattern}
  elif vlfAuPattern in line:
    g.kind = if word.startsWith("<buffer"): gtSpecialVar else: gtNone
    g.lang.vim.line = line - {vlfAuPattern} + {vlfAuOptions}
  elif word in ["++once", "++nested", "nested"]:
    g.kind = gtSpecialVar
  else:
    g.lang.vim.line = line * commandScope
    result = -1

proc syntaxSubcommand(g: var GeneralTokenizer, word: string) =
  ## `word` follows `:syntax`; `match` and `region` take patterns.
  g.kind = gtIdentifier
  g.lang.vim.line.excl vlfSyntax
  case word
  of "match", "linecont":
    g.lang.vim.line.incl vlfSpacedPattern
  of "region":
    g.lang.vim.line.incl vlfSynRegion
  of "sync":
    # `:syntax sync match`
    g.lang.vim.line.incl vlfSyntax
  else:
    discard

proc vimWord(
    g: var GeneralTokenizer, word: string, position: int, cmdPos, expectName: bool
): int =
  ## Classify the identifier `word` ending at `position`; returns the token end.
  result = position
  let
    next = g.buf[result]
    command = block:
      let c =
        if cmdPos:
          vimCommand(word)
        else:
          ""
      if g.vim9Mode and vim9InvalidCommands.has(c): "" else: c
    vim9Expr = cmdPos and g.vim9Mode and g.startsExpression(word, command, result)
  if vlfHeredocHeader in g.lang.vim.line:
    g.kind = gtKeyword
  elif expectName:
    g.kind = gtFunctionName
  elif word.startsWith("v:"):
    g.kind = if vimBooleans.has(word): gtBoolean else: gtSpecialVar
  elif command.len > 0 and not vim9Expr:
    # Legacy script calls a function with `:call` only: `execute("x")` is `:execute`
    g.kind = gtKeyword
    if next == '!' and command notin substituteCommands and
        g.peek(result) notin {'=', '~'}:
      inc(result)
    g.commandWord(command, result)
    return
  elif vlfSyntax in g.lang.vim.line:
    g.syntaxSubcommand(word)
  elif vlfSynRegion in g.lang.vim.line and next == '=' and
      word in ["end", "skip", "start"]:
    # The pattern follows the `=`: `start=+"+`
    g.kind = gtIdentifier
    g.lang.vim.line.incl vlfArgPattern
    g.operand(false)
    return result + 1
  elif word in ["in", "is", "isnot"] and next != '(' and
      g.lang.vim.line * {vlfExpr, vlfQuoteString} != {}:
    # Not in an argument or keys: `set is`, `onoremap is`
    g.kind = gtKeyword
    if word != "in" and next in {'#', '?'}:
      inc(result)
    g.operand(false)
    return
  elif vlfFuncDef in g.lang.vim.line and word in ["abort", "closure", "dict", "range"]:
    g.kind = gtKeyword
  elif next == '(' and vimBuiltins.has(word):
    g.kind = gtBuiltin
  elif vimBooleans.has(word):
    g.kind = gtBoolean
  elif vimSpecialVars.has(word):
    g.kind = gtSpecialVar
  elif g.vim9Mode and next != '(' and vimTypes.has(word):
    g.kind = gtTypeName
  else:
    g.kind = gtIdentifier
  if vim9Expr:
    # Vim9 assigns without `:let`: `lines =<< END`
    g.lang.vim.line.incl {vlfAssignTarget, vlfExpr}
  g.operand(true)

proc scopePrefix(g: GeneralTokenizer, pos: int): bool =
  ## A `g:` at `pos` that starts a scoped name, or stands alone for the scope's
  ## dictionary: `get(g:, 'x')`, `var all = g:`. Not a dict key or a Vim9
  ## type: `#{b: 2}`, `var s: string`
  if g.buf[pos] notin scopeChars or g.peek(pos) != ':':
    return false
  let next = g.peek(pos, 2)
  next in symChars + {',', ')', ']', '}', '[', '|'} or
    (next == '-' and g.peek(pos, 3) == '>') or g.buf[g.endLWS(pos + 2)] in eolChars

func inExpression(g: GeneralTokenizer): bool =
  ## A Vim9 expression line, whose brackets and operators may continue it.
  ## Not typed keys, where `<CR>` ends a `:cmd`.
  g.vim9Mode and vlfExpr in g.lang.vim.line and not g.typed

template binaryOperator(g: var GeneralTokenizer) =
  if g.inExpression:
    g.lang.vim.line.incl vlfAfterOperator

proc afterArrow(g: GeneralTokenizer, pos: int): bool =
  var p = pos - 1
  while p > 0 and g.buf[p] in lwsChars:
    dec(p)
  p > 0 and g.buf[p] == '>' and g.buf[p - 1] == '='

proc openBracket(g: var GeneralTokenizer, pos: int, cmdPos: bool) =
  ## Track the Vim9 bracket at `pos`. A `{` that starts a command or follows
  ## a lambda's `=>` is a block.
  let c = g.buf[pos]
  if c == '{' and (cmdPos or g.afterArrow(pos)):
    if not g.typed:
      g.lang.vim.brackets.add 'B'
  else:
    if cmdPos:
      g.lang.vim.line.incl vlfExpr
    if g.inExpression:
      g.lang.vim.brackets.add c

proc closeBracket(g: var GeneralTokenizer, c: char, cmdPos: bool) =
  ## A closer without its opener on top is not tracked. A block's `}` starts
  ## a command; a later one is a key or text: `normal! }`
  if g.typed:
    return
  let openers =
    case c
    of ')':
      {'('}
    of ']':
      {'['}
    of '>':
      {'<'}
    elif cmdPos:
      {'{', 'B'}
    else:
      {'{'}
  if g.lang.vim.brackets.len > 0 and g.lang.vim.brackets[^1] in openers:
    g.lang.vim.brackets.setLen(g.lang.vim.brackets.len - 1)

proc continuationComment(g: GeneralTokenizer, pos: int): bool =
  ## A comment line between `\` continuation lines, at a line's start: `"\ `
  ## in legacy script, any `#` comment in Vim9.
  if g.vim9Mode:
    g.buf[pos] == '#' and g.peek(pos) != '{'
  else:
    g.buf[pos] == '"' and g.peek(pos) == '\\' and g.peek(pos, 2) == ' '

proc vimCode(g: var GeneralTokenizer, position: int): int =
  ## A token outside strings and heredoc bodies.
  var pos = position
  if g.buf[pos] == '\\' and g.atLineStart(pos):
    # A line continuation keeps the flags of the line it continues.
    g.kind = gtSpecialVar
    return pos + 1
  if g.continuationComment(pos) and g.atLineStart(pos):
    g.kind = gtComment
    return g.endLine(pos)
  if g.lang.vim.line * {vlfAuEvent, vlfAuPattern, vlfAuOptions, vlfComAttrs} != {} and
      g.buf[pos] notin wsChars + {'|'}:
    let argEnd = g.wrapperArg(pos)
    if argEnd >= 0:
      return argEnd
  if g.buf[pos] notin wsChars:
    g.exprMapRhs(pos)

  let
    cmdPos = vlfMidCommand notin g.lang.vim.line
    expectName = vlfFuncName in g.lang.vim.line
    expectPattern = vlfPattern in g.lang.vim.line
    expectSubstitute = vlfSubstitute in g.lang.vim.line
    afterScriptCmd = vlfScriptCmd in g.lang.vim.line
    afterOperator = vlfAfterOperator in g.lang.vim.line
    afterFileCmd = vlfFileCmd in g.lang.vim.line
    patternOpeners =
      if vlfKeys in g.lang.vim.line:
        {}
      elif expectPattern or expectSubstitute or vlfSortPattern in g.lang.vim.line:
        patternDelims
      elif vlfArgPattern in g.lang.vim.line or
        (vlfSpacedPattern in g.lang.vim.line and pos > 0 and g.buf[pos - 1] in lwsChars):
        patternDelims + {'"'}
      else:
        {}
    # A Vim9 range needs a leading `:`.
    rangeStart =
      cmdPos and (not g.vim9Mode or (pos > 0 and g.buf[pos - 1] in {':', ','}))
  if g.buf[pos] notin wsChars:
    g.lang.vim.line.excl {
      vlfFuncName, vlfPattern, vlfSubstitute, vlfScriptCmd, vlfAfterOperator,
      vlfArgPattern, vlfFileCmd,
    }

  template lexOperator() =
    let opStart = pos
    while g.buf[pos] in vimOpChars and
        not (pos > opStart and g.buf[pos] == '<' and g.keyNotationEnd(pos) > 0):
      inc(pos)
    var op = g.text(opStart, pos)
    if g.buf[pos] == '#' and op in ["!=", "!~", "<", "<=", "==", "=~", ">", ">="]:
      # match case: `==#`. Not after `=`: `guifg=#808080`
      inc(pos)
      op.add '#'
    g.kind = gtOperator
    # Vim9's `++n` and `--n`, as a range there needs a leading `:`
    let increment =
      cmdPos and g.vim9Mode and op in ["++", "--"] and (
        opStart == 0 or g.buf[opStart - 1] in wsChars + {'|'} or
        g.afterKeyNotation(opStart)
      )
    if cmdPos and not increment and op.allCharsInSet({'%', '.', '+', '-'}):
      # A range: `%s/a/b/`, `.,+2d`
      g.lang.vim.line.excl vlfAfterValue
    else:
      g.operand(false)
      if op != "!":
        g.binaryOperator
    if (cmdPos and op[^1] == '!' and op.allCharsInSet({'%', '.', '+', '-', '!'})) or
        (op == "!" and afterFileCmd):
      # `:!ls`, `:%!sort`, `:w !sudo tee %`
      g.lang.vim.line.incl vlfForeign
    let opensHeredoc =
      (op == "=<<" and vlfAssignTarget in g.lang.vim.line) or
      (op == "<<" and afterScriptCmd)
    if opensHeredoc and not g.typed:
      let spec = g.heredocSpec(pos, script = op == "<<")
      if spec.marker.len > 0:
        g.lang.vim.heredocMarker = spec.marker
        if not spec.trim:
          g.lang.vim.cmdlineIndent = ""
        g.lang.vim.line =
          g.lang.vim.line - {vlfQuoteString, vlfForeign} + {vlfHeredocHeader}
    elif op.endsWith('='):
      # The target ends at its assignment: `let x = a =<< b`
      g.lang.vim.line.excl vlfAssignTarget

  # A key is no delimiter: `:vimgrep <C-r><C-w> %<CR>`
  if g.buf[pos] in patternOpeners and
      not (g.buf[pos] == '<' and g.keyNotationEnd(pos) > 0):
    g.kind = gtRegularExpression
    pos = g.scanPattern(pos, if expectSubstitute: 2 else: 1)
    if expectPattern:
      # `:g/pat/cmd`
      g.lang.vim.line = g.lang.vim.line * commandScope
    else:
      g.lang.vim.line.excl {vlfSpacedPattern, vlfSortPattern}
      g.operand(true)
    return pos

  case g.buf[pos]
  of ' ', '\t' .. '\r':
    g.kind = gtWhitespace
    while g.buf[pos] in wsChars:
      inc(pos)
  of '"':
    let
      spaced = pos > 0 and g.buf[pos - 1] in lwsChars
      line = g.lang.vim.line
    if vlfKeys in line:
      inc(pos)
      if g.buf[pos] in registerChars:
        g.kind = gtSpecialVar
        inc(pos)
      else:
        g.kind = gtNone
      g.operand(true)
    elif not g.vim9Mode and line * {vlfQuoteString, vlfForeign} == {} and
        (cmdPos or (spaced and (vlfAfterValue in line or vlfExpr notin line))):
      g.kind = gtComment
      pos = g.commentEnd(pos)
    else:
      g.kind = gtStringLit
      g.lang.vim.line.excl vlfInterpolated
      inc(pos)
      pos = g.scanStringBody(pos, '"')
      g.operand(true)
  of '\'':
    if vlfKeys in g.lang.vim.line:
      g.kind = gtNone
      inc(pos)
      g.operand(true)
    elif rangeStart and g.peek(pos) notin wsChars + {'\0'} and g.peek(pos, 2) != '\'':
      # A mark in a range: `'<,'>`
      g.kind = gtSpecialVar
      inc(pos, 2)
      g.lang.vim.line.excl vlfAfterValue
    else:
      g.kind = gtStringLit
      pos = g.singleQuoted(pos)
      g.operand(true)
  of '#':
    let spaced = pos == 0 or g.buf[pos - 1] in wsChars
    var hexColor = g.buf[pos + 1] in hexChars
    if hexColor:
      for i in 2 .. 6:
        if g.buf[pos + i] notin hexChars:
          hexColor = false
          break
      hexColor = hexColor and g.buf[pos + 7] notin symChars
    if g.vim9Mode and g.lang.vim.line * {vlfKeys, vlfForeign} == {} and
        (cmdPos or spaced):
      g.kind = gtComment
      pos = g.commentEnd(pos)
      if afterOperator:
        g.lang.vim.line.incl vlfAfterOperator
    elif cmdPos:
      # Legacy `:#` is `:number`.
      g.kind = gtKeyword
      inc(pos)
      g.operand(true)
    elif hexColor:
      # `guifg=#808080`
      g.kind = gtHexNumber
      inc(pos, 7)
      g.operand(true)
    else:
      g.kind = gtOperator
      inc(pos)
      g.operand(false)
  of '\\':
    g.kind = gtEscapeSequence
    let bar = g.peek(pos) == '|'
    inc(pos)
    g.skipEscapedChar(pos)
    if bar and g.inMapCmdline:
      g.lang.vim.line = g.lang.vim.line * commandScope
    else:
      g.operand(true)
  of '|':
    g.kind = gtOperator
    if g.peek(pos) == '|':
      inc(pos, 2)
      g.operand(false)
      g.binaryOperator
    elif g.lang.vim.line * {vlfKeys, vlfForeign} != {} and vlfMap notin g.lang.vim.line:
      # Keys, a shell command and a script take a `|`: `normal! 0|x`, `lua a | b`
      inc(pos)
      g.operand(false)
    else:
      inc(pos)
      # A map ends at a `|`, `:normal` takes it as a key: `normal! :a | b`
      g.lang.vim.line =
        if vlfMap in g.lang.vim.line:
          {}
        else:
          g.lang.vim.line * {vlfTyped}
  of ':':
    g.kind = gtPunctuation
    if cmdPos:
      while g.buf[pos] == ':':
        inc(pos)
    else:
      # `:cmd` in a map's rhs or `:normal`'s keys, after a blank or a key like
      # `<Esc>`, maybe with a range: `:.,$d`. Not a ternary's `:`: `c ? a :b`
      let
        afterKey = pos > 0 and g.buf[pos - 1] in lwsChars + {'>'}
        opensCommand =
          vlfKeys in g.lang.vim.line and afterKey and (
            g.peek(pos) in cmdlineStartChars or
            (g.peek(pos) == '<' and vlfMap in g.lang.vim.line)
          )
      inc(pos)
      if opensCommand:
        g.enterTypedCmdline(legacy = true)
      else:
        g.operand(false)
        g.binaryOperator
  of '<':
    if g.inExpression and pos > 0 and g.buf[pos - 1] in symChars:
      # A generic, as a `<` operator needs blanks in Vim9: `list<string>`
      g.kind = gtPunctuation
      g.lang.vim.brackets.add '<'
      inc(pos)
      g.operand(false)
    else:
      let keyEnd = g.keyNotationEnd(pos)
      if keyEnd < 0:
        lexOperator()
      else:
        let name = g.text(pos + 1, keyEnd - 1).toLowerAscii
        g.kind = gtSpecialVar
        pos = keyEnd
        # Keys right after a map's `:` edit the command line: `:<C-u>call F()`.
        # A `:command` placeholder may stand for a modifier or a range.
        if not (
          cmdPos and
          (vlfMap in g.lang.vim.line or name in ["count", "line1", "line2", "mods"])
        ):
          g.operand(true)
        case name
        of "expr":
          if vlfMap in g.lang.vim.line and vlfMapLhs notin g.lang.vim.line:
            g.lang.vim.line.incl vlfExprMap
        of "cmd", "scriptcmd":
          g.enterTypedCmdline(legacy = name == "cmd")
        of "bar":
          if g.inMapCmdline:
            g.lang.vim.line = g.lang.vim.line * commandScope
        of vimCmdlineEndKeys:
          # Back to the keys, dropping what the command line set. An `<expr>`
          # map's lhs may hold the key: `inoremap <expr> <CR> ...`
          if vlfMap in g.lang.vim.line:
            g.lang.vim.line =
              g.lang.vim.line * {vlfMap, vlfExprMap, vlfMapLhs} +
              {vlfMidCommand, vlfKeys}
        of "sid", "snr":
          if expectName:
            g.lang.vim.line.incl vlfFuncName
        else:
          discard
  of '&':
    var p = pos + 1
    if g.buf[p] in {'g', 'l'} and g.peek(p) == ':' and g.peek(p, 2) in letters:
      inc(p, 2)
    if g.buf[p] in letters:
      # An option: `&tabstop`, `&l:shiftwidth`
      g.kind = gtPreprocessor
      pos = p
      while g.buf[pos] in {'a' .. 'z', 'A' .. 'Z', '0' .. '9', '_'}:
        inc(pos)
      g.operand(true)
    else:
      g.kind = gtOperator
      inc(pos, if g.buf[p] == '&': 2 else: 1)
      g.operand(false)
      g.binaryOperator
  of '$':
    let next = g.peek(pos)
    if rangeStart or vlfKeys in g.lang.vim.line or next notin letters + {'_', '"', '\''}:
      # The last line in a range, or the `$` motion in keys
      g.kind = gtOperator
      inc(pos)
      if cmdPos:
        g.lang.vim.line.excl vlfAfterValue
      else:
        g.operand(false)
    elif next in {'"', '\''}:
      # Vim9 interpolated string
      g.kind = gtStringLit
      pos = g.interpolatedBody(pos + 2, next)
      g.operand(true)
    else:
      g.kind = gtPreprocessor # environment variable
      inc(pos)
      while g.buf[pos] in symChars:
        inc(pos)
      g.operand(true)
  of '@':
    g.kind = gtOperator
    inc(pos)
    if vlfKeys notin g.lang.vim.line and g.buf[pos] in letters and
        g.peek(pos) in symChars:
      # A syntax cluster: `contains=@Spell`. No register takes a longer name.
      g.kind = gtSpecialVar
      while g.buf[pos] in symChars:
        inc(pos)
      g.operand(true)
    elif g.buf[pos] in registerChars:
      g.kind = gtSpecialVar
      inc(pos)
      g.operand(true)
    else:
      g.operand(false)
  of '0' .. '9':
    pos = g.vimNumber(pos)
    if cmdPos:
      g.lang.vim.line.excl vlfAfterValue # a line number in a range
    else:
      g.operand(true)
  of 'a' .. 'z', 'A' .. 'Z', '_', '\x80' .. '\xFF':
    let wordStart = pos
    # A command and its `:` delimiter at command position: `%s:a:b:`, `:g:pat:d`.
    # Vim9 puts nothing before a statement's `g:x` but a key: `<ScriptCmd>g:x = 1`
    let maybeCommand =
      cmdPos and (
        not g.vim9Mode or
        (pos > 0 and g.buf[pos - 1] notin wsChars and not g.afterKeyNotation(pos))
      )
    if not maybeCommand and g.scopePrefix(pos):
      inc(pos, 2)
    # `#` joins autoload names: `plug#begin`
    var hash = -1
    while g.buf[pos] in symChars or (g.buf[pos] == '#' and g.peek(pos) in symChars):
      if g.buf[pos] == '#' and hash < 0:
        hash = pos
      inc(pos)
    if hash >= 0 and cmdPos and not (g.vim9Mode and g.buf[pos] == '(') and
        vimCommand(g.text(wordStart, hash)) in
        ["global", "smagic", "snomagic", "substitute", "vglobal"]:
      # A `#` delimiter: `s#a#b#`
      pos = hash
    pos = g.vimWord(g.text(wordStart, pos), pos, cmdPos, expectName)
  of '(', '[', '{', ',', ';':
    g.kind = gtPunctuation
    if g.vim9Mode and g.buf[pos] in {'(', '[', '{'}:
      g.openBracket(pos, cmdPos)
    inc(pos)
    if cmdPos and g.buf[pos - 1] in {',', ';'}:
      g.lang.vim.line.excl vlfAfterValue # `'<,'>`
    else:
      g.operand(false)
  of ')', ']', '}':
    g.kind = gtPunctuation
    if g.vim9Mode:
      g.closeBracket(g.buf[pos], cmdPos)
    inc(pos)
    g.operand(true)
  of '>':
    if g.lang.vim.brackets.endsWith('<'):
      g.kind = gtPunctuation
      g.closeBracket('>', cmdPos)
      inc(pos)
      g.operand(true)
    else:
      lexOperator()
  else:
    if g.buf[pos] in vimOpChars:
      lexOperator()
    else:
      g.kind = gtNone
      inc(pos)
      g.operand(false)
  if cmdPos and g.vim9Mode and vlfMidCommand in g.lang.vim.line and
      g.kind in {gtStringLit, gtPreprocessor, gtSpecialVar}:
    # An expression statement: `'x'->F()`, `&tabstop = 4`, `@a = ''`
    g.lang.vim.line.incl vlfExpr
  pos

proc startsStatement(g: GeneralTokenizer, pos: int): bool =
  var p = pos
  while g.buf[p] in letters:
    inc(p)
  p > pos and g.buf[p] in lwsChars + eolChars and vim9Statements.has(g.text(pos, p))

proc continuesExpression(g: var GeneralTokenizer, pos: int): bool =
  ## A Vim9 line inside brackets, after a binary operator, or starting with
  ## one (`->F()`, `.. x`, `? a`, `: b`) below an expression continues it.
  if not g.vim9Mode:
    return false
  if g.lang.vim.brackets.len > 0 and g.lang.vim.brackets[^1] != 'B':
    if g.startsStatement(pos):
      # The unclosed brackets end with the block holding them.
      while g.lang.vim.brackets.len > 0 and g.lang.vim.brackets[^1] != 'B':
        g.lang.vim.brackets.setLen(g.lang.vim.brackets.len - 1)
      return false
    return true
  if vlfAfterOperator in g.lang.vim.line:
    return true
  if not g.inExpression:
    return false
  case g.buf[pos]
  of '-', '+':
    g.peek(pos) != g.buf[pos] # `++n` and `--n` are statements
  of '*', '/', '%', '?', '.', '<', '>':
    true
  of 'i':
    # `is` and `isnot`, maybe with `#` or `?`. Not a name: `is_ok`
    if g.peek(pos) != 's':
      return false
    var p = pos + 2
    if g.buf[p] == 'n' and g.peek(p) == 'o' and g.peek(p, 2) == 't':
      inc(p, 3)
    if g.buf[p] in {'#', '?'}:
      inc(p)
    g.buf[p] in lwsChars + eolChars
  of ':':
    g.peek(pos) in lwsChars
  of '&':
    g.peek(pos) == '&'
  of '|':
    g.peek(pos) == '|'
  of '=', '!':
    g.peek(pos) in {'=', '~'}
  else:
    false

proc startLine(g: var GeneralTokenizer, pos: int) =
  ## The state at a line's first non-blank token, at `pos`.
  if g.lang.vim.heredocMarker.len > 0:
    g.state = gtLongStringLit
    g.lang.vim.line = {}
    return
  if not g.vim9Scope:
    g.lang.vim.brackets = ""
  # A generic does not span lines.
  while g.lang.vim.brackets.endsWith('<'):
    g.lang.vim.brackets.setLen(g.lang.vim.brackets.len - 1)
  if g.buf[pos] == '\\' or g.continuationComment(pos):
    discard # A continuation, which `vimCode` handles.
  elif g.continuesExpression(pos):
    g.lang.vim.line.incl vlfMidCommand
  else:
    g.lang.vim.line = {}
    g.lang.vim.cmdlineIndent = g.lineIndent(pos)

proc vimNextToken*(g: var GeneralTokenizer) =
  var pos = g.pos
  g.start = g.pos

  if g.buf[pos] == '\0':
    g.kind = gtEof
  elif g.state == gtLongStringLit:
    pos = g.heredocBody(pos)
  elif g.state == gtStringLit and g.buf[pos] notin eolChars:
    # Resume a `"` string parked on a backslash by `scanStringBody`.
    if g.buf[pos] == '\\':
      g.kind = gtEscapeSequence
      pos = g.stringEscape(pos)
      if g.buf[pos] in eolChars:
        g.state = gtNone
    else:
      g.kind = gtStringLit
      g.state = gtNone
      pos =
        if vlfInterpolated in g.lang.vim.line:
          g.interpolatedBody(pos, '"')
        else:
          g.scanStringBody(pos, '"')
  else:
    g.state = gtNone
    # Not on a blank token: a blank run may start on the line above, and the
    # state it leaves at the boundary must not depend on where parsing began.
    if g.buf[pos] notin wsChars and g.atLineStart(pos):
      g.startLine(pos)
    if g.state == gtLongStringLit:
      pos = g.heredocBody(pos)
    else:
      pos = g.vimCode(pos)

  g.length = pos - g.pos
  if g.kind != gtEof and g.length <= 0:
    assert false, "vimNextToken: produced an empty token"
  g.pos = pos
