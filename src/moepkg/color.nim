import std/[strutils, tables, macros, strformat, options]
import pkg/ncurses

type
  # Hex color code
  ColorCode* = array[6, char]

  # None is the terminal default color
  ColorPair* = tuple[fg, bg: Option[ColorCode]]

proc hexStrToIntStr(hexStr: string): string =
  result = $(fromHex[int](hexStr))

proc toColorCode*(str: string): Option[ColorCode] =
  if str.len == 6:
    var code: ColorCode
    for i, c in str:
      code[i] = c

    return some(code)
  elif str.len == 0:
    return none(ColorCode)
  else:
    assert(false)

proc initColorPair*(fgColorStr, bgColorStr: string): ColorPair {.inline.} =
  result = (
    fg: toColorCode(fgColorStr),
    bg: toColorCode(bgColorStr))

type Color* = enum
  default             = -1
  black               = 0    ## hex: #000000
  maroon              = 1    ## hex: #800000
  green               = 2    ## hex: #008000
  olive               = 3    ## hex: #808000
  navy                = 4    ## hex: #000080
  purple_1            = 5    ## hex: #800080
  teal                = 6    ## hex: #008080
  silver              = 7    ## hex: #c0c0c0
  gray                = 8    ## hex: #808080
  red                 = 9    ## hex: #ff0000
  lime                = 10   ## hex: #00ff00
  yellow              = 11   ## hex: #ffff00
  blue                = 12   ## hex: #0000ff
  fuchsia             = 13   ## hex: #ff00ff
  aqua                = 14   ## hex: #00ffff
  white               = 15   ## hex: #ffffff
  gray0               = 16   ## hex: #000000
  navyBlue            = 17   ## hex: #00005f
  darkBlue            = 18   ## hex: #000087
  blue3_1             = 19   ## hex: #0000af
  blue3_2             = 20   ## hex: #0000d7
  blue1               = 21   ## hex: #0000ff
  darkGreen           = 22   ## hex: #005f00
  deepSkyBlue4_1      = 23   ## hex: #005f5f
  deepSkyBlue4_2      = 24   ## hex: #005f87
  deepSkyBlue4_3      = 25   ## hex: #005faf
  dodgerBlue3_1       = 26   ## hex: #005fd7
  dodgerBlue3_2       = 27   ## hex: #005fff
  green4              = 28   ## hex: #008700
  springGreen4        = 29   ## hex: #00875f
  turquoise4          = 30   ## hex: #008787
  deepSkyBlue3_1      = 31   ## hex: #0087af
  deepSkyBlue3_2      = 32   ## hex: #0087d7
  dodgerBlue1         = 33   ## hex: #0087ff
  green3_1            = 34   ## hex: #00af00
  springGreen3_1      = 35   ## hex: #00af5f
  darkCyan            = 36   ## hex: #00af87
  lightSeaGreen       = 37   ## hex: #00afaf
  deepSkyBlue2        = 38   ## hex: #00afd7
  deepSkyBlue1        = 39   ## hex: #00afff
  green3_2            = 40   ## hex: #00d700
  springGreen3_3      = 41   ## hex: #00d75f
  springGreen2_1      = 42   ## hex: #00d787
  cyan3               = 43   ## hex: #00d7af
  darkTurquoise       = 44   ## hex: #00d7df
  turquoise2          = 45   ## hex: #00d7ff
  green1              = 46   ## hex: #00ff00
  springGreen2_2      = 47   ## hex: #00ff5f
  springGreen1        = 48   ## hex: #00ff87
  mediumSpringGreen   = 49   ## hex: #00ffaf
  cyan2               = 50   ## hex: #00ffd7
  cyan1               = 51   ## hex: #00ffff
  darkRed_1           = 52   ## hex: #5f0000
  deepPink4_1         = 53   ## hex: #5f005f
  purple4_1           = 54   ## hex: #5f0087
  purple4_2           = 55   ## hex: #5f00af
  purple3             = 56   ## hex: #5f00df
  blueViolet          = 57   ## hex: #5f00ff
  orange4_1           = 58   ## hex: #5f5f00
  gray37              = 59   ## hex: #5f5f5f
  mediumPurple4       = 60   ## hex: #5f5f87
  slateBlue3_1        = 61   ## hex: #5f5faf
  slateBlue3_2        = 62   ## hex: #5f5fd7
  royalBlue1          = 63   ## hex: #5f5fff
  chartreuse4         = 64   ## hex: #5f8700
  darkSeaGreen4_1     = 65   ## hex: #5f875f
  paleTurquoise4      = 66   ## hex: #5f8787
  steelBlue           = 67   ## hex: #5f87af
  steelBlue3          = 68   ## hex: #5f87d7
  cornflowerBlue      = 69   ## hex: #5f87ff
  chartreuse3_1       = 70   ## hex: #5faf00
  darkSeaGreen4_2     = 71   ## hex: #5faf5f
  cadetBlue_1         = 72   ## hex: #5faf87
  cadetBlue_2         = 73   ## hex: #5fafaf
  skyBlue3            = 74   ## hex: #5fafd7
  steelBlue1_1        = 75   ## hex: #5fafff
  chartreuse3_2       = 76   ## hex: #5fd000
  paleGreen3_1        = 77   ## hex: #5fd75f
  seaGreen3           = 78   ## hex: #5fd787
  aquamarine3         = 79   ## hex: #5fd7af
  mediumTurquoise     = 80   ## hex: #5fd7d7
  steelBlue1_2        = 81   ## hex: #5fd7ff
  chartreuse2_1       = 82   ## hex: #5fff00
  seaGreen2           = 83   ## hex: #5fff5f
  seaGreen1_1         = 84   ## hex: #5fff87
  seaGreen1_2         = 85   ## hex: #5fffaf
  aquamarine1_1       = 86   ## hex: #5fffd7
  darkSlateGray2      = 87   ## hex: #5fffff
  darkRed_2           = 88   ## hex: #870000
  deepPink4_2         = 89   ## hex: #87005f
  darkMagenta_1       = 90   ## hex: #870087
  darkMagenta_2       = 91   ## hex: #8700af
  darkViolet_1        = 92   ## hex: #8700d7
  purple_2            = 93   ## hex: #8700ff
  orange4_2           = 94   ## hex: #875f00
  lightPink4          = 95   ## hex: #875f5f
  plum4               = 96   ## hex: #875f87
  mediumPurple3_1     = 97   ## hex: #875faf
  mediumPurple3_2     = 98   ## hex: #875fd7
  slateBlue1          = 99   ## hex: #875fff
  yellow4_1           = 100  ## hex: #878700
  wheat4              = 101  ## hex: #87875f
  gray53              = 102  ## hex: #878787
  lightSlategray      = 103  ## hex: #8787af
  mediumPurple        = 104  ## hex: #8787d7
  lightSlateBlue      = 105  ## hex: #8787ff
  yellow4_2           = 106  ## hex: #87af00
  Wheat4              = 107  ## hex: #87af5f
  darkSeaGreen        = 108  ## hex: #87af87
  lightSkyBlue3_1     = 109  ## hex: #87afaf
  lightSkyBlue3_2     = 110  ## hex: #87afd7
  skyBlue2            = 111  ## hex: #87afff
  chartreuse2_2       = 112  ## hex: #87d700
  darkOliveGreen3_1   = 113  ## hex: #87d75f
  paleGreen3_2        = 114  ## hex: #87d787
  darkSeaGreen3_1     = 115  ## hex: #87d7af
  darkSlateGray3      = 116  ## hex: #87d7d7
  skyBlue1            = 117  ## hex: #87d7ff
  chartreuse1         = 118  ## hex: #87ff00
  lightGreen_1        = 119  ## hex: #87ff5f
  lightGreen_2        = 120  ## hex: #87ff87
  paleGreen1_1        = 121  ## hex: #87ffaf
  aquamarine1_2       = 122  ## hex: #87ffd7
  darkSlateGray1      = 123  ## hex: #87ffff
  red3_1              = 124  ## hex: #af0000
  deepPink4           = 125  ## hex: #af005f
  mediumVioletRed     = 126  ## hex: #af0087
  magenta3            = 127  ## hex: #af00af
  darkViolet_2        = 128  ## hex: #af00d7
  purple              = 129  ## hex: #af00ff
  darkOrange3_1       = 130  ## hex: #af5f00
  indianRed_1         = 131  ## hex: #af5f5f
  hotPink3_1          = 132  ## hex: #af5f87
  mediumOrchid3       = 133  ## hex: #af5faf
  mediumOrchid        = 134  ## hex: #af5fd7
  mediumPurple2_1     = 135  ## hex: #af5fff
  darkGoldenrod       = 136  ## hex: #af8700
  lightSalmon3_1      = 137  ## hex: #af875f
  rosyBrown           = 138  ## hex: #af8787
  gray63              = 139  ## hex: #af87af
  mediumPurple2_2     = 140  ## hex: #af87d7
  mediumPurple1       = 141  ## hex: #af87ff
  gold3_1             = 142  ## hex: #afaf00
  darkKhaki           = 143  ## hex: #afaf5f
  navajoWhite3        = 144  ## hex: #afaf87
  gray69              = 145  ## hex: #afafaf
  lightSteelBlue3     = 146  ## hex: #afafd7
  lightSteelBlue      = 147  ## hex: #afafff
  yellow3_1           = 148  ## hex: #afd700
  darkOliveGreen3_2   = 149  ## hex: #afd75f
  darkSeaGreen3_2     = 150  ## hex: #afd787
  darkSeaGreen2_1     = 151  ## hex: #afd7af
  lightCyan3          = 152  ## hex: #afafd7
  lightSkyBlue1       = 153  ## hex: #afd7ff
  greenYellow         = 154  ## hex: #afff00
  darkOliveGreen2     = 155  ## hex: #afff5f
  paleGreen1_2        = 156  ## hex: #afff87
  darkSeaGreen2_2     = 157  ## hex: #afffaf
  darkSeaGreen1_1     = 158  ## hex: #afffd7
  paleTurquoise1      = 159  ## hex: #afffff
  red3_2              = 160  ## hex: #d70000
  deepPink3_1         = 161  ## hex: #d7005f
  deepPink3_2         = 162  ## hex: #d70087
  magenta3_1          = 163  ## hex: #d700af
  magenta3_2          = 164  ## hex: #d700d7
  magenta2_1          = 165  ## hex: #d700ff
  darkOrange3_2       = 166  ## hex: #d75f00
  indianRed_2         = 167  ## hex: #d75f5f
  hotPink3_2          = 168  ## hex: #d75f87
  hotPink2            = 169  ## hex: #d75faf
  orchid              = 170  ## hex: #d75fd7
  mediumOrchid1_1     = 171  ## hex: #d75fff
  orange3             = 172  ## hex: #d78700
  lightSalmon3_2      = 173  ## hex: #d7875f
  lightPink3          = 174  ## hex: #d78787
  pink3               = 175  ## hex: #d787af
  plum3               = 176  ## hex: #d787d7
  violet              = 177  ## hex: #d787ff
  gold3_2             = 178  ## hex: #d7af00
  lightGoldenrod3     = 179  ## hex: #d7af5f
  tan                 = 180  ## hex: #d7af87
  mistyRose3          = 181  ## hex: #d7afaf
  thistle3            = 182  ## hex: #d7afd7
  plum2               = 183  ## hex: #d7afff
  yellow3_2           = 184  ## hex: #d7d700
  khaki3              = 185  ## hex: #d7d75f
  lightGoldenrod2     = 186  ## hex: #d7d787
  lightYellow3        = 187  ## hex: #d7d7af
  gray84              = 188  ## hex: #d7d7d7
  lightSteelBlue1     = 189  ## hex: #d7d7ff
  yellow2             = 190  ## hex: #d7ff00
  darkOliveGreen1_1   = 191  ## hex: #d7ff5f
  darkOliveGreen1_2   = 192  ## hex: #d7ff87
  darkSeaGreen1_2     = 193  ## hex: #d7ffaf
  honeydew2           = 194  ## hex: #d7ffd7
  lightCyan1          = 195  ## hex: #d7ffff
  red1                = 196  ## hex: #ff0000
  deepPink2           = 197  ## hex: #ff005f
  deepPink1_1         = 198  ## hex: #ff0087
  deepPink1_2         = 199  ## hex: #ff00af
  magenta2_2          = 200  ## hex: #ff00d7
  magenta1            = 201  ## hex: #ff00ff
  orangeRed1          = 202  ## hex: #ff5f00
  indianRed1_1        = 203  ## hex: #ff5f5f
  indianRed1_2        = 204  ## hex: #ff5f87
  hotPink1_1          = 205  ## hex: #ff5faf
  hotPink1_2          = 206  ## hex: #ff5fd7
  mediumOrchid1_2     = 207  ## hex: #ff5fff
  darkOrange          = 208  ## hex: #ff8700
  salmon1             = 209  ## hex: #ff875f
  lightCoral          = 210  ## hex: #ff8787
  paleVioletRed1      = 211  ## hex: #ff87af
  orchid2             = 212  ## hex: #ff87d7
  orchid1             = 213  ## hex: #ff87ff
  orange1             = 214  ## hex: #ffaf00
  sandyBrown          = 215  ## hex: #ffaf5f
  lightSalmon1        = 216  ## hex: #ffaf87
  lightPink1          = 217  ## hex: #ffafaf
  pink1               = 218  ## hex: #ffafd7
  plum1               = 219  ## hex: #ffafff
  gold1               = 220  ## hex: #ffd700
  lightGoldenrod2_1   = 221  ## hex: #ffd75f
  lightGoldenrod2_2   = 222  ## hex: #ffd787
  navajoWhite1        = 223  ## hex: #ffd7af
  mistyRose1          = 224  ## hex: #ffd7d7
  thistle1            = 225  ## hex: #ffd7ff
  yellow1             = 226  ## hex: #ffff00
  lightGoldenrod1     = 227  ## hex: #ffff5f
  khaki1              = 228  ## hex: #ffff87
  wheat1              = 229  ## hex: #ffffaf
  cornsilk1           = 230  ## hex: #ffffd7
  gray100             = 231  ## hex: #ffffff
  gray3               = 232  ## hex: #080808
  gray7               = 233  ## hex: #121212
  gray11              = 234  ## hex: #1c1c1c
  gray15              = 235  ## hex: #262626
  gray19              = 236  ## hex: #303030
  gray23              = 237  ## hex: #3a3a3a
  gray27              = 238  ## hex: #444444
  gray30              = 239  ## hex: #4e4e4e
  gray35              = 240  ## hex: #585858
  gray39              = 241  ## hex: #626262
  gray42              = 242  ## hex: #6c6c6c
  gray46              = 243  ## hex: #767676
  gray50              = 244  ## hex: #808080
  gray54              = 245  ## hex: #8a8a8a
  gray58              = 246  ## hex: #949494
  gray62              = 247  ## hex: #9e9e9e
  gray66              = 248  ## hex: #a8a8a8
  gray70              = 249  ## hex: #b2b2b2
  gray74              = 250  ## hex: #bcbcbc
  gray78              = 251  ## hex: #c6c6c6
  gray82              = 252  ## hex: #d0d0d0
  gray85              = 253  ## hex: #dadada
  gray89              = 254  ## hex: #e4e4e4
  gray93              = 255  ## hex: #eeeeee

# Make Color col readable on the background.
# This tries to preserve the color of col as much as
# possible, but adjusts it when needed for
# becoming readable on the background.
# Returns col without changes, if it's already readable.
#proc readableOnBackground*(col: Color, background: Color): Color =
#  template incDiff(val1: untyped, val2: untyped) =
#    if val1 > val2:
#      let newVal = val1 + (val1 - val2) * 1
#      if newVal > 255:
#        val1 = 255
#      else:
#        val1 = newVal
#    elif val1 < val2:
#      let newVal = val1 - (val2 - val1) * 1
#      if newVal < 0:
#        val1 = 0
#      else:
#        val1 = newVal
#
#  let minDiff = 255
#
#  var
#    rgb1 : (int, int, int)
#    rgb2 : (int, int, int)
#  if colorToRGBTable.hasKey(int(col)):
#    rgb1 = colorToRGBTable[int(col)]
#  else:
#    #rgb1 = (128,128,128)
#    rgb1 = (0, 0, 0)
#  if colorToRGBTable.hasKey(int(background)):
#    rgb2 = colorToRGBTable[int(background)]
#  else:
#    #rgb2 = (128,128,128)
#    rgb2 = (0, 0, 0)
#
#  var diff = calcRGBDifference((rgb1[0], rgb1[1], rgb1[2]),
#                               (rgb2[0], rgb2[1], rgb2[2]))
#  if diff < minDiff:
#    let missingDiff = minDiff - diff
#    incDiff(rgb1[0], rgb2[0])
#    incDiff(rgb1[1], rgb2[1])
#    incDiff(rgb1[2], rgb2[2])
#  diff = calcRGBDifference((rgb1[0], rgb1[1], rgb1[2]),
#                           (rgb2[0], rgb2[1], rgb2[2]))
#  if diff < minDiff:
#    return inverseColor(col)
#  return RGBToColor(rgb1[0], rgb1[1], rgb1[2])

type ColorTheme* = enum
  config  = 0
  vscode  = 1
  dark    = 2
  light   = 3
  vivid   = 4

type EditorColorCode* = object
  editorBg*: Option[ColorCode]
  lineNum*: Option[ColorCode]
  lineNumBg*: Option[ColorCode]
  currentLineNum*: Option[ColorCode]
  currentLineNumBg*: Option[ColorCode]
  # status line
  statusLineNormalMode*: Option[ColorCode]
  statusLineNormalModeBg*: Option[ColorCode]
  statusLineModeNormalMode*: Option[ColorCode]
  statusLineModeNormalModeBg*: Option[ColorCode]
  statusLineNormalModeInactive*: Option[ColorCode]
  statusLineNormalModeInactiveBg*: Option[ColorCode]

  statusLineInsertMode*: Option[ColorCode]
  statusLineInsertModeBg*: Option[ColorCode]
  statusLineModeInsertMode*: Option[ColorCode]
  statusLineModeInsertModeBg*: Option[ColorCode]
  statusLineInsertModeInactive*: Option[ColorCode]
  statusLineInsertModeInactiveBg*: Option[ColorCode]

  statusLineVisualMode*: Option[ColorCode]
  statusLineVisualModeBg*: Option[ColorCode]
  statusLineModeVisualMode*: Option[ColorCode]
  statusLineModeVisualModeBg*: Option[ColorCode]
  statusLineVisualModeInactive*: Option[ColorCode]
  statusLineVisualModeInactiveBg*: Option[ColorCode]

  statusLineReplaceMode*: Option[ColorCode]
  statusLineReplaceModeBg*: Option[ColorCode]
  statusLineModeReplaceMode*: Option[ColorCode]
  statusLineModeReplaceModeBg*: Option[ColorCode]
  statusLineReplaceModeInactive*: Option[ColorCode]
  statusLineReplaceModeInactiveBg*: Option[ColorCode]

  statusLineFilerMode*: Option[ColorCode]
  statusLineFilerModeBg*: Option[ColorCode]
  statusLineModeFilerMode*: Option[ColorCode]
  statusLineModeFilerModeBg*: Option[ColorCode]
  statusLineFilerModeInactive*: Option[ColorCode]
  statusLineFilerModeInactiveBg*: Option[ColorCode]

  statusLineExMode*: Option[ColorCode]
  statusLineExModeBg*: Option[ColorCode]
  statusLineModeExMode*: Option[ColorCode]
  statusLineModeExModeBg*: Option[ColorCode]
  statusLineExModeInactive*: Option[ColorCode]
  statusLineExModeInactiveBg*: Option[ColorCode]

  statusLineGitBranch*: Option[ColorCode]
  statusLineGitBranchBg*: Option[ColorCode]
  # tab line
  tab*: Option[ColorCode]
  tabBg*: Option[ColorCode]
  currentTab*: Option[ColorCode]
  currentTabBg*: Option[ColorCode]
  # command bar
  commandBar*: Option[ColorCode]
  commandBarBg*: Option[ColorCode]
  # error message
  errorMessage*: Option[ColorCode]
  errorMessageBg*: Option[ColorCode]
  # search result highlighting
  searchResult*: Option[ColorCode]
  searchResultBg*: Option[ColorCode]
  # selected area in visual mode
  visualMode*: Option[ColorCode]
  visualModeBg*: Option[ColorCode]

  # color scheme
  defaultChar*: Option[ColorCode]
  gtKeyword*: Option[ColorCode]
  gtFunctionName*: Option[ColorCode]
  gtTypeName*: Option[ColorCode]
  gtBoolean*: Option[ColorCode]
  gtStringLit*: Option[ColorCode]
  gtSpecialVar*: Option[ColorCode]
  gtBuiltin*: Option[ColorCode]
  gtDecNumber*: Option[ColorCode]
  gtComment*: Option[ColorCode]
  gtLongComment*: Option[ColorCode]
  gtWhitespace*: Option[ColorCode]
  gtPreprocessor*: Option[ColorCode]
  gtPragma*: Option[ColorCode]

  # filer mode
  currentFile*: Option[ColorCode]
  currentFileBg*: Option[ColorCode]
  file*: Option[ColorCode]
  fileBg*: Option[ColorCode]
  dir*: Option[ColorCode]
  dirBg*: Option[ColorCode]
  pcLink*: Option[ColorCode]
  pcLinkBg*: Option[ColorCode]
  # pop up window
  popUpWindow*: Option[ColorCode]
  popUpWindowBg*: Option[ColorCode]
  popUpWinCurrentLine*: Option[ColorCode]
  popUpWinCurrentLineBg*: Option[ColorCode]
  # replace text highlighting
  replaceText*: Option[ColorCode]
  replaceTextBg*: Option[ColorCode]

  # pair of paren highlighting
  parenText*: Option[ColorCode]
  parenTextBg*: Option[ColorCode]

  # highlight other uses current word
  currentWord*: Option[ColorCode]
  currentWordBg*: Option[ColorCode]

  # highlight full width space
  highlightFullWidthSpace*: Option[ColorCode]
  highlightFullWidthSpaceBg*: Option[ColorCode]

  # highlight trailing spaces
  highlightTrailingSpaces*: Option[ColorCode]
  highlightTrailingSpacesBg*: Option[ColorCode]

  # highlight reserved words
  reservedWord*: Option[ColorCode]
  reservedWordBg*: Option[ColorCode]

  # highlight history manager
  currentHistory*: Option[ColorCode]
  currentHistoryBg*: Option[ColorCode]

  # highlight diff
  addedLine*: Option[ColorCode]
  addedLineBg*: Option[ColorCode]
  deletedLine*: Option[ColorCode]
  deletedLineBg*: Option[ColorCode]

  # configuration mode
  currentSetting*: Option[ColorCode]
  currentSettingBg*: Option[ColorCode]

  # highlight curent line background
  currentLineBg*: Option[ColorCode]

type EditorColorPair* = enum
  lineNum = 1
  currentLineNum = 2
  # status line
  statusLineNormalMode = 3
  statusLineModeNormalMode = 4
  statusLineNormalModeInactive = 5
  statusLineInsertMode = 6
  statusLineModeInsertMode = 7
  statusLineInsertModeInactive = 8
  statusLineVisualMode = 9
  statusLineModeVisualMode = 10
  statusLineVisualModeInactive = 11
  statusLineReplaceMode = 12
  statusLineModeReplaceMode = 13
  statusLineReplaceModeInactive = 14
  statusLineFilerMode = 15
  statusLineModeFilerMode = 16
  statusLineFilerModeInactive = 17
  statusLineExMode = 18
  statusLineModeExMode = 19
  statusLineExModeInactive = 20
  statusLineGitBranch = 21
  # tab lnie
  tab = 22
  # tab line
  currentTab = 23
  # command bar
  commandBar = 24
  # error message
  errorMessage = 25
  # search result highlighting
  searchResult = 26
  # selected area in visual mode
  visualMode = 27

  # color scheme
  defaultChar = 28
  keyword = 29
  functionName = 30
  typeName = 31
  boolean = 32
  specialVar = 33
  builtin = 34
  stringLit = 35
  decNumber = 36
  comment = 37
  longComment = 38
  whitespace = 39
  preprocessor = 40
  pragma = 41

  # filer mode
  currentFile = 42
  file = 43
  dir = 44
  pcLink = 45
  # pop up window
  popUpWindow = 46
  popUpWinCurrentLine = 47
  # replace text highlighting
  replaceText = 48
  # pair of paren highlighting
  parenText = 49
  # highlight other uses current word
  currentWord = 50
  # highlight full width space
  highlightFullWidthSpace = 51
  # highlight trailing spaces
  highlightTrailingSpaces = 52
  # highlight reserved words
  reservedWord = 53
  # highlight history manager
  currentHistory = 54
  # highlight diff
  addedLine = 55
  deletedLine = 56
  # configuration mode
  currentSetting = 57

var ColorThemeTable*: array[ColorTheme, EditorColorCode] = [
  config: EditorColorCode(
    # TODO: Fix color code. (default)
    editorBg: toColorCode("000000"),
    lineNum: toColorCode("8a8a8a"),
    # TODO: Fix color code. (default)
    lineNumBg: toColorCode("000000"),
    currentLineNum: toColorCode("008080"),
    # TODO: Fix color code. (default)
    currentLineNumBg: toColorCode("000000"),
    # statsu bar
    statusLineNormalMode: toColorCode("ffffff"),
    statusLineNormalModeBg: toColorCode("0000ff"),
    statusLineModeNormalMode: toColorCode("000000"),
    statusLineModeNormalModeBg: toColorCode("ffffff"),
    statusLineNormalModeInactive: toColorCode("0000ff"),
    statusLineNormalModeInactiveBg: toColorCode("ffffff"),

    statusLineInsertMode: toColorCode("ffffff"),
    statusLineInsertModeBg: toColorCode("0000ff"),
    statusLineModeInsertMode: toColorCode("000000"),
    statusLineModeInsertModeBg: toColorCode("ffffff"),
    statusLineInsertModeInactive: toColorCode("0000ff"),
    statusLineInsertModeInactiveBg: toColorCode("ffffff"),

    statusLineVisualMode: toColorCode("ffffff"),
    statusLineVisualModeBg: toColorCode("0000ff"),
    statusLineModeVisualMode: toColorCode("000000"),
    statusLineModeVisualModeBg: toColorCode("ffffff"),
    statusLineVisualModeInactive: toColorCode("0000ff"),
    statusLineVisualModeInactiveBg: toColorCode("ffffff"),

    statusLineReplaceMode: toColorCode("ffffff"),
    statusLineReplaceModeBg: toColorCode("0000ff"),
    statusLineModeReplaceMode: toColorCode("000000"),
    statusLineModeReplaceModeBg: toColorCode("ffffff"),
    statusLineReplaceModeInactive: toColorCode("0000ff"),
    statusLineReplaceModeInactiveBg: toColorCode("ffffff"),

    statusLineFilerMode: toColorCode("ffffff"),
    statusLineFilerModeBg: toColorCode("0000ff"),
    statusLineModeFilerMode: toColorCode("000000"),
    statusLineModeFilerModeBg: toColorCode("ffffff"),
    statusLineFilerModeInactive: toColorCode("0000ff"),
    statusLineFilerModeInactiveBg: toColorCode("ffffff"),

    statusLineExMode: toColorCode("ffffff"),
    statusLineExModeBg: toColorCode("0000ff"),
    statusLineModeExMode: toColorCode("000000"),
    statusLineModeExModeBg: toColorCode("ffffff"),
    statusLineExModeInactive: toColorCode("0000ff"),
    statusLineExModeInactiveBg: toColorCode("ffffff"),

    statusLineGitBranch: toColorCode("ffffff"),
    statusLineGitBranchBg: toColorCode("0000ff"),
    # tab line
    tab: toColorCode("ffffff"),
    # TODO: Fix color code. (default)
    tabBg: toColorCode("000000"),
    currentTab: toColorCode("ffffff"),
    currentTabBg: toColorCode("0000ff"),
    # command  bar
    commandBar: toColorCode("ffffff"),
    # TODO: Fix color code. (default)
    commandBarBg: toColorCode("000000"),
    # error message
    errorMessage: toColorCode("ff0000"),
    # TODO: Fix color code. (default)
    errorMessageBg: toColorCode("000000"),
    # search result highlighting
    # TODO: Fix color code. (default)
    searchResult: toColorCode("ffffff"),
    searchResultBg: toColorCode("ff0000"),
    # selected area in visual mode
    visualMode: toColorCode("ffffff"),
    visualModeBg: toColorCode("800080"),

    # color scheme
    defaultChar: toColorCode("ffffff"),
    gtKeyword: toColorCode("87d7ff"),
    gtFunctionName: toColorCode("ffd700"),
    gtTypeName: toColorCode("008000"),
    gtBoolean: toColorCode("ffff00"),
    gtStringLit: toColorCode("ffff00"),
    gtSpecialVar: toColorCode("008000"),
    gtBuiltin: toColorCode("ffff00"),
    gtDecNumber: toColorCode("00ffff"),
    gtComment: toColorCode("808080"),
    gtLongComment: toColorCode("808080"),
    gtWhitespace: toColorCode("808080"),
    gtPreprocessor: toColorCode("008000"),
    gtPragma: toColorCode("ffff00"),

    # filer mode
    currentFile: toColorCode("ffffff"),
    currentFileBg: toColorCode("008080"),
    file: toColorCode("ffffff"),
    # TODO: Fix color code. (default)
    fileBg: toColorCode("000000"),
    dir: toColorCode("0000ff"),
    # TODO: Fix color code. (default)
    dirBg: toColorCode("000000"),
    pcLink: toColorCode("008080"),
    pcLinkBg:toColorCode("000000") ,
    # pop up window
    popUpWindow: toColorCode("ffffff"),
    popUpWindowBg: toColorCode("000000"),
    popUpWinCurrentLine: toColorCode("0000ff"),
    popUpWinCurrentLineBg: toColorCode("000000"),
    # replace text highlighting
    # TODO: Fix color code. (default)
    replaceText: toColorCode("ffffff"),
    replaceTextBg: toColorCode("ff0000"),
    # pair of paren highlighting
    # TODO: Fix color code. (default)
    parenText: toColorCode("ffffff"),
    parenTextBg: toColorCode("0000ff"),
    # highlight other uses current word
    # TODO: Fix color code. (default)
    currentWord: toColorCode("ffffff"),
    currentWordBg: toColorCode("808080"),
    # highlight full width space
    highlightFullWidthSpace: toColorCode("ff0000"),
    highlightFullWidthSpaceBg: toColorCode("ff0000"),
    # highlight trailing spaces
    highlightTrailingSpaces: toColorCode("ff0000"),
    highlightTrailingSpacesBg: toColorCode("ff0000"),
    # highlight reserved words
    reservedWord: toColorCode("ffffff"),
    reservedWordBg: toColorCode("808080"),
    # highlight history manager
    currentHistory: toColorCode("ffffff"),
    currentHistoryBg: toColorCode("008080"),
    # highlight diff
    addedLine: toColorCode("008000"),
    # TODO: Fix color code. (default)
    addedLineBg: toColorCode("000000"),
    deletedLine: toColorCode("ff0000"),
    # TODO: Fix color code. (default)
    deletedLineBg: toColorCode("000000"),
    # configuration mode
    currentSetting: toColorCode("ffffff"),
    currentSettingBg: toColorCode("008080"),
    # Highlight current line background
    currentLineBg: toColorCode("444444")
  ),
  vscode: EditorColorCode(
    # TODO: Fix color code. (default)
    editorBg: toColorCode("000000"),
    lineNum: toColorCode("8a8a8a"),
    # TODO: Fix color code. (default)
    lineNumBg: toColorCode("000000"),
    currentLineNum: toColorCode("008080"),
    # TODO: Fix color code. (default)
    currentLineNumBg: toColorCode("000000"),
    # statsu line
    statusLineNormalMode: toColorCode("ffffff"),
    statusLineNormalModeBg: toColorCode("0000ff"),
    statusLineModeNormalMode: toColorCode("000000"),
    statusLineModeNormalModeBg: toColorCode("ffffff"),
    statusLineNormalModeInactive: toColorCode("0000ff"),
    statusLineNormalModeInactiveBg: toColorCode("ffffff"),

    statusLineInsertMode: toColorCode("ffffff"),
    statusLineInsertModeBg: toColorCode("0000ff"),
    statusLineModeInsertMode: toColorCode("000000"),
    statusLineModeInsertModeBg: toColorCode("ffffff"),
    statusLineInsertModeInactive: toColorCode("0000ff"),
    statusLineInsertModeInactiveBg: toColorCode("ffffff"),

    statusLineVisualMode: toColorCode("ffffff"),
    statusLineVisualModeBg: toColorCode("0000ff"),
    statusLineModeVisualMode: toColorCode("000000"),
    statusLineModeVisualModeBg: toColorCode("ffffff"),
    statusLineVisualModeInactive: toColorCode("0000ff"),
    statusLineVisualModeInactiveBg: toColorCode("ffffff"),

    statusLineReplaceMode: toColorCode("ffffff"),
    statusLineReplaceModeBg: toColorCode("0000ff"),
    statusLineModeReplaceMode: toColorCode("000000"),
    statusLineModeReplaceModeBg: toColorCode("ffffff"),
    statusLineReplaceModeInactive: toColorCode("0000ff"),
    statusLineReplaceModeInactiveBg: toColorCode("ffffff"),

    statusLineFilerMode: toColorCode("ffffff"),
    statusLineFilerModeBg: toColorCode("0000ff"),
    statusLineModeFilerMode: toColorCode("000000"),
    statusLineModeFilerModeBg: toColorCode("ffffff"),
    statusLineFilerModeInactive: toColorCode("0000ff"),
    statusLineFilerModeInactiveBg: toColorCode("ffffff"),

    statusLineExMode: toColorCode("ffffff"),
    statusLineExModeBg: toColorCode("0000ff"),
    statusLineModeExMode: toColorCode("000000"),
    statusLineModeExModeBg: toColorCode("ffffff"),
    statusLineExModeInactive: toColorCode("0000ff"),
    statusLineExModeInactiveBg: toColorCode("ffffff"),

    statusLineGitBranch: toColorCode("ffffff"),
    statusLineGitBranchBg: toColorCode("0000ff"),
    # tab line
    tab: toColorCode("ffffff"),
    # TODO: Fix color code. (default)
    tabBg: toColorCode("000000"),
    currentTab: toColorCode("ffffff"),
    currentTabBg: toColorCode("0000ff"),
    # command  bar
    commandBar: toColorCode("ffffff"),
    # TODO: Fix color code. (default)
    commandBarBg: toColorCode("000000"),
    # error message
    errorMessage: toColorCode("ff0000"),
    # TODO: Fix color code. (default)
    errorMessageBg: toColorCode("000000"),
    # search result highlighting
    # TODO: Fix color code. (default)
    searchResult: toColorCode("ffffff"),
    searchResultBg: toColorCode("ff0000"),
    # selected area in visual mode
    visualMode: toColorCode("ffffff"),
    visualModeBg: toColorCode("800080"),

    # color scheme
    defaultChar: toColorCode("ffffff"),
    gtKeyword: toColorCode("87d7ff"),
    gtFunctionName: toColorCode("ffd700"),
    gtTypeName: toColorCode("008000"),
    gtBoolean: toColorCode("ffff00"),
    gtStringLit: toColorCode("ffff00"),
    gtSpecialVar: toColorCode("008000"),
    gtBuiltin: toColorCode("ffff00"),
    gtDecNumber: toColorCode("00ffff"),
    gtComment: toColorCode("808080"),
    gtLongComment: toColorCode("808080"),
    gtWhitespace: toColorCode("808080"),
    gtPreprocessor: toColorCode("008000"),
    gtPragma: toColorCode("ffff00"),

    # filer mode
    currentFile: toColorCode("ffffff"),
    currentFileBg: toColorCode("008080"),
    file: toColorCode("ffffff"),
    # TODO: Fix color code. (default)
    fileBg: toColorCode("000000"),
    dir: toColorCode("0000ff"),
    # TODO: Fix color code. (default)
    dirBg: toColorCode("000000"),
    pcLink: toColorCode("008080"),
    # TODO: Fix color code. (default)
    pcLinkBg: toColorCode("000000"),
    # pop up window
    popUpWindow: toColorCode("ffffff"),
    popUpWindowBg: toColorCode("000000"),
    popUpWinCurrentLine: toColorCode("0000ff"),
    popUpWinCurrentLineBg: toColorCode("000000"),
    # replace text highlighting
    # TODO: Fix color code. (default)
    replaceText: toColorCode("ffffff"),
    replaceTextBg: toColorCode("ff0000"),
    # pair of paren highlighting
    # TODO: Fix color code. (default)
    parenText: toColorCode("ffffff"),
    parenTextBg: toColorCode("0000ff"),
    # highlight other uses current word
    # TODO: Fix color code. (default)
    currentWord: toColorCode("ffffff"),
    currentWordBg: toColorCode("808080"),
    # highlight full width space
    highlightFullWidthSpace: toColorCode("ff0000"),
    highlightFullWidthSpaceBg: toColorCode("ff0000"),
    # highlight trailing spaces
    highlightTrailingSpaces: toColorCode("ff0000"),
    highlightTrailingSpacesBg: toColorCode("ff0000"),
    # highlight reserved words
    reservedWord: toColorCode("ffffff"),
    reservedWordBg: toColorCode("808080"),
    # highlight history manager
    currentHistory: toColorCode("ffffff"),
    currentHistoryBg: toColorCode("008080"),
    # highlight diff
    addedLine: toColorCode("008000"),
    # TODO: Fix color code. (default)
    addedLineBg: toColorCode("000000"),
    deletedLine: toColorCode("ff0000"),
    # TODO: Fix color code. (default)
    deletedLineBg: toColorCode("000000"),
    # configuration mode
    currentSetting: toColorCode("ffffff"),
    currentSettingBg: toColorCode("008080"),
    # Highlight current line background
    currentLineBg: toColorCode("444444")
  ),
  dark: EditorColorCode(
    # TODO: Fix color code. (default)
    editorBg: toColorCode("000000"),
    lineNum: toColorCode("8a8a8a"),
    # TODO: Fix color code. (default)
    lineNumBg: toColorCode("000000"),
    currentLineNum: toColorCode("008080"),
    # TODO: Fix color code. (default)
    currentLineNumBg: toColorCode("000000"),
    # statsu line
    statusLineNormalMode: toColorCode("ffffff"),
    statusLineNormalModeBg: toColorCode("0000ff"),
    statusLineModeNormalMode: toColorCode("000000"),
    statusLineModeNormalModeBg: toColorCode("ffffff"),
    statusLineNormalModeInactive: toColorCode("0000ff"),
    statusLineNormalModeInactiveBg: toColorCode("ffffff"),

    statusLineInsertMode: toColorCode("ffffff"),
    statusLineInsertModeBg: toColorCode("0000ff"),
    statusLineModeInsertMode: toColorCode("000000"),
    statusLineModeInsertModeBg: toColorCode("ffffff"),
    statusLineInsertModeInactive: toColorCode("0000ff"),
    statusLineInsertModeInactiveBg: toColorCode("ffffff"),

    statusLineVisualMode: toColorCode("ffffff"),
    statusLineVisualModeBg: toColorCode("0000ff"),
    statusLineModeVisualMode: toColorCode("000000"),
    statusLineModeVisualModeBg: toColorCode("ffffff"),
    statusLineVisualModeInactive: toColorCode("0000ff"),
    statusLineVisualModeInactiveBg: toColorCode("ffffff"),

    statusLineReplaceMode: toColorCode("ffffff"),
    statusLineReplaceModeBg: toColorCode("0000ff"),
    statusLineModeReplaceMode: toColorCode("000000"),
    statusLineModeReplaceModeBg: toColorCode("ffffff"),
    statusLineReplaceModeInactive: toColorCode("0000ff"),
    statusLineReplaceModeInactiveBg: toColorCode("ffffff"),

    statusLineFilerMode: toColorCode("ffffff"),
    statusLineFilerModeBg: toColorCode("0000ff"),
    statusLineModeFilerMode: toColorCode("000000"),
    statusLineModeFilerModeBg: toColorCode("ffffff"),
    statusLineFilerModeInactive: toColorCode("0000ff"),
    statusLineFilerModeInactiveBg: toColorCode("ffffff"),

    statusLineExMode: toColorCode("ffffff"),
    statusLineExModeBg: toColorCode("0000ff"),
    statusLineModeExMode: toColorCode("000000"),
    statusLineModeExModeBg: toColorCode("ffffff"),
    statusLineExModeInactive: toColorCode("0000ff"),
    statusLineExModeInactiveBg: toColorCode("ffffff"),

    statusLineGitBranch: toColorCode("ffffff"),
    statusLineGitBranchBg: toColorCode("0000ff"),
    # tab line
    tab: toColorCode("ffffff"),
    # TODO: Fix color code. (default)
    tabBg: toColorCode("000000"),
    currentTab: toColorCode("ffffff"),
    currentTabBg: toColorCode("0000ff"),
    # command bar
    commandBar: toColorCode("ffffff"),
    # TODO: Fix color code. (default)
    commandBarBg: toColorCode("000000"),
    # error message
    errorMessage: toColorCode("ff0000"),
    # TODO: Fix color code. (default)
    errorMessageBg: toColorCode("000000"),
    # search result highlighting
    # TODO: Fix color code. (default)
    searchResult: toColorCode("ffffff"),
    searchResultBg: toColorCode("ff0000"),
    # selected area in visual mode
    visualMode: toColorCode("ffffff"),
    visualModeBg: toColorCode("800080"),

    # color scheme
    defaultChar: toColorCode("ffffff"),
    gtKeyword: toColorCode("87d7ff"),
    gtFunctionName: toColorCode("ffd700"),
    gtTypeName: toColorCode("008000"),
    gtBoolean: toColorCode("ffff00"),
    gtStringLit: toColorCode("ffff00"),
    gtSpecialVar: toColorCode("008000"),
    gtBuiltin: toColorCode("ffff00"),
    gtDecNumber: toColorCode("00ffff"),
    gtComment: toColorCode("808080"),
    gtLongComment: toColorCode("808080"),
    gtWhitespace: toColorCode("808080"),
    gtPreprocessor: toColorCode("008000"),
    gtPragma: toColorCode("ffff00"),

    # filer mode
    currentFile: toColorCode("ffffff"),
    currentFileBg: toColorCode("008080"),
    file: toColorCode("ffffff"),
    # TODO: Fix color code. (default)
    fileBg: toColorCode("000000"),
    dir: toColorCode("0000ff"),
    # TODO: Fix color code. (default)
    dirBg: toColorCode("000000"),
    pcLink: toColorCode("008080"),
    # TODO: Fix color code. (default)
    pcLinkBg: toColorCode("000000"),
    # pop up window
    popUpWindow: toColorCode("ffffff"),
    popUpWindowBg: toColorCode("000000"),
    popUpWinCurrentLine: toColorCode("0000ff"),
    popUpWinCurrentLineBg: toColorCode("000000"),
    # replace text highlighting
    # TODO: Fix color code. (default)
    replaceText: toColorCode("ffffff"),
    replaceTextBg: toColorCode("ff0000"),
    # pair of paren highlighting
    # TODO: Fix color code. (default)
    parenText: toColorCode("ffffff"),
    parenTextBg: toColorCode("0000ff"),
    # highlight other uses current word
    # TODO: Fix color code. (default)
    currentWord: toColorCode("ffffff"),
    currentWordBg: toColorCode("808080"),
    # highlight full width space
    highlightFullWidthSpace: toColorCode("ff0000"),
    highlightFullWidthSpaceBg: toColorCode("ff0000"),
    # highlight trailing spaces
    highlightTrailingSpaces: toColorCode("ff0000"),
    highlightTrailingSpacesBg: toColorCode("ff0000"),
    # highlight reserved words
    reservedWord: toColorCode("ffffff"),
    reservedWordBg: toColorCode("808080"),
    # highlight history manager
    currentHistory: toColorCode("ffffff"),
    currentHistoryBg: toColorCode("008080"),
    # highlight diff
    addedLine: toColorCode("008000"),
    # TODO: Fix color code. (default)
    addedLineBg: toColorCode("000000"),
    deletedLine: toColorCode("ff0000"),
    # TODO: Fix color code. (default)
    deletedLineBg: toColorCode("000000"),
    # configuration mode
    currentSetting: toColorCode("ffffff"),
    currentSettingBg: toColorCode("008080"),
    # Highlight current line background
    currentLineBg: toColorCode("444444")
  ),
  light: EditorColorCode(
    editorBg: toColorCode(""),
    lineNum: toColorCode("8a8a8a"),
    lineNumBg: toColorCode(""),
    currentLineNum: toColorCode("000000"),
    currentLineNumBg: toColorCode(""),
    # statsu line
    statusLineNormalMode: toColorCode("0000ff"),
    statusLineNormalModeBg: toColorCode("8a8a8a"),
    statusLineModeNormalMode: toColorCode("ffffff"),
    statusLineModeNormalModeBg: toColorCode("008080"),
    statusLineNormalModeInactive: toColorCode("8a8a8a"),
    statusLineNormalModeInactiveBg: toColorCode("0000ff"),

    statusLineInsertMode: toColorCode("0000ff"),
    statusLineInsertModeBg: toColorCode("8a8a8a"),
    statusLineModeInsertMode: toColorCode("ffffff"),
    statusLineModeInsertModeBg: toColorCode("008080"),
    statusLineInsertModeInactive: toColorCode("8a8a8a"),
    statusLineInsertModeInactiveBg: toColorCode("0000ff"),

    statusLineVisualMode: toColorCode("0000ff"),
    statusLineVisualModeBg: toColorCode("8a8a8a"),
    statusLineModeVisualMode: toColorCode("ffffff"),
    statusLineModeVisualModeBg: toColorCode("008080"),
    statusLineVisualModeInactive: toColorCode("8a8a8a"),
    statusLineVisualModeInactiveBg: toColorCode("0000ff"),

    statusLineReplaceMode: toColorCode("0000ff"),
    statusLineReplaceModeBg: toColorCode("8a8a8a"),
    statusLineModeReplaceMode: toColorCode("ffffff"),
    statusLineModeReplaceModeBg: toColorCode("008080"),
    statusLineReplaceModeInactive: toColorCode("8a8a8a"),
    statusLineReplaceModeInactiveBg: toColorCode("0000ff"),

    statusLineFilerMode: toColorCode("0000ff"),
    statusLineFilerModeBg: toColorCode("8a8a8a"),
    statusLineModeFilerMode: toColorCode("ffffff"),
    statusLineModeFilerModeBg: toColorCode("008080"),
    statusLineFilerModeInactive: toColorCode("8a8a8a"),
    statusLineFilerModeInactiveBg: toColorCode("0000ff"),

    statusLineExMode: toColorCode("0000ff"),
    statusLineExModeBg: toColorCode("8a8a8a"),
    statusLineModeExMode: toColorCode("ffffff"),
    statusLineModeExModeBg: toColorCode("008080"),
    statusLineExModeInactive: toColorCode("8a8a8a"),
    statusLineExModeInactiveBg: toColorCode("0000ff"),

    statusLineGitBranch: toColorCode("0000ff"),
    statusLineGitBranchBg: toColorCode("8a8a8a"),
    # tab line
    tab: toColorCode("0000ff"),
    tabBg: toColorCode("8a8a8a"),
    currentTab: toColorCode("ffffff"),
    currentTabBg: toColorCode("0000ff"),
    # command bar
    commandBar: toColorCode("000000"),
    commandBarBg: toColorCode(""),
    # error message
    errorMessage: toColorCode("ff0000"),
    errorMessageBg: toColorCode(""),
    # search result highlighting
    searchResult: toColorCode(""),
    searchResultBg: toColorCode("ff0000"),
    # selected area in visual mode
    visualMode: toColorCode("000000"),
    visualModeBg: toColorCode("800080"),

    # color scheme
    defaultChar: toColorCode("ffffff"),
    gtKeyword: toColorCode("5fffaf"),
    gtFunctionName: toColorCode("ffd700"),
    gtTypeName: toColorCode("008000"),
    gtBoolean: toColorCode("ffff00"),
    gtStringLit: toColorCode("800080"),
    gtSpecialVar: toColorCode("008000"),
    gtBuiltin: toColorCode("ffff00"),
    gtDecNumber: toColorCode("00ffff"),
    gtComment: toColorCode("808080"),
    gtLongComment: toColorCode("808080"),
    gtWhitespace: toColorCode("808080"),
    gtPreprocessor: toColorCode("008000"),
    gtPragma: toColorCode("ffff00"),

    # filer mode
    currentFile: toColorCode("000000"),
    currentFileBg: toColorCode("ff0087"),
    file: toColorCode("000000"),
    fileBg: toColorCode(""),
    dir: toColorCode("ff0087"),
    dirBg: toColorCode(""),
    pcLink: toColorCode("008080"),
    pcLinkBg: toColorCode(""),
    # pop up window
    popUpWindow: toColorCode("000000"),
    popUpWindowBg: toColorCode("808080"),
    popUpWinCurrentLine: toColorCode("0000ff"),
    popUpWinCurrentLineBg: toColorCode("808080"),
    # replace text highlighting
    replaceText: toColorCode(""),
    replaceTextBg: toColorCode("ff0000"),
    # pair of paren highlighting
    parenText: toColorCode(""),
    parenTextBg: toColorCode("808080"),
    # highlight other uses current word
    currentWord: toColorCode(""),
    currentWordBg: toColorCode("808080"),
    # highlight full width space
    highlightFullWidthSpace: toColorCode("ff0000"),
    highlightFullWidthSpaceBg: toColorCode("ff0000"),
    # highlight trailing spaces
    highlightTrailingSpaces: toColorCode("ff0000"),
    highlightTrailingSpacesBg: toColorCode("ff0000"),
    # highlight reserved words
    reservedWord: toColorCode("ffffff"),
    reservedWordBg: toColorCode("808080"),
    # highlight history manager
    currentHistory: toColorCode("000000"),
    currentHistoryBg: toColorCode("ff0087"),
    # highlight diff
    addedLine: toColorCode("008000"),
    addedLineBg: toColorCode(""),
    deletedLine: toColorCode("ff0000"),
    deletedLineBg: toColorCode(""),
    # configuration mode
    currentSetting: toColorCode("000000"),
    currentSettingBg: toColorCode("ff0087"),
    # Highlight current line background
    currentLineBg: toColorCode("444444")
  ),
  vivid: EditorColorCode(
    editorBg: toColorCode(""),
    lineNum: toColorCode("8a8a8a"),
    lineNumBg: toColorCode(""),
    currentLineNum: toColorCode("ff0087"),
    currentLineNumBg: toColorCode(""),
    # statsu line
    statusLineNormalMode: toColorCode("000000"),
    statusLineNormalModeBg: toColorCode("ff0087"),
    statusLineModeNormalMode: toColorCode("000000"),
    statusLineModeNormalModeBg: toColorCode("ffffff"),
    statusLineNormalModeInactive: toColorCode("ff0087"),
    statusLineNormalModeInactiveBg: toColorCode("ffffff"),

    statusLineInsertMode: toColorCode("000000"),
    statusLineInsertModeBg: toColorCode("ff0087"),
    statusLineModeInsertMode: toColorCode("000000"),
    statusLineModeInsertModeBg: toColorCode("ffffff"),
    statusLineInsertModeInactive: toColorCode("ff0087"),
    statusLineInsertModeInactiveBg: toColorCode("ffffff"),

    statusLineVisualMode: toColorCode("000000"),
    statusLineVisualModeBg: toColorCode("ff0087"),
    statusLineModeVisualMode: toColorCode("000000"),
    statusLineModeVisualModeBg: toColorCode("ffffff"),
    statusLineVisualModeInactive: toColorCode("ff0087"),
    statusLineVisualModeInactiveBg: toColorCode("ffffff"),

    statusLineReplaceMode: toColorCode("000000"),
    statusLineReplaceModeBg: toColorCode("ff0087"),
    statusLineModeReplaceMode: toColorCode("000000"),
    statusLineModeReplaceModeBg: toColorCode("ffffff"),
    statusLineReplaceModeInactive: toColorCode("ff0087"),
    statusLineReplaceModeInactiveBg: toColorCode("ffffff"),

    statusLineFilerMode: toColorCode("000000"),
    statusLineFilerModeBg: toColorCode("ff0087"),
    statusLineModeFilerMode: toColorCode("000000"),
    statusLineModeFilerModeBg: toColorCode("ffffff"),
    statusLineFilerModeInactive: toColorCode("ff0087"),
    statusLineFilerModeInactiveBg: toColorCode("ffffff"),

    statusLineExMode: toColorCode("000000"),
    statusLineExModeBg: toColorCode("ff0087"),
    statusLineModeExMode: toColorCode("000000"),
    statusLineModeExModeBg: toColorCode("ffffff"),
    statusLineExModeInactive: toColorCode("ff0087"),
    statusLineExModeInactiveBg: toColorCode("ffffff"),

    statusLineGitBranch: toColorCode("ff0087"),
    statusLineGitBranchBg: toColorCode("000000"),
    # tab line
    tab: toColorCode("ffffff"),
    tabBg: toColorCode(""),
    currentTab: toColorCode("000000"),
    currentTabBg: toColorCode("ff0087"),
    # command bar
    commandBar: toColorCode("ffffff"),
    commandBarBg: toColorCode(""),
    # error message
    errorMessage: toColorCode("ff0000"),
    errorMessageBg: toColorCode(""),
    # search result highlighting
    searchResult: toColorCode(""),
    searchResultBg: toColorCode("ff0000"),
    # selected area in visual mode
    visualMode: toColorCode("ffffff"),
    visualModeBg: toColorCode("800080"),

    # color scheme
    defaultChar: toColorCode("ffffff"),
    gtKeyword: toColorCode("ff0087"),
    gtFunctionName: toColorCode("ffd700"),
    gtTypeName: toColorCode("008000"),
    gtBoolean: toColorCode("ffff00"),
    gtStringLit: toColorCode("800080"),
    gtSpecialVar: toColorCode("008000"),
    gtBuiltin: toColorCode("00ffff"),
    gtDecNumber: toColorCode("00ffff"),
    gtComment: toColorCode("808080"),
    gtLongComment: toColorCode("808080"),
    gtWhitespace: toColorCode("808080"),
    gtPreprocessor: toColorCode("008000"),
    gtPragma: toColorCode("00ffff"),

    # filer mode
    currentFile: toColorCode("ffffff"),
    currentFileBg: toColorCode("ff0087"),
    file: toColorCode("ffffff"),
    fileBg: toColorCode(""),
    dir: toColorCode("ff0087"),
    dirBg: toColorCode(""),
    pcLink:  toColorCode("00ffff"),
    pcLinkBg: toColorCode(""),
    # pop up window
    popUpWindow: toColorCode("ffffff"),
    popUpWindowBg: toColorCode("000000"),
    popUpWinCurrentLine: toColorCode("ff0087"),
    popUpWinCurrentLineBg: toColorCode("000000"),
    # replace text highlighting
    replaceText: toColorCode(""),
    replaceTextBg: toColorCode("ff0000"),
    # pair of paren highlighting
    parenText: toColorCode(""),
    parenTextBg: toColorCode("ff0087"),
    # highlight other uses current word
    currentWord: toColorCode(""),
    currentWordBg: toColorCode("808080"),
    # highlight full width space
    highlightFullWidthSpace: toColorCode("ff0000"),
    highlightFullWidthSpaceBg: toColorCode("ff0000"),
    # highlight trailing spaces
    highlightTrailingSpaces: toColorCode("ff0000"),
    highlightTrailingSpacesBg: toColorCode("ff0000"),
    # highlight reserved words
    reservedWord: toColorCode("ff0087"),
    reservedWordBg: toColorCode("000000"),
    # highlight history manager
    currentHistory: toColorCode("ffffff"),
    currentHistoryBg: toColorCode("ff0087"),
    # highlight diff
    addedLine: toColorCode("008000"),
    addedLineBg: toColorCode(""),
    deletedLine: toColorCode("ff0000"),
    deletedLineBg: toColorCode(""),
    # configuration mode
    currentSetting: toColorCode("ffffff"),
    currentSettingBg: toColorCode("ff0087"),
    # Highlight current line background
    currentLineBg: toColorCode("444444")
  ),
]

#proc setColorPair*(colorPair: EditorColorPair | int,
#                   character, background: ColorCode) {.inline.} =
#
#  init_pair(cshort(ord(colorPair)),
#            cshort(ord(character)),
#            cshort(ord(background)))
#
#proc setCursesColor*(editorColor: EditorColorPair) =
#  # Not set when running unit tests
#  when not defined unitTest:
#    start_color()   # enable color
#    use_default_colors()    # set terminal default color
#
#    setColorPair(EditorColorPair.lineNum,
#                 editorColor.lineNum,
#                 editorColor.lineNumBg)
#    setColorPair(EditorColorPair.currentLineNum,
#                 editorColor.currentLineNum,
#                 editorColor.currentLineNumBg)
#    # status line
#    setColorPair(EditorColorPair.statusLineNormalMode,
#                 editorColor.statusLineNormalMode,
#                 editorColor.statusLineNormalModeBg)
#    setColorPair(EditorColorPair.statusLineModeNormalMode,
#                 editorColor.statusLineModeNormalMode,
#                 editorColor.statusLineModeNormalModeBg)
#    setColorPair(EditorColorPair.statusLineNormalModeInactive,
#                 editorColor.statusLineNormalModeInactive,
#                 editorColor.statusLineNormalModeInactiveBg)
#
#    setColorPair(EditorColorPair.statusLineInsertMode,
#                 editorColor.statusLineInsertMode,
#                 editorColor.statusLineInsertModeBg)
#    setColorPair(EditorColorPair.statusLineModeInsertMode,
#                 editorColor.statusLineModeInsertMode,
#                 editorColor.statusLineModeInsertModeBg)
#    setColorPair(EditorColorPair.statusLineInsertModeInactive,
#                 editorColor.statusLineInsertModeInactive,
#                 editorColor.statusLineInsertModeInactiveBg)
#
#    setColorPair(EditorColorPair.statusLineVisualMode,
#                 editorColor.statusLineVisualMode,
#                 editorColor.statusLineVisualModeBg)
#    setColorPair(EditorColorPair.statusLineModeVisualMode,
#                 editorColor.statusLineModeVisualMode,
#                 editorColor.statusLineModeVisualModeBg)
#    setColorPair(EditorColorPair.statusLineVisualModeInactive,
#                 editorColor.statusLineVisualModeInactive,
#                 editorColor.statusLineVisualModeInactiveBg)
#
#    setColorPair(EditorColorPair.statusLineReplaceMode,
#                 editorColor.statusLineReplaceMode,
#                 editorColor.statusLineReplaceModeBg)
#    setColorPair(EditorColorPair.statusLineModeReplaceMode,
#                 editorColor.statusLineModeReplaceMode,
#                 editorColor.statusLineModeReplaceModeBg)
#    setColorPair(EditorColorPair.statusLineReplaceModeInactive,
#                 editorColor.statusLineReplaceModeInactive,
#                 editorColor.statusLineReplaceModeInactiveBg)
#
#    setColorPair(EditorColorPair.statusLineExMode,
#                 editorColor.statusLineExMode,
#                 editorColor.statusLineExModeBg)
#    setColorPair(EditorColorPair.statusLineModeExMode,
#                 editorColor.statusLineModeExMode,
#                 editorColor.statusLineModeExModeBg)
#    setColorPair(EditorColorPair.statusLineExModeInactive,
#                 editorColor.statusLineExModeInactive,
#                 editorColor.statusLineExModeInactiveBg)
#
#    setColorPair(EditorColorPair.statusLineFilerMode,
#                 editorColor.statusLineFilerMode,
#                 editorColor.statusLineFilerModeBg)
#    setColorPair(EditorColorPair.statusLineModeFilerMode,
#                 editorColor.statusLineModeFilerMode,
#                 editorColor.statusLineModeFilerModeBg)
#    setColorPair(EditorColorPair.statusLineFilerModeInactive,
#                 editorColor.statusLineFilerModeInactive,
#                 editorColor.statusLineFilerModeInactiveBg)
#
#    setColorPair(EditorColorPair.statusLineGitBranch,
#                 editorColor.statusLineGitBranch,
#                 editorColor.statusLineGitBranchBg)
#
#    # tab line
#    setColorPair(EditorColorPair.tab, editorColor.tab, editorColor.tabBg)
#    setColorPair(EditorColorPair.currentTab,
#                 editorColor.currentTab,
#                 editorColor.currentTabBg)
#    # command line
#    setColorPair(EditorColorPair.commandBar,
#                 editorColor.commandBar,
#                 editorColor.commandBarBg)
#    # error message
#    setColorPair(EditorColorPair.errorMessage,
#                 editorColor.errorMessage,
#                 editorColor.errorMessageBg)
#    # search result highlighting
#    setColorPair(EditorColorPair.searchResult,
#                 editorColor.searchResult,
#                 editorColor.searchResultBg)
#    # selected area in visual mode
#    setColorPair(EditorColorPair.visualMode,
#                 editorColor.visualMode,
#                 editorColor.visualModeBg)
#
#    # color scheme
#    setColorPair(EditorColorPair.defaultChar,
#                 editorColor.defaultChar,
#                 editorColor.editorBg)
#    setColorPair(EditorColorPair.keyword,
#                 editorColor.gtKeyword,
#                 editorColor.editorBg)
#    setColorPair(EditorColorPair.functionName,
#                 editorColor.gtFunctionName,
#                 editorColor.editorBg)
#    setColorPair(EditorColorPair.typeName,
#                 editorColor.gtTypeName,
#                 editorColor.editorBg)
#    setColorPair(EditorColorPair.boolean,
#                 editorColor.gtBoolean,
#                 editorColor.editorBg)
#    setColorPair(EditorColorPair.specialVar,
#                 editorColor.gtSpecialVar,
#                 editorColor.editorBg)
#    setColorPair(EditorColorPair.builtin,
#                 editorColor.gtBuiltin,
#                 editorColor.editorBg)
#    setColorPair(EditorColorPair.stringLit,
#                 editorColor.gtStringLit,
#                 editorColor.editorBg)
#    setColorPair(EditorColorPair.decNumber,
#                 editorColor.gtDecNumber,
#                 editorColor.editorBg)
#    setColorPair(EditorColorPair.comment,
#                 editorColor.gtComment,
#                 editorColor.editorBg)
#    setColorPair(EditorColorPair.longComment,
#                 editorColor.gtLongComment,
#                 editorColor.editorBg)
#    setColorPair(EditorColorPair.whitespace,
#                 editorColor.gtWhitespace,
#                 editorColor.editorBg)
#    setColorPair(EditorColorPair.preprocessor,
#                 editorColor.gtPreprocessor,
#                 editorColor.editorBg)
#    setColorPair(EditorColorPair.pragma,
#                 editorColor.gtPragma,
#                 editorColor.editorBg)
#
#    # filer
#    setColorPair(EditorColorPair.currentFile,
#                 editorColor.currentFile,
#                 editorColor.currentFileBg)
#    setColorPair(EditorColorPair.file, editorColor.file, editorColor.fileBg)
#    setColorPair(EditorColorPair.dir, editorColor.dir, editorColor.dirBg)
#    setColorPair(EditorColorPair.pcLink, editorColor.pcLink, editorColor.pcLinkBg)
#    # pop up window
#    setColorPair(EditorColorPair.popUpWindow,
#                 editorColor.popUpWindow,
#                 editorColor.popUpWindowBg)
#    setColorPair(EditorColorPair.popUpWinCurrentLine,
#                 editorColor.popUpWinCurrentLine,
#                 editorColor.popUpWinCurrentLineBg)
#
#    # replace text highlighting
#    setColorPair(EditorColorPair.replaceText,
#                 editorColor.replaceText,
#                 editorColor.replaceTextBg)
#
#    # pair of paren highlighting
#    setColorPair(EditorColorPair.parenText,
#                 editorColor.parenText,
#                 editorColor.parenTextBg)
#
#    # highlight other uses current word
#    setColorPair(EditorColorPair.currentWord,
#                 editorColor.currentWord,
#                 editorColor.currentWordBg)
#
#    # highlight full width space
#    setColorPair(EditorColorPair.highlightFullWidthSpace,
#                 editorColor.highlightFullWidthSpace,
#                 editorColor.highlightFullWidthSpaceBg)
#
#    # highlight trailing spaces
#    setColorPair(EditorColorPair.highlightTrailingSpaces,
#                 editorColor.highlightTrailingSpaces,
#                 editorColor.highlightTrailingSpacesBg)
#
#    # highlight reserved words
#    setColorPair(EditorColorPair.reservedWord,
#                 editorColor.reservedWord,
#                 editorColor.reservedWordBg)
#
#    # highlight history manager
#    setColorPair(EditorColorPair.currentHistory,
#                 editorColor.currentHistory,
#                 editorColor.currentHistoryBg)
#
#    # highlight diff
#    setColorPair(EditorColorPair.addedLine,
#                 editorColor.addedLine,
#                 editorColor.addedLineBg)
#    setColorPair(EditorColorPair.deletedLine,
#                 editorColor.deletedLine,
#                 editorColor.deletedLineBg)
#
#    # configuration mode
#    setColorPair(EditorColorPair.currentSetting,
#                 editorColor.currentSetting,
#                 editorColor.currentSettingBg)
#
#proc getColorFromEditorColorPair*(theme: ColorTheme,
#                                  pair: EditorColorPair): (Color, Color) =
#
#  let editorColor = ColorThemeTable[theme]
#
#  case pair
#  of EditorColorPair.lineNum:
#    return (editorColor.lineNum, editorColor.lineNumBg)
#  of EditorColorPair.currentLineNum:
#    return (editorColor.currentLineNum, editorColor.currentLineNumBg)
#  of EditorColorPair.statusLineNormalMode:
#    return (editorColor.statusLineNormalMode,
#            editorColor.statusLineNormalModeBg)
#  of EditorColorPair.statusLineModeNormalMode:
#    return (editorColor.statusLineModeNormalMode,
#            editorColor.statusLineModeNormalModeBg)
#  of EditorColorPair.statusLineNormalModeInactive:
#    return (editorColor.statusLineNormalModeInactive,
#            editorColor.statusLineNormalModeInactiveBg)
#  of EditorColorPair.statusLineInsertMode:
#    return (editorColor.statusLineInsertMode,
#            editorColor.statusLineInsertModeBg)
#  of EditorColorPair.statusLineModeInsertMode:
#    return (editorColor.statusLineModeInsertMode,
#            editorColor.statusLineModeInsertModeBg)
#  of EditorColorPair.statusLineInsertModeInactive:
#    return (editorColor.statusLineInsertModeInactive,
#            editorColor.statusLineInsertModeInactiveBg)
#  of EditorColorPair.statusLineVisualMode:
#    return (editorColor.statusLineVisualMode,
#            editorColor.statusLineVisualModeBg)
#  of EditorColorPair.statusLineModeVisualMode:
#    return (editorColor.statusLineModeVisualMode,
#            editorColor.statusLineModeVisualModeBg)
#  of EditorColorPair.statusLineVisualModeInactive:
#    return (editorColor.statusLineVisualModeInactive,
#            editorColor.statusLineVisualModeInactiveBg)
#  of EditorColorPair.statusLineReplaceMode:
#    return (editorColor.statusLineReplaceMode,
#            editorColor.statusLineReplaceModeBg)
#  of EditorColorPair.statusLineModeReplaceMode:
#    return (editorColor.statusLineModeReplaceMode,
#            editorColor.statusLineModeReplaceModeBg)
#  of EditorColorPair.statusLineReplaceModeInactive:
#    return (editorColor.statusLineReplaceModeInactive,
#            editorColor.statusLineReplaceModeInactiveBg)
#  of EditorColorPair.statusLineExMode:
#    return (editorColor.statusLineExMode, editorColor.statusLineExModeBg)
#  of EditorColorPair.statusLineModeExMode:
#    return (editorColor.statusLineModeExMode,
#            editorColor.statusLineModeExModeBg)
#  of EditorColorPair.statusLineExModeInactive:
#    return (editorColor.statusLineExModeInactive,
#            editorColor.statusLineExModeInactiveBg)
#  of EditorColorPair.statusLineFilerMode:
#    return (editorColor.statusLineFilerMode, editorColor.statusLineFilerModeBg)
#  of EditorColorPair.statusLineModeFilerMode:
#    return (editorColor.statusLineModeFilerMode,
#            editorColor.statusLineModeFilerModeBg)
#  of EditorColorPair.statusLineFilerModeInactive:
#    return (editorColor.statusLineFilerModeInactive,
#            editorColor.statusLineFilerModeInactiveBg)
#  of EditorColorPair.statusLineGitBranch:
#    return (editorColor.statusLineGitBranch, editorColor.statusLineGitBranchBg)
#  of EditorColorPair.tab:
#    return (editorColor.tab, editorColor.tabBg)
#  of EditorColorPair.currentTab:
#    return (editorColor.currentTab, editorColor.currentTabBg)
#  of EditorColorPair.commandBar:
#    return (editorColor.commandBar, editorColor.commandBarBg)
#  of EditorColorPair.errorMessage:
#    return (editorColor.errorMessage, editorColor.errorMessageBg)
#  of EditorColorPair.searchResult:
#    return (editorColor.searchResult, editorColor.searchResultBg)
#  of EditorColorPair.visualMode:
#    return (editorColor.visualMode, editorColor.visualModeBg)
#
#  of EditorColorPair.defaultChar:
#    return (editorColor.defaultChar, editorColor.editorBg)
#  of EditorColorPair.keyword:
#    return (editorColor.gtKeyword, editorColor.editorBg)
#  of EditorColorPair.functionName:
#    return (editorColor.gtFunctionName, editorColor.editorBg)
#  of EditorColorPair.typeName:
#    return (editorColor.gtTypeName, editorColor.editorBg)
#  of EditorColorPair.boolean:
#    return (editorColor.gtBoolean, editorColor.editorBg)
#  of EditorColorPair.specialVar:
#    return (editorColor.gtSpecialVar, editorColor.editorBg)
#  of EditorColorPair.builtin:
#    return (editorColor.gtBuiltin, editorColor.editorBg)
#  of EditorColorPair.stringLit:
#    return (editorColor.gtStringLit, editorColor.editorBg)
#  of EditorColorPair.decNumber:
#    return (editorColor.gtDecNumber, editorColor.editorBg)
#  of EditorColorPair.comment:
#    return (editorColor.gtComment, editorColor.editorBg)
#  of EditorColorPair.longComment:
#    return (editorColor.gtLongComment, editorColor.editorBg)
#  of EditorColorPair.whitespace:
#    return (editorColor.gtWhitespace, editorColor.editorBg)
#  of EditorColorPair.preprocessor:
#    return (editorColor.gtPreprocessor, editorColor.editorBg)
#  of EditorColorPair.pragma:
#    return (editorColor.gtPragma, editorColor.editorBg)
#
#  of EditorColorPair.currentFile:
#    return (editorColor.currentFile, editorColor.currentFileBg)
#  of EditorColorPair.file:
#    return (editorColor.file, editorColor.fileBg)
#  of EditorColorPair.dir:
#    return (editorColor.dir, editorColor.dirBg)
#  of EditorColorPair.pcLink:
#    return (editorColor.pcLink, editorColor.pcLinkBg)
#  of EditorColorPair.popUpWindow:
#    return (editorColor.popUpWindow, editorColor.popUpWindowBg)
#  of EditorColorPair.popUpWinCurrentLine:
#    return (editorColor.popUpWinCurrentLine, editorColor.popUpWinCurrentLineBg)
#  of EditorColorPair.replaceText:
#    return (editorColor.replaceText, editorColor.replaceTextBg)
#  of EditorColorPair.highlightTrailingSpaces:
#    return (editorColor.highlightTrailingSpaces,
#            editorColor.highlightTrailingSpacesBg)
#  of EditorColorPair.reservedWord:
#    return (editorColor.reservedWord, editorColor.reservedWordBg)
#  of EditorColorPair.addedLine:
#    return (editorColor.addedLine, editorColor.addedLineBg)
#  of EditorColorPair.deletedLine:
#    return (editorColor.deletedLine, editorColor.deletedLineBg)
#  of EditorColorPair.currentHistory:
#    return (editorColor.currentHistory, editorColor.currentHistoryBg)
#  of EditorColorPair.currentSetting:
#    return (editorColor.currentSetting, editorColor.currentSettingBg)
#  of EditorColorPair.parenText:
#    return (editorColor.parenText, editorColor.parenTextBg)
#  of EditorColorPair.currentWord:
#    return (editorColor.currentWord, editorColor.currentWordBg)
#  of EditorColorPair.highlightFullWidthSpace:
#    return (editorColor.highlightFullWidthSpace, editorColor.highlightFullWidthSpaceBg)
#
#macro setColor*(theme: ColorTheme,
#                editorColor: string,
#                color: Color): untyped =
#
#    parseStmt(fmt"""
#      ColorThemeTable[{repr(theme)}].{editorColor} = {repr(color)}
#    """)
#
## Environment where only 8 colors can be used
#proc convertToConsoleEnvironmentColor*(theme: ColorTheme) =
#  proc isDefault(color: Color): bool {.inline.} = color == Color.default
#
#  proc isBlack(color: Color): bool =
#    case color:
#      of black, gray3, gray7, gray11, gray15, gray19, gray23, gray27, gray30,
#         gray35, gray39, gray42, gray46, gray50, gray54, gray58, gray62, gray66,
#         gray70, gray74, gray78: true
#      else: false
#
#  # is maroon (red)
#  proc isMaroon(color: Color): bool =
#    case color:
#      of maroon, red, darkRed_1, darkRed_2, red3_1, mediumVioletRed,
#         indianRed_1, red3_2, indianRed_2, red1, orangeRed1, indianRed1_1,
#         indianRed1_2, paleVioletRed1, deepPink4_1, deepPink4_2, deepPink4,
#         magenta3: true
#      else: false
#
#  proc isGreen(color: Color): bool =
#    case color:
#      of green, darkGreen, green4, springGreen4, green3_1, springGreen3_1,
#         lightSeaGreen, green3_2, springGreen3_3, springGreen2_1, green1,
#         springGreen2_2, springGreen1, mediumSpringGreen, darkSeaGreen4_1,
#         darkSeaGreen4_2, paleGreen3_1, seaGreen3, seaGreen2, seaGreen1_1,
#         seaGreen1_2, darkSeaGreen, darkOliveGreen3_1, paleGreen3_2,
#         darkSeaGreen3_1, lightGreen_1, lightGreen_2, paleGreen1_1,
#         darkOliveGreen3_2, darkSeaGreen3_2, darkSeaGreen2_1, greenYellow,
#         darkOliveGreen2, paleGreen1_2, darkSeaGreen2_2, darkSeaGreen1_1,
#         darkOliveGreen1_1, darkOliveGreen1_2, darkSeaGreen1_2,
#         lime, orange4_1, chartreuse4, paleTurquoise4, chartreuse3_1,
#         chartreuse3_2, chartreuse2_1, Wheat4, chartreuse2_2, chartreuse1,
#         darkGoldenrod, lightSalmon3_1, rosyBrown, gold3_1, darkKhaki,
#         navajoWhite3: true
#      else: false
#
#  # is olive (yellow)
#  proc isOlive(color: Color): bool =
#    case color:
#      of olive,
#         yellow, yellow4_1, yellow4_2, yellow3_1, yellow3_2, lightYellow3,
#         yellow2, yellow1, orange4_2, lightPink4, plum4, wheat4, darkOrange3_1,
#         darkOrange3_2, orange3, lightSalmon3_2, gold3_2, lightGoldenrod3, tan,
#         mistyRose3, khaki3, lightGoldenrod2, darkOrange, salmon1, orange1,
#         sandyBrown, lightSalmon1, gold1, lightGoldenrod2_1, lightGoldenrod2_2,
#         navajoWhite1, lightGoldenrod1, khaki1, wheat1, cornsilk1: true
#      else: false
#
#  # is navy (blue)
#  proc isNavy(color: Color): bool =
#    case color:
#      of navy,
#         blue, navyBlue, darkBlue, blue3_1, blue3_2, blue1, deepSkyBlue4_1,
#         deepSkyBlue4_2, deepSkyBlue4_3, dodgerBlue3_1, dodgerBlue3_2,
#         deepSkyBlue3_1, deepSkyBlue3_2, dodgerBlue1, deepSkyBlue2,
#         deepSkyBlue1, blueViolet, slateBlue3_1, slateBlue3_2, royalBlue1,
#         steelBlue, steelBlue3, cornflowerBlue, cadetBlue_1, cadetBlue_2,
#         skyBlue3, steelBlue1_1, steelBlue1_2, slateBlue1, lightSlateBlue,
#         lightSkyBlue3_1, lightSkyBlue3_2, skyBlue2, skyBlue1,
#         lightSteelBlue3, lightSteelBlue, lightSkyBlue1, lightSteelBlue1,
#         aqua, darkTurquoise, turquoise2, aquamarine1_1: true
#      else: false
#
#  proc isPurple(color: Color): bool =
#    case color:
#      of purple_1,
#         purple4_1, purple4_2, purple3, mediumPurple4, purple_2,
#         mediumPurple3_1, mediumPurple3_2, mediumPurple, purple,
#         mediumPurple2_1, mediumPurple2_2, mediumPurple1, fuchsia,
#         darkMagenta_1, darkMagenta_2, darkViolet_1, darkViolet_2, hotPink3_1,
#         mediumOrchid3, mediumOrchid, deepPink3_1, deepPink3_2, magenta3_1,
#         magenta3_2, magenta2_1, hotPink3_2, hotPink2, orchid, mediumOrchid1_1,
#         lightPink3, pink3, plum3, violet, thistle3, plum2, deepPink2,
#         deepPink1_1, deepPink1_2, magenta2_2, magenta1, hotPink1_1,
#         hotPink1_2, mediumOrchid1_2, lightCoral, orchid2, orchid1, lightPink1,
#         pink1, plum1, mistyRose1, thistle1: true
#      else: false
#
#  # is teal (cyan)
#  proc isTeal(color: Color): bool =
#    case color:
#      of teal, darkCyan, cyan3, cyan2, cyan1, lightCyan3, lightCyan1,
#         turquoise4, turquoise2, aquamarine3, mediumTurquoise, aquamarine1_2,
#         paleTurquoise1, honeydew2: true
#      else: false
#
#  for name, color in ColorThemeTable[theme].fieldPairs:
#    if isDefault(color):
#      setColor(theme, name, Color.default)
#    elif isBlack(color):
#      setColor(theme, name, Color.black)
#    elif isMaroon(color):
#      setColor(theme, name, Color.maroon)
#    elif isGreen(color):
#      setColor(theme, name, Color.green)
#    elif isOlive(color):
#      setColor(theme, name, Color.olive)
#    elif isNavy(color):
#      setColor(theme, name, Color.navy)
#    elif isPurple(color):
#      setColor(theme, name, Color.purple_1)
#    elif isTeal(color):
#      setColor(theme, name, Color.teal)
#    else:
#      # is silver (white)
#      setColor(theme, name, Color.silver)
#
#    setCursesColor(ColorThemeTable[theme])
