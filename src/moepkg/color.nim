import std/[strutils, tables, macros, strformat]
import pkg/ncurses

# maps annotations of the enum to a hexToColor table
macro mapAnnotationToTable(args: varargs[untyped]): untyped =
  var lines: seq[string]
  let original = args[0]
  # read source file at compile time into string
  # and put all ines in the lines sequence
  for line in staticRead(original.lineInfoObj.filename).splitLines():
    lines.add line
  let typeDef           = original[0][0]
  let enumTy            = typeDef[2]
  let tableIdent        = ident"hexToColorTable"
  let tableReverseIdent = ident"colorToHexTable"
  let tableRGBIdent     = ident"colorToRGBTable"

  # create filling lines for the hexToColor table
  var fillTable: NimNode = quote do: discard
  for child in enumTy:
    if child.kind != nnkEnumFieldDef:
      continue
    let line = lines[child.lineInfoObj.line-1].strip()
    # check for annotations
    if "##" notIn line:
      continue

    let hexCode = line[line.len()-6..line.len()-1]
    let red     = parseHexInt(hexCode[0..1])
    let green   = parseHexInt(hexCode[2..3])
    let blue    = parseHexInt(hexCode[4..5])
    if hexCode.len() == 6:
      let intLit = child[1]
      fillTable = quote do:
        `fillTable`
        `tableIdent`[`hexCode`]       = `intLit`
        `tableReverseIdent`[`intLit`] = `hexCode`
        `tableRGBIdent`[`intLit`]     = (`red`, `green`, `blue`)

  # emit source code
  return quote do:
    var `tableIdent`        = initTable[string, int]()
    var `tableReverseIdent` = initTable[int, string]()
    var `tableRGBIdent`     = initTable[int, (int, int, int)]()
    `original`
    `fillTable`

mapAnnotationToTable:
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

# Calculates the difference between two rgb colors
template calcRGBDifference(col1: (int, int, int), col2: (int, int, int)): int =
  abs(col1[0] - col2[0]) + abs(col1[1] - col2[1]) + abs(col1[2] - col2[2])

# Converts an rgb value to a color,
# the closest color is approximated
proc RGBToColor*(red, green, blue: int): Color =
  var closestColor     : Color
  var lowestDifference : int    = 100000
  for key, value in colorToRGBTable:
    let keyRed   = value[0]
    let keyGreen = value[1]
    let keyBlue  = value[2]
    let difference = calcRGBDifference((red, green, blue),
                                       (keyRed, keyGreen, keyBlue))
    if difference < lowestDifference:
      lowestDifference = difference
      closestColor     = Color(key)
      if difference == 0:
        break
  return closestColor

# Note: this takes a hex string of the form
# f0f0f0 as opposed to #f0f0f0
proc hexToColor*(hex: string): Color =
  let red   = parseHexInt(hex[0..1])
  let green = parseHexInt(hex[2..3])
  let blue  = parseHexInt(hex[4..5])
  return RGBToColor(red, green, blue)

# Returns the closest inverse Color
# for col.
proc inverseColor*(col: Color): Color =
  if not colorToHexTable.hasKey(int(col)):
    return Color.default

  var rgb      = colorToRGBTable[int(col)]
  rgb[0] = abs(rgb[0] - 255)
  rgb[1] = abs(rgb[1] - 255)
  rgb[2] = abs(rgb[2] - 255)
  return RGBToColor(rgb[0], rgb[1], rgb[2])

# Make Color col readable on the background.
# This tries to preserve the color of col as much as
# possible, but adjusts it when needed for
# becoming readable on the background.
# Returns col without changes, if it's already readable.
proc readableOnBackground*(col: Color, background: Color): Color =
  template incDiff(val1: untyped, val2: untyped) =
    if val1 > val2:
      let newVal = val1 + (val1 - val2) * 1
      if newVal > 255:
        val1 = 255
      else:
        val1 = newVal
    elif val1 < val2:
      let newVal = val1 - (val2 - val1) * 1
      if newVal < 0:
        val1 = 0
      else:
        val1 = newVal

  let minDiff = 255

  var
    rgb1 : (int, int, int)
    rgb2 : (int, int, int)
  if colorToRGBTable.hasKey(int(col)):
    rgb1 = colorToRGBTable[int(col)]
  else:
    #rgb1 = (128,128,128)
    rgb1 = (0, 0, 0)
  if colorToRGBTable.hasKey(int(background)):
    rgb2 = colorToRGBTable[int(background)]
  else:
    #rgb2 = (128,128,128)
    rgb2 = (0, 0, 0)

  var diff = calcRGBDifference((rgb1[0], rgb1[1], rgb1[2]),
                               (rgb2[0], rgb2[1], rgb2[2]))
  if diff < minDiff:
    let missingDiff = minDiff - diff
    incDiff(rgb1[0], rgb2[0])
    incDiff(rgb1[1], rgb2[1])
    incDiff(rgb1[2], rgb2[2])
  diff = calcRGBDifference((rgb1[0], rgb1[1], rgb1[2]),
                           (rgb2[0], rgb2[1], rgb2[2]))
  if diff < minDiff:
    return inverseColor(col)
  return RGBToColor(rgb1[0], rgb1[1], rgb1[2])

type ColorTheme* = enum
  config  = 0
  vscode  = 1
  dark    = 2
  light   = 3
  vivid   = 4

type EditorColor* = object
  editorBg*: Color
  lineNum*: Color
  lineNumBg*: Color
  currentLineNum*: Color
  currentLineNumBg*: Color
  # status line
  statusLineNormalMode*: Color
  statusLineNormalModeBg*: Color
  statusLineModeNormalMode*: Color
  statusLineModeNormalModeBg*: Color
  statusLineNormalModeInactive*: Color
  statusLineNormalModeInactiveBg*: Color

  statusLineInsertMode*: Color
  statusLineInsertModeBg*: Color
  statusLineModeInsertMode*: Color
  statusLineModeInsertModeBg*: Color
  statusLineInsertModeInactive*: Color
  statusLineInsertModeInactiveBg*: Color

  statusLineVisualMode*: Color
  statusLineVisualModeBg*: Color
  statusLineModeVisualMode*: Color
  statusLineModeVisualModeBg*: Color
  statusLineVisualModeInactive*: Color
  statusLineVisualModeInactiveBg*: Color

  statusLineReplaceMode*: Color
  statusLineReplaceModeBg*: Color
  statusLineModeReplaceMode*: Color
  statusLineModeReplaceModeBg*: Color
  statusLineReplaceModeInactive*: Color
  statusLineReplaceModeInactiveBg*: Color

  statusLineFilerMode*: Color
  statusLineFilerModeBg*: Color
  statusLineModeFilerMode*: Color
  statusLineModeFilerModeBg*: Color
  statusLineFilerModeInactive*: Color
  statusLineFilerModeInactiveBg*: Color

  statusLineExMode*: Color
  statusLineExModeBg*: Color
  statusLineModeExMode*: Color
  statusLineModeExModeBg*: Color
  statusLineExModeInactive*: Color
  statusLineExModeInactiveBg*: Color

  statusLineGitBranch*: Color
  statusLineGitBranchBg*: Color
  # tab line
  tab*: Color
  tabBg*: Color
  currentTab*: Color
  currentTabBg*: Color
  # command bar
  commandBar*: Color
  commandBarBg*: Color
  # error message
  errorMessage*: Color
  errorMessageBg*: Color
  # search result highlighting
  searchResult*: Color
  searchResultBg*: Color
  # selected area in visual mode
  visualMode*: Color
  visualModeBg*: Color

  # color scheme
  defaultChar*: Color
  gtKeyword*: Color
  gtFunctionName*: Color
  gtTypeName*: Color
  gtBoolean*: Color
  gtStringLit*: Color
  gtSpecialVar*: Color
  gtBuiltin*: Color
  gtDecNumber*: Color
  gtComment*: Color
  gtLongComment*: Color
  gtWhitespace*: Color
  gtPreprocessor*: Color
  gtPragma*: Color

  # filer mode
  currentFile*: Color
  currentFileBg*: Color
  file*: Color
  fileBg*: Color
  dir*: Color
  dirBg*: Color
  pcLink*: Color
  pcLinkBg*: Color
  # pop up window
  popUpWindow*: Color
  popUpWindowBg*: Color
  popUpWinCurrentLine*: Color
  popUpWinCurrentLineBg*: Color
  # replace text highlighting
  replaceText*: Color
  replaceTextBg*: Color

  # pair of paren highlighting
  parenText*: Color
  parenTextBg*: Color

  # highlight other uses current word
  currentWord*: Color
  currentWordBg*: Color

  # highlight full width space
  highlightFullWidthSpace*: Color
  highlightFullWidthSpaceBg*: Color

  # highlight trailing spaces
  highlightTrailingSpaces*: Color
  highlightTrailingSpacesBg*: Color

  # highlight reserved words
  reservedWord*: Color
  reservedWordBg*: Color

  # highlight history manager
  currentHistory*: Color
  currentHistoryBg*: Color

  # highlight diff
  addedLine*: Color
  addedLineBg*: Color
  deletedLine*: Color
  deletedLineBg*: Color

  # configuration mode
  currentSetting*: Color
  currentSettingBg*: Color

  # highlight curent line background
  currentLineBg*: Color

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

var ColorThemeTable*: array[ColorTheme, EditorColor] = [
  config: EditorColor(
    editorBg: default,
    lineNum: gray54,
    lineNumBg: default,
    currentLineNum: teal,
    currentLineNumBg: default,
    # statsu bar
    statusLineNormalMode: white,
    statusLineNormalModeBg: blue,
    statusLineModeNormalMode: black,
    statusLineModeNormalModeBg: white,
    statusLineNormalModeInactive: blue,
    statusLineNormalModeInactiveBg: white,

    statusLineInsertMode: white,
    statusLineInsertModeBg: blue,
    statusLineModeInsertMode: black,
    statusLineModeInsertModeBg: white,
    statusLineInsertModeInactive: blue,
    statusLineInsertModeInactiveBg: white,

    statusLineVisualMode: white,
    statusLineVisualModeBg: blue,
    statusLineModeVisualMode: black,
    statusLineModeVisualModeBg: white,
    statusLineVisualModeInactive: blue,
    statusLineVisualModeInactiveBg: white,

    statusLineReplaceMode: white,
    statusLineReplaceModeBg: blue,
    statusLineModeReplaceMode: black,
    statusLineModeReplaceModeBg: white,
    statusLineReplaceModeInactive: blue,
    statusLineReplaceModeInactiveBg: white,

    statusLineFilerMode: white,
    statusLineFilerModeBg: blue,
    statusLineModeFilerMode: black,
    statusLineModeFilerModeBg: white,
    statusLineFilerModeInactive: blue,
    statusLineFilerModeInactiveBg: white,

    statusLineExMode: white,
    statusLineExModeBg: blue,
    statusLineModeExMode: black,
    statusLineModeExModeBg: white,
    statusLineExModeInactive: blue,
    statusLineExModeInactiveBg: white,

    statusLineGitBranch: white,
    statusLineGitBranchBg: blue,
    # tab line
    tab: white,
    tabBg: default,
    currentTab: white,
    currentTabBg: blue,
    # command  bar
    commandBar: gray100,
    commandBarBg: default,
    # error message
    errorMessage: red,
    errorMessageBg: default,
    # search result highlighting
    searchResult: default,
    searchResultBg: red,
    # selected area in visual mode
    visualMode: gray100,
    visualModeBg: purple_1,

    # color scheme
    defaultChar: white,
    gtKeyword: skyBlue1,
    gtFunctionName: gold1,
    gtTypeName: green,
    gtBoolean: yellow,
    gtStringLit: yellow,
    gtSpecialVar: green,
    gtBuiltin: yellow,
    gtDecNumber: aqua,
    gtComment: gray,
    gtLongComment: gray,
    gtWhitespace: gray,
    gtPreprocessor: green,
    gtPragma: yellow,

    # filer mode
    currentFile: gray100,
    currentFileBg: teal,
    file: gray100,
    fileBg: default,
    dir: blue,
    dirBg: default,
    pcLink: teal,
    pcLinkBg: default,
    # pop up window
    popUpWindow: gray100,
    popUpWindowBg: black,
    popUpWinCurrentLine: blue,
    popUpWinCurrentLineBg: black,
    # replace text highlighting
    replaceText: default,
    replaceTextBg: red,
    # pair of paren highlighting
    parenText: default,
    parenTextBg: blue,
    # highlight other uses current word
    currentWord: default,
    currentWordBg: gray,
    # highlight full width space
    highlightFullWidthSpace: red,
    highlightFullWidthSpaceBg: red,
    # highlight trailing spaces
    highlightTrailingSpaces: red,
    highlightTrailingSpacesBg: red,
    # highlight reserved words
    reservedWord: white,
    reservedWordBg: gray,
    # highlight history manager
    currentHistory: gray100,
    currentHistoryBg: teal,
    # highlight diff
    addedLine: green,
    addedLineBg: default,
    deletedLine: red,
    deletedLineBg: default,
    # configuration mode
    currentSetting: gray100,
    currentSettingBg: teal,
    # Highlight current line background
    currentLineBg: gray27
  ),
  vscode: EditorColor(
    editorBg: default,
    lineNum: gray54,
    lineNumBg: default,
    currentLineNum: teal,
    currentLineNumBg: default,
    # statsu line
    statusLineNormalMode: white,
    statusLineNormalModeBg: blue,
    statusLineModeNormalMode: black,
    statusLineModeNormalModeBg: white,
    statusLineNormalModeInactive: blue,
    statusLineNormalModeInactiveBg: white,

    statusLineInsertMode: white,
    statusLineInsertModeBg: blue,
    statusLineModeInsertMode: black,
    statusLineModeInsertModeBg: white,
    statusLineInsertModeInactive: blue,
    statusLineInsertModeInactiveBg: white,

    statusLineVisualMode: white,
    statusLineVisualModeBg: blue,
    statusLineModeVisualMode: black,
    statusLineModeVisualModeBg: white,
    statusLineVisualModeInactive: blue,
    statusLineVisualModeInactiveBg: white,

    statusLineReplaceMode: white,
    statusLineReplaceModeBg: blue,
    statusLineModeReplaceMode: black,
    statusLineModeReplaceModeBg: white,
    statusLineReplaceModeInactive: blue,
    statusLineReplaceModeInactiveBg: white,

    statusLineFilerMode: white,
    statusLineFilerModeBg: blue,
    statusLineModeFilerMode: black,
    statusLineModeFilerModeBg: white,
    statusLineFilerModeInactive: blue,
    statusLineFilerModeInactiveBg: white,

    statusLineExMode: white,
    statusLineExModeBg: blue,
    statusLineModeExMode: black,
    statusLineModeExModeBg: white,
    statusLineExModeInactive: blue,
    statusLineExModeInactiveBg: white,

    statusLineGitBranch: white,
    statusLineGitBranchBg: blue,
    # tab line
    tab: white,
    tabBg: default,
    currentTab: white,
    currentTabBg: blue,
    # command  bar
    commandBar: gray100,
    commandBarBg: default,
    # error message
    errorMessage: red,
    errorMessageBg: default,
    # search result highlighting
    searchResult: default,
    searchResultBg: red,
    # selected area in visual mode
    visualMode: gray100,
    visualModeBg: purple_1,

    # color scheme
    defaultChar: white,
    gtKeyword: skyBlue1,
    gtFunctionName: gold1,
    gtTypeName: green,
    gtBoolean: yellow,
    gtStringLit: yellow,
    gtSpecialVar: green,
    gtBuiltin: yellow,
    gtDecNumber: aqua,
    gtComment: gray,
    gtLongComment: gray,
    gtWhitespace: gray,
    gtPreprocessor: green,
    gtPragma: yellow,

    # filer mode
    currentFile: gray100,
    currentFileBg: teal,
    file: gray100,
    fileBg: default,
    dir: blue,
    dirBg: default,
    pcLink: teal,
    pcLinkBg: default,
    # pop up window
    popUpWindow: gray100,
    popUpWindowBg: black,
    popUpWinCurrentLine: blue,
    popUpWinCurrentLineBg: black,
    # replace text highlighting
    replaceText: default,
    replaceTextBg: red,
    # pair of paren highlighting
    parenText: default,
    parenTextBg: blue,
    # highlight other uses current word
    currentWord: default,
    currentWordBg: gray,
    # highlight full width space
    highlightFullWidthSpace: red,
    highlightFullWidthSpaceBg: red,
    # highlight trailing spaces
    highlightTrailingSpaces: red,
    highlightTrailingSpacesBg: red,
    # highlight reserved words
    reservedWord: white,
    reservedWordBg: gray,
    # highlight history manager
    currentHistory: gray100,
    currentHistoryBg: teal,
    # highlight diff
    addedLine: green,
    addedLineBg: default,
    deletedLine: red,
    deletedLineBg: default,
    # configuration mode
    currentSetting: gray100,
    currentSettingBg: teal,
    # Highlight current line background
    currentLineBg: gray27
  ),
  dark: EditorColor(
    editorBg: default,
    lineNum: gray54,
    lineNumBg: default,
    currentLineNum: teal,
    currentLineNumBg: default,
    # statsu line
    statusLineNormalMode: white,
    statusLineNormalModeBg: blue,
    statusLineModeNormalMode: black,
    statusLineModeNormalModeBg: white,
    statusLineNormalModeInactive: blue,
    statusLineNormalModeInactiveBg: white,

    statusLineInsertMode: white,
    statusLineInsertModeBg: blue,
    statusLineModeInsertMode: black,
    statusLineModeInsertModeBg: white,
    statusLineInsertModeInactive: blue,
    statusLineInsertModeInactiveBg: white,

    statusLineVisualMode: white,
    statusLineVisualModeBg: blue,
    statusLineModeVisualMode: black,
    statusLineModeVisualModeBg: white,
    statusLineVisualModeInactive: blue,
    statusLineVisualModeInactiveBg: white,

    statusLineReplaceMode: white,
    statusLineReplaceModeBg: blue,
    statusLineModeReplaceMode: black,
    statusLineModeReplaceModeBg: white,
    statusLineReplaceModeInactive: blue,
    statusLineReplaceModeInactiveBg: white,

    statusLineFilerMode: white,
    statusLineFilerModeBg: blue,
    statusLineModeFilerMode: black,
    statusLineModeFilerModeBg: white,
    statusLineFilerModeInactive: blue,
    statusLineFilerModeInactiveBg: white,

    statusLineExMode: white,
    statusLineExModeBg: blue,
    statusLineModeExMode: black,
    statusLineModeExModeBg: white,
    statusLineExModeInactive: blue,
    statusLineExModeInactiveBg: white,

    statusLineGitBranch: white,
    statusLineGitBranchBg: blue,
    # tab line
    tab: white,
    tabBg: default,
    currentTab: white,
    currentTabBg: blue,
    # command bar
    commandBar: gray100,
    commandBarBg: default,
    # error message
    errorMessage: red,
    errorMessageBg: default,
    # search result highlighting
    searchResult: default,
    searchResultBg: red,
    # selected area in visual mode
    visualMode: gray100,
    visualModeBg: purple_1,

    # color scheme
    defaultChar: white,
    gtKeyword: skyBlue1,
    gtFunctionName: gold1,
    gtTypeName: green,
    gtBoolean: yellow,
    gtStringLit: yellow,
    gtSpecialVar: green,
    gtBuiltin: yellow,
    gtDecNumber: aqua,
    gtComment: gray,
    gtLongComment: gray,
    gtWhitespace: gray,
    gtPreprocessor: green,
    gtPragma: yellow,

    # filer mode
    currentFile: gray100,
    currentFileBg: teal,
    file: gray100,
    fileBg: default,
    dir: blue,
    dirBg: default,
    pcLink: teal,
    pcLinkBg: default,
    # pop up window
    popUpWindow: gray100,
    popUpWindowBg: black,
    popUpWinCurrentLine: blue,
    popUpWinCurrentLineBg: black,
    # replace text highlighting
    replaceText: default,
    replaceTextBg: red,
    # pair of paren highlighting
    parenText: default,
    parenTextBg: blue,
    # highlight other uses current word
    currentWord: default,
    currentWordBg: gray,
    # highlight full width space
    highlightFullWidthSpace: red,
    highlightFullWidthSpaceBg: red,
    # highlight trailing spaces
    highlightTrailingSpaces: red,
    highlightTrailingSpacesBg: red,
    # highlight reserved words
    reservedWord: white,
    reservedWordBg: gray,
    # highlight history manager
    currentHistory: gray100,
    currentHistoryBg: teal,
    # highlight diff
    addedLine: green,
    addedLineBg: default,
    deletedLine: red,
    deletedLineBg: default,
    # configuration mode
    currentSetting: gray100,
    currentSettingBg: teal,
    # Highlight current line background
    currentLineBg: gray27
  ),
  light: EditorColor(
    editorBg: default,
    lineNum: gray54,
    lineNumBg: default,
    currentLineNum: black,
    currentLineNumBg: default,
    # statsu line
    statusLineNormalMode: blue,
    statusLineNormalModeBg: gray54,
    statusLineModeNormalMode: white,
    statusLineModeNormalModeBg: teal,
    statusLineNormalModeInactive: gray54,
    statusLineNormalModeInactiveBg: blue,

    statusLineInsertMode: blue,
    statusLineInsertModeBg: gray54,
    statusLineModeInsertMode: white,
    statusLineModeInsertModeBg: teal,
    statusLineInsertModeInactive: gray54,
    statusLineInsertModeInactiveBg: blue,

    statusLineVisualMode: blue,
    statusLineVisualModeBg: gray54,
    statusLineModeVisualMode: white,
    statusLineModeVisualModeBg: teal,
    statusLineVisualModeInactive: gray54,
    statusLineVisualModeInactiveBg: blue,

    statusLineReplaceMode: blue,
    statusLineReplaceModeBg: gray54,
    statusLineModeReplaceMode: white,
    statusLineModeReplaceModeBg: teal,
    statusLineReplaceModeInactive: gray54,
    statusLineReplaceModeInactiveBg: blue,

    statusLineFilerMode: blue,
    statusLineFilerModeBg: gray54,
    statusLineModeFilerMode: white,
    statusLineModeFilerModeBg: teal,
    statusLineFilerModeInactive: gray54,
    statusLineFilerModeInactiveBg: blue,

    statusLineExMode: blue,
    statusLineExModeBg: gray54,
    statusLineModeExMode: white,
    statusLineModeExModeBg: teal,
    statusLineExModeInactive: gray54,
    statusLineExModeInactiveBg: blue,

    statusLineGitBranch: blue,
    statusLineGitBranchBg: gray54,
    # tab line
    tab: blue,
    tabBg: gray54,
    currentTab: white,
    currentTabBg: blue,
    # command bar
    commandBar: black,
    commandBarBg: default,
    # error message
    errorMessage: red,
    errorMessageBg: default,
    # search result highlighting
    searchResult: default,
    searchResultBg: red,
    # selected area in visual mode
    visualMode: black,
    visualModeBg: purple_1,

    # color scheme
    defaultChar: gray100,
    gtKeyword: seaGreen1_2,
    gtFunctionName: gold1,
    gtTypeName: green,
    gtBoolean: yellow,
    gtStringLit: purple_1,
    gtSpecialVar: green,
    gtBuiltin: yellow,
    gtDecNumber: aqua,
    gtComment: gray,
    gtLongComment: gray,
    gtWhitespace: gray,
    gtPreprocessor: green,
    gtPragma: yellow,

    # filer mode
    currentFile: black,
    currentFileBg: deepPink1_1,
    file: black,
    fileBg: default,
    dir: deepPink1_1,
    dirBg: default,
    pcLink: teal,
    pcLinkBg: default,
    # pop up window
    popUpWindow: black,
    popUpWindowBg: gray,
    popUpWinCurrentLine: blue,
    popUpWinCurrentLineBg: gray,
    # replace text highlighting
    replaceText: default,
    replaceTextBg: red,
    # pair of paren highlighting
    parenText: default,
    parenTextBg: gray,
    # highlight other uses current word
    currentWord: default,
    currentWordBg: gray,
    # highlight full width space
    highlightFullWidthSpace: red,
    highlightFullWidthSpaceBg: red,
    # highlight trailing spaces
    highlightTrailingSpaces: red,
    highlightTrailingSpacesBg: red,
    # highlight reserved words
    reservedWord: white,
    reservedWordBg: gray,
    # highlight history manager
    currentHistory: black,
    currentHistoryBg: deepPink1_1,
    # highlight diff
    addedLine: green,
    addedLineBg: default,
    deletedLine: red,
    deletedLineBg: default,
    # configuration mode
    currentSetting: black,
    currentSettingBg: deepPink1_1,
    # Highlight current line background
    currentLineBg: gray27
  ),
  vivid: EditorColor(
    editorBg: default,
    lineNum: gray54,
    lineNumBg: default,
    currentLineNum: deepPink1_1,
    currentLineNumBg: default,
    # statsu line
    statusLineNormalMode: black,
    statusLineNormalModeBg: deepPink1_1,
    statusLineModeNormalMode: black,
    statusLineModeNormalModeBg: gray100,
    statusLineNormalModeInactive: deepPink1_1,
    statusLineNormalModeInactiveBg: white,

    statusLineInsertMode: black,
    statusLineInsertModeBg: deepPink1_1,
    statusLineModeInsertMode: black,
    statusLineModeInsertModeBg: gray100,
    statusLineInsertModeInactive: deepPink1_1,
    statusLineInsertModeInactiveBg: white,

    statusLineVisualMode: black,
    statusLineVisualModeBg: deepPink1_1,
    statusLineModeVisualMode: black,
    statusLineModeVisualModeBg: gray100,
    statusLineVisualModeInactive: deepPink1_1,
    statusLineVisualModeInactiveBg: white,

    statusLineReplaceMode: black,
    statusLineReplaceModeBg: deepPink1_1,
    statusLineModeReplaceMode: black,
    statusLineModeReplaceModeBg: gray100,
    statusLineReplaceModeInactive: deepPink1_1,
    statusLineReplaceModeInactiveBg: white,

    statusLineFilerMode: black,
    statusLineFilerModeBg: deepPink1_1,
    statusLineModeFilerMode: black,
    statusLineModeFilerModeBg: gray100,
    statusLineFilerModeInactive: deepPink1_1,
    statusLineFilerModeInactiveBg: white,

    statusLineExMode: black,
    statusLineExModeBg: deepPink1_1,
    statusLineModeExMode: black,
    statusLineModeExModeBg: gray100,
    statusLineExModeInactive: deepPink1_1,
    statusLineExModeInactiveBg: white,

    statusLineGitBranch: deepPink1_1,
    statusLineGitBranchBg: black,
    # tab line
    tab: white,
    tabBg: default,
    currentTab: black,
    currentTabBg: deepPink1_1,
    # command bar
    commandBar: gray100,
    commandBarBg: default,
    # error message
    errorMessage: red,
    errorMessageBg: default,
    # search result highlighting
    searchResult: default,
    searchResultBg: red,
    # selected area in visual mode
    visualMode: gray100,
    visualModeBg: purple_1,

    # color scheme
    defaultChar: gray100,
    gtKeyword: deepPink1_1,
    gtFunctionName: gold1,
    gtTypeName: green,
    gtBoolean: yellow,
    gtStringLit: purple_1,
    gtSpecialVar: green,
    gtBuiltin: aqua,
    gtDecNumber: aqua,
    gtComment: gray,
    gtLongComment: gray,
    gtWhitespace: gray,
    gtPreprocessor: green,
    gtPragma: aqua,

    # filer mode
    currentFile: gray100,
    currentFileBg: deepPink1_1,
    file: gray100,
    fileBg: default,
    dir: deepPink1_1,
    dirBg: default,
    pcLink: cyan1,
    pcLinkBg: default,
    # pop up window
    popUpWindow: gray100,
    popUpWindowBg: black,
    popUpWinCurrentLine: deepPink1_1,
    popUpWinCurrentLineBg: black,
    # replace text highlighting
    replaceText: default,
    replaceTextBg: red,
    # pair of paren highlighting
    parenText: default,
    parenTextBg: deepPink1_1,
    # highlight other uses current word
    currentWord: default,
    currentWordBg: gray,
    # highlight full width space
    highlightFullWidthSpace: red,
    highlightFullWidthSpaceBg: red,
    # highlight trailing spaces
    highlightTrailingSpaces: red,
    highlightTrailingSpacesBg: red,
    # highlight reserved words
    reservedWord: deepPink1_1,
    reservedWordBg: black,
    # highlight history manager
    currentHistory: gray100,
    currentHistoryBg: deepPink1_1,
    # highlight diff
    addedLine: green,
    addedLineBg: default,
    deletedLine: red,
    deletedLineBg: default,
    # configuration mode
    currentSetting: gray100,
    currentSettingBg: deepPink1_1,
    # Highlight current line background
    currentLineBg: gray27
  ),
]

proc setColorPair*(colorPair: EditorColorPair | int,
                   character, background: Color) {.inline.} =

  init_pair(cshort(ord(colorPair)),
            cshort(ord(character)),
            cshort(ord(background)))

proc setCursesColor*(editorColor: EditorColor) =
  # Not set when running unit tests
  when not defined unitTest:
    start_color()   # enable color
    use_default_colors()    # set terminal default color

    setColorPair(EditorColorPair.lineNum,
                 editorColor.lineNum,
                 editorColor.lineNumBg)
    setColorPair(EditorColorPair.currentLineNum,
                 editorColor.currentLineNum,
                 editorColor.currentLineNumBg)
    # status line
    setColorPair(EditorColorPair.statusLineNormalMode,
                 editorColor.statusLineNormalMode,
                 editorColor.statusLineNormalModeBg)
    setColorPair(EditorColorPair.statusLineModeNormalMode,
                 editorColor.statusLineModeNormalMode,
                 editorColor.statusLineModeNormalModeBg)
    setColorPair(EditorColorPair.statusLineNormalModeInactive,
                 editorColor.statusLineNormalModeInactive,
                 editorColor.statusLineNormalModeInactiveBg)

    setColorPair(EditorColorPair.statusLineInsertMode,
                 editorColor.statusLineInsertMode,
                 editorColor.statusLineInsertModeBg)
    setColorPair(EditorColorPair.statusLineModeInsertMode,
                 editorColor.statusLineModeInsertMode,
                 editorColor.statusLineModeInsertModeBg)
    setColorPair(EditorColorPair.statusLineInsertModeInactive,
                 editorColor.statusLineInsertModeInactive,
                 editorColor.statusLineInsertModeInactiveBg)

    setColorPair(EditorColorPair.statusLineVisualMode,
                 editorColor.statusLineVisualMode,
                 editorColor.statusLineVisualModeBg)
    setColorPair(EditorColorPair.statusLineModeVisualMode,
                 editorColor.statusLineModeVisualMode,
                 editorColor.statusLineModeVisualModeBg)
    setColorPair(EditorColorPair.statusLineVisualModeInactive,
                 editorColor.statusLineVisualModeInactive,
                 editorColor.statusLineVisualModeInactiveBg)

    setColorPair(EditorColorPair.statusLineReplaceMode,
                 editorColor.statusLineReplaceMode,
                 editorColor.statusLineReplaceModeBg)
    setColorPair(EditorColorPair.statusLineModeReplaceMode,
                 editorColor.statusLineModeReplaceMode,
                 editorColor.statusLineModeReplaceModeBg)
    setColorPair(EditorColorPair.statusLineReplaceModeInactive,
                 editorColor.statusLineReplaceModeInactive,
                 editorColor.statusLineReplaceModeInactiveBg)

    setColorPair(EditorColorPair.statusLineExMode,
                 editorColor.statusLineExMode,
                 editorColor.statusLineExModeBg)
    setColorPair(EditorColorPair.statusLineModeExMode,
                 editorColor.statusLineModeExMode,
                 editorColor.statusLineModeExModeBg)
    setColorPair(EditorColorPair.statusLineExModeInactive,
                 editorColor.statusLineExModeInactive,
                 editorColor.statusLineExModeInactiveBg)

    setColorPair(EditorColorPair.statusLineFilerMode,
                 editorColor.statusLineFilerMode,
                 editorColor.statusLineFilerModeBg)
    setColorPair(EditorColorPair.statusLineModeFilerMode,
                 editorColor.statusLineModeFilerMode,
                 editorColor.statusLineModeFilerModeBg)
    setColorPair(EditorColorPair.statusLineFilerModeInactive,
                 editorColor.statusLineFilerModeInactive,
                 editorColor.statusLineFilerModeInactiveBg)

    setColorPair(EditorColorPair.statusLineGitBranch,
                 editorColor.statusLineGitBranch,
                 editorColor.statusLineGitBranchBg)

    # tab line
    setColorPair(EditorColorPair.tab, editorColor.tab, editorColor.tabBg)
    setColorPair(EditorColorPair.currentTab,
                 editorColor.currentTab,
                 editorColor.currentTabBg)
    # command line
    setColorPair(EditorColorPair.commandBar,
                 editorColor.commandBar,
                 editorColor.commandBarBg)
    # error message
    setColorPair(EditorColorPair.errorMessage,
                 editorColor.errorMessage,
                 editorColor.errorMessageBg)
    # search result highlighting
    setColorPair(EditorColorPair.searchResult,
                 editorColor.searchResult,
                 editorColor.searchResultBg)
    # selected area in visual mode
    setColorPair(EditorColorPair.visualMode,
                 editorColor.visualMode,
                 editorColor.visualModeBg)

    # color scheme
    setColorPair(EditorColorPair.defaultChar,
                 editorColor.defaultChar,
                 editorColor.editorBg)
    setColorPair(EditorColorPair.keyword,
                 editorColor.gtKeyword,
                 editorColor.editorBg)
    setColorPair(EditorColorPair.functionName,
                 editorColor.gtFunctionName,
                 editorColor.editorBg)
    setColorPair(EditorColorPair.typeName,
                 editorColor.gtTypeName,
                 editorColor.editorBg)
    setColorPair(EditorColorPair.boolean,
                 editorColor.gtBoolean,
                 editorColor.editorBg)
    setColorPair(EditorColorPair.specialVar,
                 editorColor.gtSpecialVar,
                 editorColor.editorBg)
    setColorPair(EditorColorPair.builtin,
                 editorColor.gtBuiltin,
                 editorColor.editorBg)
    setColorPair(EditorColorPair.stringLit,
                 editorColor.gtStringLit,
                 editorColor.editorBg)
    setColorPair(EditorColorPair.decNumber,
                 editorColor.gtDecNumber,
                 editorColor.editorBg)
    setColorPair(EditorColorPair.comment,
                 editorColor.gtComment,
                 editorColor.editorBg)
    setColorPair(EditorColorPair.longComment,
                 editorColor.gtLongComment,
                 editorColor.editorBg)
    setColorPair(EditorColorPair.whitespace,
                 editorColor.gtWhitespace,
                 editorColor.editorBg)
    setColorPair(EditorColorPair.preprocessor,
                 editorColor.gtPreprocessor,
                 editorColor.editorBg)
    setColorPair(EditorColorPair.pragma,
                 editorColor.gtPragma,
                 editorColor.editorBg)

    # filer
    setColorPair(EditorColorPair.currentFile,
                 editorColor.currentFile,
                 editorColor.currentFileBg)
    setColorPair(EditorColorPair.file, editorColor.file, editorColor.fileBg)
    setColorPair(EditorColorPair.dir, editorColor.dir, editorColor.dirBg)
    setColorPair(EditorColorPair.pcLink, editorColor.pcLink, editorColor.pcLinkBg)
    # pop up window
    setColorPair(EditorColorPair.popUpWindow,
                 editorColor.popUpWindow,
                 editorColor.popUpWindowBg)
    setColorPair(EditorColorPair.popUpWinCurrentLine,
                 editorColor.popUpWinCurrentLine,
                 editorColor.popUpWinCurrentLineBg)

    # replace text highlighting
    setColorPair(EditorColorPair.replaceText,
                 editorColor.replaceText,
                 editorColor.replaceTextBg)

    # pair of paren highlighting
    setColorPair(EditorColorPair.parenText,
                 editorColor.parenText,
                 editorColor.parenTextBg)

    # highlight other uses current word
    setColorPair(EditorColorPair.currentWord,
                 editorColor.currentWord,
                 editorColor.currentWordBg)

    # highlight full width space
    setColorPair(EditorColorPair.highlightFullWidthSpace,
                 editorColor.highlightFullWidthSpace,
                 editorColor.highlightFullWidthSpaceBg)

    # highlight trailing spaces
    setColorPair(EditorColorPair.highlightTrailingSpaces,
                 editorColor.highlightTrailingSpaces,
                 editorColor.highlightTrailingSpacesBg)

    # highlight reserved words
    setColorPair(EditorColorPair.reservedWord,
                 editorColor.reservedWord,
                 editorColor.reservedWordBg)

    # highlight history manager
    setColorPair(EditorColorPair.currentHistory,
                 editorColor.currentHistory,
                 editorColor.currentHistoryBg)

    # highlight diff
    setColorPair(EditorColorPair.addedLine,
                 editorColor.addedLine,
                 editorColor.addedLineBg)
    setColorPair(EditorColorPair.deletedLine,
                 editorColor.deletedLine,
                 editorColor.deletedLineBg)

    # configuration mode
    setColorPair(EditorColorPair.currentSetting,
                 editorColor.currentSetting,
                 editorColor.currentSettingBg)

proc getColorFromEditorColorPair*(theme: ColorTheme,
                                  pair: EditorColorPair): (Color, Color) =

  let editorColor = ColorThemeTable[theme]

  case pair
  of EditorColorPair.lineNum:
    return (editorColor.lineNum, editorColor.lineNumBg)
  of EditorColorPair.currentLineNum:
    return (editorColor.currentLineNum, editorColor.currentLineNumBg)
  of EditorColorPair.statusLineNormalMode:
    return (editorColor.statusLineNormalMode,
            editorColor.statusLineNormalModeBg)
  of EditorColorPair.statusLineModeNormalMode:
    return (editorColor.statusLineModeNormalMode,
            editorColor.statusLineModeNormalModeBg)
  of EditorColorPair.statusLineNormalModeInactive:
    return (editorColor.statusLineNormalModeInactive,
            editorColor.statusLineNormalModeInactiveBg)
  of EditorColorPair.statusLineInsertMode:
    return (editorColor.statusLineInsertMode,
            editorColor.statusLineInsertModeBg)
  of EditorColorPair.statusLineModeInsertMode:
    return (editorColor.statusLineModeInsertMode,
            editorColor.statusLineModeInsertModeBg)
  of EditorColorPair.statusLineInsertModeInactive:
    return (editorColor.statusLineInsertModeInactive,
            editorColor.statusLineInsertModeInactiveBg)
  of EditorColorPair.statusLineVisualMode:
    return (editorColor.statusLineVisualMode,
            editorColor.statusLineVisualModeBg)
  of EditorColorPair.statusLineModeVisualMode:
    return (editorColor.statusLineModeVisualMode,
            editorColor.statusLineModeVisualModeBg)
  of EditorColorPair.statusLineVisualModeInactive:
    return (editorColor.statusLineVisualModeInactive,
            editorColor.statusLineVisualModeInactiveBg)
  of EditorColorPair.statusLineReplaceMode:
    return (editorColor.statusLineReplaceMode,
            editorColor.statusLineReplaceModeBg)
  of EditorColorPair.statusLineModeReplaceMode:
    return (editorColor.statusLineModeReplaceMode,
            editorColor.statusLineModeReplaceModeBg)
  of EditorColorPair.statusLineReplaceModeInactive:
    return (editorColor.statusLineReplaceModeInactive,
            editorColor.statusLineReplaceModeInactiveBg)
  of EditorColorPair.statusLineExMode:
    return (editorColor.statusLineExMode, editorColor.statusLineExModeBg)
  of EditorColorPair.statusLineModeExMode:
    return (editorColor.statusLineModeExMode,
            editorColor.statusLineModeExModeBg)
  of EditorColorPair.statusLineExModeInactive:
    return (editorColor.statusLineExModeInactive,
            editorColor.statusLineExModeInactiveBg)
  of EditorColorPair.statusLineFilerMode:
    return (editorColor.statusLineFilerMode, editorColor.statusLineFilerModeBg)
  of EditorColorPair.statusLineModeFilerMode:
    return (editorColor.statusLineModeFilerMode,
            editorColor.statusLineModeFilerModeBg)
  of EditorColorPair.statusLineFilerModeInactive:
    return (editorColor.statusLineFilerModeInactive,
            editorColor.statusLineFilerModeInactiveBg)
  of EditorColorPair.statusLineGitBranch:
    return (editorColor.statusLineGitBranch, editorColor.statusLineGitBranchBg)
  of EditorColorPair.tab:
    return (editorColor.tab, editorColor.tabBg)
  of EditorColorPair.currentTab:
    return (editorColor.currentTab, editorColor.currentTabBg)
  of EditorColorPair.commandBar:
    return (editorColor.commandBar, editorColor.commandBarBg)
  of EditorColorPair.errorMessage:
    return (editorColor.errorMessage, editorColor.errorMessageBg)
  of EditorColorPair.searchResult:
    return (editorColor.searchResult, editorColor.searchResultBg)
  of EditorColorPair.visualMode:
    return (editorColor.visualMode, editorColor.visualModeBg)

  of EditorColorPair.defaultChar:
    return (editorColor.defaultChar, editorColor.editorBg)
  of EditorColorPair.keyword:
    return (editorColor.gtKeyword, editorColor.editorBg)
  of EditorColorPair.functionName:
    return (editorColor.gtFunctionName, editorColor.editorBg)
  of EditorColorPair.typeName:
    return (editorColor.gtTypeName, editorColor.editorBg)
  of EditorColorPair.boolean:
    return (editorColor.gtBoolean, editorColor.editorBg)
  of EditorColorPair.specialVar:
    return (editorColor.gtSpecialVar, editorColor.editorBg)
  of EditorColorPair.builtin:
    return (editorColor.gtBuiltin, editorColor.editorBg)
  of EditorColorPair.stringLit:
    return (editorColor.gtStringLit, editorColor.editorBg)
  of EditorColorPair.decNumber:
    return (editorColor.gtDecNumber, editorColor.editorBg)
  of EditorColorPair.comment:
    return (editorColor.gtComment, editorColor.editorBg)
  of EditorColorPair.longComment:
    return (editorColor.gtLongComment, editorColor.editorBg)
  of EditorColorPair.whitespace:
    return (editorColor.gtWhitespace, editorColor.editorBg)
  of EditorColorPair.preprocessor:
    return (editorColor.gtPreprocessor, editorColor.editorBg)
  of EditorColorPair.pragma:
    return (editorColor.gtPragma, editorColor.editorBg)

  of EditorColorPair.currentFile:
    return (editorColor.currentFile, editorColor.currentFileBg)
  of EditorColorPair.file:
    return (editorColor.file, editorColor.fileBg)
  of EditorColorPair.dir:
    return (editorColor.dir, editorColor.dirBg)
  of EditorColorPair.pcLink:
    return (editorColor.pcLink, editorColor.pcLinkBg)
  of EditorColorPair.popUpWindow:
    return (editorColor.popUpWindow, editorColor.popUpWindowBg)
  of EditorColorPair.popUpWinCurrentLine:
    return (editorColor.popUpWinCurrentLine, editorColor.popUpWinCurrentLineBg)
  of EditorColorPair.replaceText:
    return (editorColor.replaceText, editorColor.replaceTextBg)
  of EditorColorPair.highlightTrailingSpaces:
    return (editorColor.highlightTrailingSpaces,
            editorColor.highlightTrailingSpacesBg)
  of EditorColorPair.reservedWord:
    return (editorColor.reservedWord, editorColor.reservedWordBg)
  of EditorColorPair.addedLine:
    return (editorColor.addedLine, editorColor.addedLineBg)
  of EditorColorPair.deletedLine:
    return (editorColor.deletedLine, editorColor.deletedLineBg)
  of EditorColorPair.currentHistory:
    return (editorColor.currentHistory, editorColor.currentHistoryBg)
  of EditorColorPair.currentSetting:
    return (editorColor.currentSetting, editorColor.currentSettingBg)
  of EditorColorPair.parenText:
    return (editorColor.parenText, editorColor.parenTextBg)
  of EditorColorPair.currentWord:
    return (editorColor.currentWord, editorColor.currentWordBg)
  of EditorColorPair.highlightFullWidthSpace:
    return (editorColor.highlightFullWidthSpace, editorColor.highlightFullWidthSpaceBg)

macro setColor*(theme: ColorTheme,
                editorColor: string,
                color: Color): untyped =

    parseStmt(fmt"""
      ColorThemeTable[{repr(theme)}].{editorColor} = {repr(color)}
    """)

# Environment where only 8 colors can be used
proc convertToConsoleEnvironmentColor*(theme: ColorTheme) =
  proc isDefault(color: Color): bool {.inline.} = color == Color.default

  proc isBlack(color: Color): bool =
    case color:
      of black, gray3, gray7, gray11, gray15, gray19, gray23, gray27, gray30,
         gray35, gray39, gray42, gray46, gray50, gray54, gray58, gray62, gray66,
         gray70, gray74, gray78: true
      else: false

  # is maroon (red)
  proc isMaroon(color: Color): bool =
    case color:
      of maroon, red, darkRed_1, darkRed_2, red3_1, mediumVioletRed,
         indianRed_1, red3_2, indianRed_2, red1, orangeRed1, indianRed1_1,
         indianRed1_2, paleVioletRed1, deepPink4_1, deepPink4_2, deepPink4,
         magenta3: true
      else: false

  proc isGreen(color: Color): bool =
    case color:
      of green, darkGreen, green4, springGreen4, green3_1, springGreen3_1,
         lightSeaGreen, green3_2, springGreen3_3, springGreen2_1, green1,
         springGreen2_2, springGreen1, mediumSpringGreen, darkSeaGreen4_1,
         darkSeaGreen4_2, paleGreen3_1, seaGreen3, seaGreen2, seaGreen1_1,
         seaGreen1_2, darkSeaGreen, darkOliveGreen3_1, paleGreen3_2,
         darkSeaGreen3_1, lightGreen_1, lightGreen_2, paleGreen1_1,
         darkOliveGreen3_2, darkSeaGreen3_2, darkSeaGreen2_1, greenYellow,
         darkOliveGreen2, paleGreen1_2, darkSeaGreen2_2, darkSeaGreen1_1,
         darkOliveGreen1_1, darkOliveGreen1_2, darkSeaGreen1_2,
         lime, orange4_1, chartreuse4, paleTurquoise4, chartreuse3_1,
         chartreuse3_2, chartreuse2_1, Wheat4, chartreuse2_2, chartreuse1,
         darkGoldenrod, lightSalmon3_1, rosyBrown, gold3_1, darkKhaki,
         navajoWhite3: true
      else: false

  # is olive (yellow)
  proc isOlive(color: Color): bool =
    case color:
      of olive,
         yellow, yellow4_1, yellow4_2, yellow3_1, yellow3_2, lightYellow3,
         yellow2, yellow1, orange4_2, lightPink4, plum4, wheat4, darkOrange3_1,
         darkOrange3_2, orange3, lightSalmon3_2, gold3_2, lightGoldenrod3, tan,
         mistyRose3, khaki3, lightGoldenrod2, darkOrange, salmon1, orange1,
         sandyBrown, lightSalmon1, gold1, lightGoldenrod2_1, lightGoldenrod2_2,
         navajoWhite1, lightGoldenrod1, khaki1, wheat1, cornsilk1: true
      else: false

  # is navy (blue)
  proc isNavy(color: Color): bool =
    case color:
      of navy,
         blue, navyBlue, darkBlue, blue3_1, blue3_2, blue1, deepSkyBlue4_1,
         deepSkyBlue4_2, deepSkyBlue4_3, dodgerBlue3_1, dodgerBlue3_2,
         deepSkyBlue3_1, deepSkyBlue3_2, dodgerBlue1, deepSkyBlue2,
         deepSkyBlue1, blueViolet, slateBlue3_1, slateBlue3_2, royalBlue1,
         steelBlue, steelBlue3, cornflowerBlue, cadetBlue_1, cadetBlue_2,
         skyBlue3, steelBlue1_1, steelBlue1_2, slateBlue1, lightSlateBlue,
         lightSkyBlue3_1, lightSkyBlue3_2, skyBlue2, skyBlue1,
         lightSteelBlue3, lightSteelBlue, lightSkyBlue1, lightSteelBlue1,
         aqua, darkTurquoise, turquoise2, aquamarine1_1: true
      else: false

  proc isPurple(color: Color): bool =
    case color:
      of purple_1,
         purple4_1, purple4_2, purple3, mediumPurple4, purple_2,
         mediumPurple3_1, mediumPurple3_2, mediumPurple, purple,
         mediumPurple2_1, mediumPurple2_2, mediumPurple1, fuchsia,
         darkMagenta_1, darkMagenta_2, darkViolet_1, darkViolet_2, hotPink3_1,
         mediumOrchid3, mediumOrchid, deepPink3_1, deepPink3_2, magenta3_1,
         magenta3_2, magenta2_1, hotPink3_2, hotPink2, orchid, mediumOrchid1_1,
         lightPink3, pink3, plum3, violet, thistle3, plum2, deepPink2,
         deepPink1_1, deepPink1_2, magenta2_2, magenta1, hotPink1_1,
         hotPink1_2, mediumOrchid1_2, lightCoral, orchid2, orchid1, lightPink1,
         pink1, plum1, mistyRose1, thistle1: true
      else: false

  # is teal (cyan)
  proc isTeal(color: Color): bool =
    case color:
      of teal, darkCyan, cyan3, cyan2, cyan1, lightCyan3, lightCyan1,
         turquoise4, turquoise2, aquamarine3, mediumTurquoise, aquamarine1_2,
         paleTurquoise1, honeydew2: true
      else: false

  for name, color in ColorThemeTable[theme].fieldPairs:
    if isDefault(color):
      setColor(theme, name, Color.default)
    elif isBlack(color):
      setColor(theme, name, Color.black)
    elif isMaroon(color):
      setColor(theme, name, Color.maroon)
    elif isGreen(color):
      setColor(theme, name, Color.green)
    elif isOlive(color):
      setColor(theme, name, Color.olive)
    elif isNavy(color):
      setColor(theme, name, Color.navy)
    elif isPurple(color):
      setColor(theme, name, Color.purple_1)
    elif isTeal(color):
      setColor(theme, name, Color.teal)
    else:
      # is silver (white)
      setColor(theme, name, Color.silver)

    setCursesColor(ColorThemeTable[theme])
