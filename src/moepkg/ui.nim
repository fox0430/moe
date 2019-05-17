import posix, strformat
from os import execShellCmd
import ncurses
import unicodeext

type Attributes* = enum
  normal = A_NORMAL
  standout = A_STANDOUT
  underline = A_UNDERLINE
  reverse = A_REVERSE
  blink = A_BLINK
  dim = A_DIM
  bold = A_BOLD
  altcharet = A_ALT_CHARSET
  invis = A_INVIS
  protect = A_PROTECT
  #chartext = A_CHAR_TEXT

type CursorType* = enum
  blockMode = 0
  ibeamMode = 1

type Color* = enum
  default             = -1,
  black               = 0,
  maroon              = 1,
  green               = 2,
  olive               = 3,
  navy                = 4,
  purple_1            = 5,
  teal                = 6,
  silver              = 7,
  gray                = 8,
  red                 = 9,
  lime                = 10,
  yellow              = 11,
  blue                = 12,
  fuchsia             = 13,
  aqua                = 14,
  white               = 15,
  gray0               = 16,
  navyBlue            = 17,
  darkBlue            = 18,
  blue3_1             = 19,
  blue3_2             = 20,
  blue1               = 21,
  darkGreen           = 22,
  deepSkyBlue4_1      = 23,
  deepSkyBlue4_2      = 24,
  deepSkyBlue4_3      = 25,
  dodgerBlue3_1       = 26,
  dodgerBlue3_2       = 27,
  green4              = 28,
  springGreen4        = 29,
  turquoise4          = 30,
  deepSkyBlue3_1      = 31,
  deepSkyBlue3_2      = 32,
  dodgerBlue1         = 33,
  green3_1            = 34,
  springGreen3_1      = 35,
  darkCyan            = 36,
  lightSeaGreen       = 37,
  deepSkyBlue2        = 38,
  deepSkyBlue1        = 39,
  green3_2            = 40,
  springGreen3_3      = 41,
  springGreen2_1      = 42,
  cyan3               = 43,
  darkTurquoise       = 44,
  turquoise2          = 45,
  green1              = 46,
  springGreen2_2      = 47,
  springGreen1        = 48,
  mediumSpringGreen   = 49,
  cyan2               = 50,
  cyan1               = 51,
  darkRed_1           = 52,
  deepPink4_1         = 53,
  purple4_1           = 54,
  purple4_2           = 55,
  purple3             = 56,
  blueViolet          = 57,
  orange4_1           = 58,
  gray37              = 59,
  mediumPurple4       = 60,
  slateBlue3_1        = 61,
  slateBlue3_2        = 62,
  royalBlue1          = 63,
  chartreuse4         = 64,
  darkSeaGreen4_1     = 65,
  paleTurquoise4      = 66,
  steelBlue           = 67,
  steelBlue3          = 68,
  cornflowerBlue      = 69,
  chartreuse3_1       = 70,
  darkSeaGreen4_2     = 71,
  cadetBlue_1         = 72,
  cadetBlue_2         = 73,
  skyBlue3            = 74,
  steelBlue1_1        = 75,
  chartreuse3_2       = 76,
  paleGreen3_1        = 77,
  seaGreen3           = 78,
  aquamarine3         = 79,
  mediumTurquoise     = 80,
  steelBlue1_2        = 81,
  chartreuse2_1       = 82,
  seaGreen2           = 83,
  seaGreen1_1         = 84,
  seaGreen1_2         = 85,
  aquamarine1_1       = 86,
  darkSlateGray2      = 87,
  darkRed_2           = 88,
  deepPink4_2         = 89,
  darkMagenta_1       = 90,
  darkMagenta_2       = 91,
  darkViolet_1        = 92,
  purple_2            = 93,
  orange4_2           = 94,
  lightPink4          = 95,
  plum4               = 96,
  mediumPurple3_1     = 97,
  mediumPurple3_2     = 98,
  slateBlue1          = 99,
  yellow4_1           = 100,
  wheat4              = 101,
  gray53              = 102,
  lightSlategray      = 103,
  mediumPurple        = 104,
  lightSlateBlue      = 105,
  yellow4_2           = 106,
  Wheat4              = 107,
  darkSeaGreen        = 108,
  lightSkyBlue3_1     = 109
  lightSkyBlue3_2     = 110
  skyBlue2            = 111
  chartreuse2_2       = 112
  darkOliveGreen3_1   = 113
  paleGreen3_2        = 114
  darkSeaGreen3_1     = 115
  darkSlateGray3      = 116
  skyBlue1            = 117
  chartreuse1         = 118
  lightGreen_1        = 119
  lightGreen_2        = 120
  paleGreen1_1        = 121
  aquamarine1_2       = 122
  darkSlateGray1      = 123
  red3_1              = 124
  deepPink4           = 125
  mediumVioletRed     = 126
  magenta3            = 127
  darkViolet_2        = 128
  purple              = 129
  darkOrange3_1       = 130
  indianRed_1         = 131
  hotPink3_1          = 132
  mediumOrchid3       = 133
  mediumOrchid        = 134
  mediumPurple2_1     = 135
  darkGoldenrod       = 136
  lightSalmon3_1      = 137
  rosyBrown           = 138
  gray63              = 139
  mediumPurple2_2     = 140
  mediumPurple1       = 141
  gold3_1             = 142
  darkKhaki           = 143
  navajoWhite3        = 144
  gray69              = 145
  lightSteelBlue3     = 146
  lightSteelBlue      = 147
  yellow3_1           = 148
  darkOliveGreen3_2   = 149
  darkSeaGreen3_2     = 150
  darkSeaGreen2_1     = 151
  lightCyan3          = 152
  lightSkyBlue1       = 153
  greenYellow         = 154
  darkOliveGreen2     = 155
  paleGreen1_2        = 156
  darkSeaGreen2_2     = 157
  darkSeaGreen1_1     = 158
  paleTurquoise1      = 159
  red3_2              = 160
  deepPink3_1         = 161
  deepPink3_2         = 162
  magenta3_1          = 163
  magenta3_2          = 164
  magenta2_1          = 165
  darkOrange3_2       = 166
  indianRed_2         = 167
  hotPink3_2          = 168
  hotPink2            = 169
  orchid              = 170
  mediumOrchid1_1     = 171
  orange3             = 172
  lightSalmon3_2      = 173
  lightPink3          = 174
  pink3               = 175
  plum3               = 176
  violet              = 177
  gold3_2             = 178
  lightGoldenrod3     = 179
  tan                 = 180
  mistyRose3          = 181
  thistle3            = 182
  plum2               = 183
  yellow3_2           = 184
  khaki3              = 185
  lightGoldenrod2     = 186
  lightYellow3        = 187
  gray84              = 188
  lightSteelBlue1     = 189
  yellow2             = 190
  darkOliveGreen1_1   = 191
  darkOliveGreen1_2   = 192
  darkSeaGreen1_2     = 193
  honeydew2           = 194
  lightCyan1          = 195
  red1                = 196
  deepPink2           = 197
  deepPink1_1         = 198
  deepPink1_2         = 199
  magenta2_2          = 200
  magenta1            = 201
  orangeRed1          = 202
  indianRed1_1        = 203
  indianRed1_2        = 204
  hotPink1_1          = 205
  hotPink1_2          = 206
  mediumOrchid1_2     = 207
  darkOrange          = 208
  salmon1             = 209
  lightCoral          = 210
  paleVioletRed1      = 211
  orchid2             = 212
  orchid1             = 213
  orange1             = 214
  sandyBrown          = 215
  lightSalmon1        = 216
  lightPink1          = 217
  pink1               = 218
  plum1               = 219
  gold1               = 220
  lightGoldenrod2_1   = 221
  lightGoldenrod2_2   = 222
  navajoWhite1        = 223
  mistyRose1          = 224
  thistle1            = 225
  yellow1             = 226
  lightGoldenrod1     = 227
  khaki1              = 228
  wheat1              = 229
  cornsilk1           = 230
  gray100             = 231
  gray3               = 232
  gray7               = 233
  gray11              = 234
  gray15              = 235
  gray19              = 236
  gray23              = 237
  gray27              = 238
  gray30              = 239
  gray35              = 240
  gray39              = 241
  gray42              = 242
  gray46              = 243
  gray50              = 244
  gray54              = 245
  gray58              = 246
  gray62              = 247
  gray66              = 248
  gray70              = 249
  gray74              = 250
  gray78              = 251
  gray82              = 252
  gray85              = 253
  gray89              = 254
  gray93              = 255

type ColorTheme* = enum
  config  = 0
  dark    = 1
  light   = 2
  vivid   = 3

type EditorColor* = object
  editorBg*: Color
  lineNum*: Color
  lineNumBg*: Color
  currentLineNum*: Color
  currentLineNumBg*: Color
  statusBar*: Color
  statusBarBg*: Color
  statusBarMode*: Color
  statusBarModeBg*: Color
  tab*: Color
  tabBg*: Color
  currentTab*: Color
  currentTabBg*: Color
  commandBar*: Color
  commandBarBg*: Color
  errorMessage*: Color
  errorMessageBg*: Color
  searchResult*: Color
  searchResultBg*: Color
  visualMode: Color
  visualModeBg: Color
  # color scheme
  defaultChar*: Color
  gtKeyword*: Color
  gtStringLit*: Color
  gtDecNumber*: Color
  gtComment*: Color
  gtLongComment*: Color
  gtWhitespace*: Color
  # filer mode
  currentFile*: Color
  currentFileBg*: Color
  file*: Color
  fileBg*: Color
  dir*: Color
  dirBg*: Color
  pcLink*: Color
  pcLinkBg*: Color

type EditorColorPair* = enum
  lineNum = 1
  currentLineNum = 2
  statusBar = 3
  statusBarMode = 4
  tab = 5
  currentTab = 6
  commandBar = 7
  errorMessage = 8
  searchResult = 9
  visualMode = 10
  # color scheme
  defaultChar = 11
  keyword = 12
  stringLit = 13
  decNumber = 14
  comment = 15
  longComment = 16
  whitespace = 17
  # filer mode
  currentFile = 18
  currentFileBg = 19
  file = 20
  fileBg = 21
  dir = 22
  dirBg = 23
  pcLink = 24
  pcLinkBg = 25

var ColorThemeTable*: array[ColorTheme, EditorColor] = [
  config: EditorColor(
    editorBg: default,
    lineNum: gray54,
    lineNumBg: default,
    currentLineNum: teal,
    currentLineNumBg: default,
    statusBar: white,
    statusBarBg: blue,
    statusBarMode: black,
    statusBarModeBg: white,
    tab: white,
    tabBg: default,
    currentTab: white,
    currentTabBg: blue,
    commandBar: gray100,
    commandBarBg: default,
    errorMessage: red,
    errorMessageBg: default,
    searchResult: default,
    searchResultBg: red,
    visualMode: gray100,
    visualModeBg: purple_1,
    # color scheme
    defaultChar: gray100,
    gtKeyword: seaGreen1_2,
    gtStringLit: purple_1,
    gtDecNumber: aqua,
    gtComment: white,
    gtLongComment: white,
    gtWhitespace: gray100,
    # filer mode
    currentFile: gray100,
    currentFileBg: teal,
    file: gray100,
    fileBg: default,
    dir: blue,
    dirBg: default,
    pcLink: teal,
    pcLinkBg: default
  ),
  dark: EditorColor(
    editorBg: default,
    lineNum: gray54,
    lineNumBg: default,
    currentLineNum: teal,
    currentLineNumBg: default,
    statusBar: white,
    statusBarBg: blue,
    statusBarMode: black,
    statusBarModeBg: white,
    tab: white,
    tabBg: default,
    currentTab: white,
    currentTabBg: blue,
    commandBar: gray100,
    commandBarBg: default,
    errorMessage: red,
    errorMessageBg: default,
    searchResult: default,
    searchResultBg: red,
    visualMode: gray100,
    visualModeBg: purple_1,
    # color scheme
    defaultChar: gray100,
    gtKeyword: seaGreen1_2,
    gtStringLit: purple_1,
    gtDecNumber: aqua,
    gtComment: white,
    gtLongComment: white,
    gtWhitespace: gray100,
    # filer mode
    currentFile: gray100,
    currentFileBg: teal,
    file: gray100,
    fileBg: default,
    dir: blue,
    dirBg: default,
    pcLink: teal,
    pcLinkBg: default
  ),
  light: EditorColor(
    editorBg: default,
    lineNum: gray54,
    lineNumBg: default,
    currentLineNum: black,
    currentLineNumBg: default,
    statusBar: blue,
    statusBarBg: gray54,
    statusBarMode: white,
    statusBarModeBg: teal,
    tab: blue,
    tabBg: gray54,
    currentTab: white,
    currentTabBg: blue,
    commandBar: black,
    commandBarBg: default,
    errorMessage: red,
    errorMessageBg: default,
    searchResult: default,
    searchResultBg: red,
    visualMode: black,
    visualModeBg: purple_1,
    # color scheme
    defaultChar: black,
    gtKeyword: seaGreen1_2,
    gtStringLit: purple_1,
    gtDecNumber: aqua,
    gtComment: white,
    gtLongComment: white,
    gtWhitespace: gray100,
    # filer mode
    currentFile: black,
    currentFileBg: deepPink1_1,
    file: black,
    fileBg: default,
    dir: deepPink1_1,
    dirBg: default,
    pcLink: teal,
    pcLinkBg: default
  ),
  vivid: EditorColor(
    editorBg: default,
    lineNum: gray54,
    lineNumBg: default,
    currentLineNum: deepPink1_1,
    currentLineNumBg: default,
    statusBar: black,
    statusBarBg: deepPink1_1,
    statusBarMode: black,
    statusBarModeBg: gray100,
    tab: white,
    tabBg: default,
    currentTab: black,
    currentTabBg: deepPink1_1,
    commandBar: gray100,
    commandBarBg: default,
    errorMessage: red,
    errorMessageBg: default,
    searchResult: default,
    searchResultBg: red,
    visualMode: gray100,
    visualModeBg: purple_1,
    # color scheme
    defaultChar: gray100,
    gtKeyword: seaGreen1_2,
    gtStringLit: purple_1,
    gtDecNumber: aqua,
    gtComment: white,
    gtLongComment: white,
    gtWhitespace: gray100,
    # filer mode
    currentFile: gray100,
    currentFileBg: deepPink1_1,
    file: gray100,
    fileBg: default,
    dir: deepPink1_1,
    dirBg: default,
    pcLink: teal,
    pcLinkBg: default
  ),
]

type Window* = object
  cursesWindow*: ptr window
  top, left, height*, width*: int
  y*, x*: int

proc setColorPair(colorPair: EditorColorPair, character, background: Color) =
  init_pair(cshort(ord(colorPair)), cshort(ord(character)), cshort(ord(background)))

proc setCursesColor*(editorColor: EditorColor) =
  start_color()   # enable color
  use_default_colors()    # set terminal default color

  setColorPair(EditorColorPair.lineNum , editorColor.lineNum, editorColor.lineNumBg)
  setColorPair(EditorColorPair.currentLineNum, editorColor.currentLineNum, editorColor.currentLineNumBg)
  setColorPair(EditorColorPair.statusBar, editorColor.statusBar, editorColor.statusBarBg)
  setColorPair(EditorColorPair.statusBarMode, editorColor.statusBarMode, editorColor.statusBarModeBg)
  setColorPair(EditorColorPair.tab , editorColor.tab, editorColor.tabBg)
  setColorPair(EditorColorPair.currentTab , editorColor.currentTab, editorColor.currentTabBg)
  setColorPair(EditorColorPair.commandBar , editorColor.commandBar, editorColor.commandBarBg)
  setColorPair(EditorColorPair.errorMessage , editorColor.errorMessage, editorColor.errorMessageBg)
  setColorPair(EditorColorPair.searchResult, editorColor.searchResult, editorColor.searchResultBg)
  setColorPair(EditorColorPair.visualMode, editorColor.visualMode, editorColor.visualModeBg)

  setColorPair(EditorColorPair.defaultChar, editorColor.defaultChar, Color.default)
  setColorPair(EditorColorPair.keyword, editorColor.gtKeyword, Color.default)
  setColorPair(EditorColorPair.stringLit, editorColor.gtStringLit, Color.default)
  setColorPair(EditorColorPair.decNumber, editorColor.gtDecNumber, Color.default)
  setColorPair(EditorColorPair.comment, editorColor.gtComment, Color.default)
  setColorPair(EditorColorPair.longComment, editorColor.gtLongComment, Color.default)
  setColorPair(EditorColorPair.whitespace, editorColor.gtWhitespace, Color.default)

  setColorPair(EditorColorPair.currentFile, editorColor.currentFile, editorColor.currentFileBg)
  setColorPair(EditorColorPair.file, editorColor.file, editorColor.fileBg)
  setColorPair(EditorColorPair.dir, editorColor.dir, editorColor.dirBg)
  setColorPair(EditorColorPair.pcLink, editorColor.pcLink, editorColor.pcLinkBg)

proc setIbeamCursor*() = discard execShellCmd("printf '\\033[6 q'")

proc setBlockCursor*() = discard execShellCmd("printf '\e[0 q'")

proc changeCursorType*(cursorType: CursorType) =
  case cursorType
  of blockMode: setBlockCursor()
  of ibeamMode: setIbeamCursor()

proc disableControlC() = setControlCHook(proc() {.noconv.} = discard)

proc restoreTerminalModes*() = reset_prog_mode()

proc saveCurrentTerminalModes*() = def_prog_mode()

proc setCursor*(cursor: bool) =
  if cursor == true: curs_set(1)   # enable cursor
  elif cursor == false: curs_set(0)   # disable cursor

proc keyEcho*(keyecho: bool) =
  if keyecho == true: echo()
  elif keyecho == false: noecho()
    
proc startUi*() =
  disableControlC()
  discard setLocale(LC_ALL, "")   # enable UTF-8
  initscr()   # start terminal control
  cbreak()    # enable cbreak mode
  setCursor(true)

  if can_change_color(): setCursesColor(ColorThemeTable[ColorTheme.vivid]) # default is vivid

  erase()
  keyEcho(false)
  set_escdelay(25)

proc exitUi*() = endwin()

proc initWindow*(height, width, top, left: int, color: EditorColorPair = EditorColorPair.defaultChar): Window =
  result.top = top
  result.left = left
  result.height = height
  result.width = width
  result.cursesWindow = newwin(cint(height), cint(width), cint(top), cint(left))
  keypad(result.cursesWindow, true)
  discard wbkgd(result.cursesWindow, ncurses.COLOR_PAIR(color))

proc write*(win: var Window, y, x: int, str: string, color: EditorColorPair = EditorColorPair.defaultChar, storeX: bool = true) =
  win.cursesWindow.wattron(cint(ncurses.COLOR_PAIR(ord(color))))
  mvwaddstr(win.cursesWindow, cint(y), cint(x), str)
  if storeX:
    win.y = y
    win.x = x+str.toRunes.width

proc write*(win: var Window, y, x: int, str: seq[Rune], color: EditorColorPair = EditorColorPair.defaultChar, storeX: bool = true) =
  write(win, y, x, $str, color, false)
  if storeX:
    win.y = y
    win.x = x+str.width

proc append*(win: var Window, str: string, color: EditorColorPair = EditorColorPair.defaultChar) =
  win.cursesWindow.wattron(cint(ncurses.COLOR_PAIR(ord(color))))
  mvwaddstr(win.cursesWindow, cint(win.y), cint(win.x), $str)
  win.x += str.toRunes.width

proc append*(win: var Window, str: seq[Rune], color: EditorColorPair = EditorColorPair.defaultChar) = append(win, $str, color)
  
proc erase*(win: var Window) =
  werase(win.cursesWindow)
  win.y = 0
  win.x = 0

proc refresh*(win: Window) = wrefresh(win.cursesWindow)

proc move*(win: Window, y, x: int) = mvwin(win.cursesWindow, cint(y), cint(x))

proc resize*(win: Window, height, width: int) = wresize(win.cursesWindow, cint(height), cint(width))

proc resize*(win: Window, height, width, y, x: int) =
  win.resize(height, width)
  win.move(y, x)

proc attron*(win: var Window, attributes: Attributes) = win.cursesWindow.wattron(cint(attributes))

proc attroff*(win: var Window, attributes: Attributes) = win.cursesWindow.wattroff(cint(attributes))

proc moveCursor*(win: Window, y, x: int) = wmove(win.cursesWindow, cint(y), cint(x))

let KEY_ESC = 27
var KEY_RESIZE {.header: "<ncurses.h>", importc: "KEY_RESIZE".}: int
var KEY_DOWN {.header: "<ncurses.h>", importc: "KEY_DOWN".}: int
var KEY_UP {.header: "<ncurses.h>", importc: "KEY_UP".}: int
var KEY_LEFT {.header: "<ncurses.h>", importc: "KEY_LEFT".}: int
var KEY_RIGHT {.header: "<ncurses.h>", importc: "KEY_RIGHT".}: int
var KEY_HOME {.header: "<ncurses.h>", importc: "KEY_HOME".}: int
var KEY_END {.header: "<ncurses.h>", importc: "KEY_END".}: int
var KEY_BACKSPACE {.header: "<ncurses.h>", importc: "KEY_BACKSPACE".}: int
var KEY_DC {.header: "<ncurses.h>", importc: "KEY_DC".}: int
var KEY_ENTER {.header: "<ncurses.h>", importc: "KEY_ENTER".}: int
var KEY_PPAGE {.header: "<ncurses.h>", importc: "KEY_PPAGE".}: int
var KEY_NPAGE {.header: "<ncurses.h>", importc: "KEY_NPAGE".}: int

proc getKey*(win: Window): Rune =
  var
    s = ""
    len: int
  block getfirst:
    let key = wgetch(win.cursesWindow)
    if not (key <= 0x7F or (0xC2 <= key and key <= 0xF0) or key == 0xF3): return Rune(key)
    s.add(char(key))
    len = numberOfBytes(char(key))
  for i in 0 ..< len-1: s.add(char(wgetch(win.cursesWindow)))
  
  let runes = toRunes(s)
  doAssert(runes.len == 1, fmt"runes length shoud be 1.")
  return runes[0]

proc isEscKey*(key: Rune): bool = key == KEY_ESC
proc isResizeKey*(key: Rune): bool = key == KEY_RESIZE
proc isDownKey*(key: Rune): bool = key == KEY_DOWN
proc isUpKey*(key: Rune): bool = key == KEY_UP
proc isLeftKey*(key: Rune): bool = key == KEY_LEFT
proc isRightKey*(key: Rune): bool = key == KEY_RIGHT
proc isHomeKey*(key: Rune): bool = key == KEY_HOME
proc isEndKey*(key: Rune): bool = key == KEY_END
proc isBackspaceKey*(key: Rune): bool = key == KEY_BACKSPACE or key == 8 or key == 127
proc isDcKey*(key: Rune): bool = key == KEY_DC
proc isEnterKey*(key: Rune): bool = key == KEY_ENTER or key == ord('\n')
proc isPageUpKey*(key: Rune): bool = key == KEY_PPAGE or key == 2
proc isPageDownkey*(key: Rune): bool = key == KEY_NPAGE or key == 6

proc isControlU*(key: Rune): bool = int(key) == 21
proc isControlH*(key: Rune): bool = int(key) == 8
proc isControlL*(key: Rune): bool = int(key) == 12
