#[###################### GNU General Public License 3.0 ######################]#
#                                                                              #
#  Copyright (C) 2017─2023 Shuhei Nogawa                                       #
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
    if "##" notin line:
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
    purple1            = 5    ## hex: #800080
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
    blue31             = 19   ## hex: #0000af
    blue32             = 20   ## hex: #0000d7
    blue1               = 21   ## hex: #0000ff
    darkGreen           = 22   ## hex: #005f00
    deepSkyBlue41      = 23   ## hex: #005f5f
    deepSkyBlue42      = 24   ## hex: #005f87
    deepSkyBlue43      = 25   ## hex: #005faf
    dodgerBlue31       = 26   ## hex: #005fd7
    dodgerBlue32       = 27   ## hex: #005fff
    green4              = 28   ## hex: #008700
    springGreen4        = 29   ## hex: #00875f
    turquoise4          = 30   ## hex: #008787
    deepSkyBlue31      = 31   ## hex: #0087af
    deepSkyBlue32      = 32   ## hex: #0087d7
    dodgerBlue1         = 33   ## hex: #0087ff
    green31            = 34   ## hex: #00af00
    springGreen31      = 35   ## hex: #00af5f
    darkCyan            = 36   ## hex: #00af87
    lightSeaGreen       = 37   ## hex: #00afaf
    deepSkyBlue2        = 38   ## hex: #00afd7
    deepSkyBlue1        = 39   ## hex: #00afff
    green32            = 40   ## hex: #00d700
    springGreen33      = 41   ## hex: #00d75f
    springGreen21      = 42   ## hex: #00d787
    cyan3               = 43   ## hex: #00d7af
    darkTurquoise       = 44   ## hex: #00d7df
    turquoise2          = 45   ## hex: #00d7ff
    green1              = 46   ## hex: #00ff00
    springGreen22      = 47   ## hex: #00ff5f
    springGreen1        = 48   ## hex: #00ff87
    mediumSpringGreen   = 49   ## hex: #00ffaf
    cyan2               = 50   ## hex: #00ffd7
    cyan1               = 51   ## hex: #00ffff
    darkRed1           = 52   ## hex: #5f0000
    deepPink41         = 53   ## hex: #5f005f
    purple41           = 54   ## hex: #5f0087
    purple42           = 55   ## hex: #5f00af
    purple3             = 56   ## hex: #5f00df
    blueViolet          = 57   ## hex: #5f00ff
    orange41           = 58   ## hex: #5f5f00
    gray37              = 59   ## hex: #5f5f5f
    mediumPurple4       = 60   ## hex: #5f5f87
    slateBlue31        = 61   ## hex: #5f5faf
    slateBlue32        = 62   ## hex: #5f5fd7
    royalBlue1          = 63   ## hex: #5f5fff
    chartreuse4         = 64   ## hex: #5f8700
    darkSeaGreen41     = 65   ## hex: #5f875f
    paleTurquoise4      = 66   ## hex: #5f8787
    steelBlue           = 67   ## hex: #5f87af
    steelBlue3          = 68   ## hex: #5f87d7
    cornflowerBlue      = 69   ## hex: #5f87ff
    chartreuse31       = 70   ## hex: #5faf00
    darkSeaGreen42     = 71   ## hex: #5faf5f
    cadetBlue1         = 72   ## hex: #5faf87
    cadetBlue2         = 73   ## hex: #5fafaf
    skyBlue3            = 74   ## hex: #5fafd7
    steelBlue11        = 75   ## hex: #5fafff
    chartreuse32       = 76   ## hex: #5fd000
    paleGreen31        = 77   ## hex: #5fd75f
    seaGreen3           = 78   ## hex: #5fd787
    aquamarine3         = 79   ## hex: #5fd7af
    mediumTurquoise     = 80   ## hex: #5fd7d7
    steelBlue12        = 81   ## hex: #5fd7ff
    chartreuse21       = 82   ## hex: #5fff00
    seaGreen2           = 83   ## hex: #5fff5f
    seaGreen11         = 84   ## hex: #5fff87
    seaGreen12         = 85   ## hex: #5fffaf
    aquamarine11       = 86   ## hex: #5fffd7
    darkSlateGray2      = 87   ## hex: #5fffff
    darkRed2           = 88   ## hex: #870000
    deepPink42         = 89   ## hex: #87005f
    darkMagenta1       = 90   ## hex: #870087
    darkMagenta2       = 91   ## hex: #8700af
    darkViolet1        = 92   ## hex: #8700d7
    purple2            = 93   ## hex: #8700ff
    orange42           = 94   ## hex: #875f00
    lightPink4          = 95   ## hex: #875f5f
    plum4               = 96   ## hex: #875f87
    mediumPurple31     = 97   ## hex: #875faf
    mediumPurple32     = 98   ## hex: #875fd7
    slateBlue1          = 99   ## hex: #875fff
    yellow41           = 100  ## hex: #878700
    wheat4              = 101  ## hex: #87875f
    gray53              = 102  ## hex: #878787
    lightSlategray      = 103  ## hex: #8787af
    mediumPurple        = 104  ## hex: #8787d7
    lightSlateBlue      = 105  ## hex: #8787ff
    yellow42           = 106  ## hex: #87af00
    Wheat4              = 107  ## hex: #87af5f
    darkSeaGreen        = 108  ## hex: #87af87
    lightSkyBlue31     = 109  ## hex: #87afaf
    lightSkyBlue32     = 110  ## hex: #87afd7
    skyBlue2            = 111  ## hex: #87afff
    chartreuse22       = 112  ## hex: #87d700
    darkOliveGreen31   = 113  ## hex: #87d75f
    paleGreen32        = 114  ## hex: #87d787
    darkSeaGreen31     = 115  ## hex: #87d7af
    darkSlateGray3      = 116  ## hex: #87d7d7
    skyBlue1            = 117  ## hex: #87d7ff
    chartreuse1         = 118  ## hex: #87ff00
    lightGreen1        = 119  ## hex: #87ff5f
    lightGreen2        = 120  ## hex: #87ff87
    paleGreen11        = 121  ## hex: #87ffaf
    aquamarine12       = 122  ## hex: #87ffd7
    darkSlateGray1      = 123  ## hex: #87ffff
    red31              = 124  ## hex: #af0000
    deepPink4           = 125  ## hex: #af005f
    mediumVioletRed     = 126  ## hex: #af0087
    magenta3            = 127  ## hex: #af00af
    darkViolet2        = 128  ## hex: #af00d7
    purple              = 129  ## hex: #af00ff
    darkOrange31       = 130  ## hex: #af5f00
    indianRed1         = 131  ## hex: #af5f5f
    hotPink31          = 132  ## hex: #af5f87
    mediumOrchid3       = 133  ## hex: #af5faf
    mediumOrchid        = 134  ## hex: #af5fd7
    mediumPurple21     = 135  ## hex: #af5fff
    darkGoldenrod       = 136  ## hex: #af8700
    lightSalmon31      = 137  ## hex: #af875f
    rosyBrown           = 138  ## hex: #af8787
    gray63              = 139  ## hex: #af87af
    mediumPurple22     = 140  ## hex: #af87d7
    mediumPurple1       = 141  ## hex: #af87ff
    gold31             = 142  ## hex: #afaf00
    darkKhaki           = 143  ## hex: #afaf5f
    navajoWhite3        = 144  ## hex: #afaf87
    gray69              = 145  ## hex: #afafaf
    lightSteelBlue3     = 146  ## hex: #afafd7
    lightSteelBlue      = 147  ## hex: #afafff
    yellow31           = 148  ## hex: #afd700
    darkOliveGreen32   = 149  ## hex: #afd75f
    darkSeaGreen32     = 150  ## hex: #afd787
    darkSeaGreen21     = 151  ## hex: #afd7af
    lightCyan3          = 152  ## hex: #afafd7
    lightSkyBlue1       = 153  ## hex: #afd7ff
    greenYellow         = 154  ## hex: #afff00
    darkOliveGreen2     = 155  ## hex: #afff5f
    paleGreen12        = 156  ## hex: #afff87
    darkSeaGreen22     = 157  ## hex: #afffaf
    darkSeaGreen11     = 158  ## hex: #afffd7
    paleTurquoise1      = 159  ## hex: #afffff
    red32              = 160  ## hex: #d70000
    deepPink31         = 161  ## hex: #d7005f
    deepPink32         = 162  ## hex: #d70087
    magenta31          = 163  ## hex: #d700af
    magenta32          = 164  ## hex: #d700d7
    magenta21          = 165  ## hex: #d700ff
    darkOrange32       = 166  ## hex: #d75f00
    indianRed2         = 167  ## hex: #d75f5f
    hotPink32          = 168  ## hex: #d75f87
    hotPink2            = 169  ## hex: #d75faf
    orchid              = 170  ## hex: #d75fd7
    mediumOrchid11     = 171  ## hex: #d75fff
    orange3             = 172  ## hex: #d78700
    lightSalmon32      = 173  ## hex: #d7875f
    lightPink3          = 174  ## hex: #d78787
    pink3               = 175  ## hex: #d787af
    plum3               = 176  ## hex: #d787d7
    violet              = 177  ## hex: #d787ff
    gold32             = 178  ## hex: #d7af00
    lightGoldenrod3     = 179  ## hex: #d7af5f
    tan                 = 180  ## hex: #d7af87
    mistyRose3          = 181  ## hex: #d7afaf
    thistle3            = 182  ## hex: #d7afd7
    plum2               = 183  ## hex: #d7afff
    yellow32           = 184  ## hex: #d7d700
    khaki3              = 185  ## hex: #d7d75f
    lightGoldenrod2     = 186  ## hex: #d7d787
    lightYellow3        = 187  ## hex: #d7d7af
    gray84              = 188  ## hex: #d7d7d7
    lightSteelBlue1     = 189  ## hex: #d7d7ff
    yellow2             = 190  ## hex: #d7ff00
    darkOliveGreen11   = 191  ## hex: #d7ff5f
    darkOliveGreen12   = 192  ## hex: #d7ff87
    darkSeaGreen12     = 193  ## hex: #d7ffaf
    honeydew2           = 194  ## hex: #d7ffd7
    lightCyan1          = 195  ## hex: #d7ffff
    red1                = 196  ## hex: #ff0000
    deepPink2           = 197  ## hex: #ff005f
    deepPink11         = 198  ## hex: #ff0087
    deepPink12         = 199  ## hex: #ff00af
    magenta22          = 200  ## hex: #ff00d7
    magenta1            = 201  ## hex: #ff00ff
    orangeRed1          = 202  ## hex: #ff5f00
    indianRed11        = 203  ## hex: #ff5f5f
    indianRed12        = 204  ## hex: #ff5f87
    hotPink11          = 205  ## hex: #ff5faf
    hotPink12          = 206  ## hex: #ff5fd7
    mediumOrchid12     = 207  ## hex: #ff5fff
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
    lightGoldenrod21   = 221  ## hex: #ffd75f
    lightGoldenrod22   = 222  ## hex: #ffd787
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
proc rgbToColor*(red, green, blue: int): Color =
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
  return rgbToColor(red, green, blue)

# Returns the closest inverse Color
# for col.
proc inverseColor*(col: Color): Color =
  if not colorToHexTable.hasKey(int(col)):
    return Color.default

  var rgb      = colorToRGBTable[int(col)]
  rgb[0] = abs(rgb[0] - 255)
  rgb[1] = abs(rgb[1] - 255)
  rgb[2] = abs(rgb[2] - 255)
  return rgbToColor(rgb[0], rgb[1], rgb[2])

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
  return rgbToColor(rgb1[0], rgb1[1], rgb1[2])

type colorTheme* = enum
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
  gtBinNumber*: Color
  gtDecNumber*: Color
  gtFloatNumber*: Color
  gtHexNumber*: Color
  gtOctNumber*: Color
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
  popupWindow*: Color
  popupWindowBg*: Color
  popupWinCurrentLine*: Color
  popupWinCurrentLineBg*: Color
  # replace text highlighting
  replaceText*: Color
  replaceTextBg*: Color

  # pair of paren highlighting
  parenText*: Color
  parenTextBg*: Color

  # highlight for other uses current word
  currentWord*: Color
  currentWordBg*: Color

  # full width space
  highlightFullWidthSpace*: Color
  highlightFullWidthSpaceBg*: Color

  # trailing spaces
  highlightTrailingSpaces*: Color
  highlightTrailingSpacesBg*: Color

  # reserved words
  reservedWord*: Color
  reservedWordBg*: Color

  # backup manager
  currentBackup*: Color
  currentBackupBg*: Color

  # diff viewer
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
  binNumber = 36
  decNumber = 37
  floatNumber = 38
  hexNumber = 39
  octNumber = 40
  comment = 41
  longComment = 42
  whitespace = 43
  preprocessor = 44
  pragma = 45

  # filer mode
  currentFile = 46
  file = 47
  dir = 48
  pcLink = 49
  # pop up window
  popupWindow = 50
  popupWinCurrentLine = 51
  # replace text highlighting
  replaceText = 52
  # pair of paren highlighting
  parenText = 53
  # other uses current word
  currentWord = 54
  # full width space
  highlightFullWidthSpace = 55
  # trailing spaces
  highlightTrailingSpaces = 56
  # reserved words
  reservedWord = 57
  # Backup manager
  currentBackup = 58
  # diff viewer
  addedLine = 59
  deletedLine = 60
  # configuration mode
  currentSetting = 61

var colorThemeTable*: array[colorTheme, EditorColor] = [
  config: EditorColor(
    editorBg: default,
    lineNum: gray54,
    lineNumBg: default,
    currentLineNum: teal,
    currentLineNumBg: default,
    # status bar
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
    visualModeBg: purple1,

    # color scheme
    defaultChar: white,
    gtKeyword: skyBlue1,
    gtFunctionName: gold1,
    gtTypeName: green,
    gtBoolean: yellow,
    gtStringLit: yellow,
    gtSpecialVar: green,
    gtBuiltin: yellow,
    gtBinNumber: aqua,
    gtDecNumber: aqua,
    gtFloatNumber: aqua,
    gtHexNumber: aqua,
    gtOctNumber: aqua,
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
    popupWindow: gray100,
    popupWindowBg: black,
    popupWinCurrentLine: blue,
    popupWinCurrentLineBg: black,
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
    # Backup manager
    currentBackup: gray100,
    currentBackupBg: teal,
    # diff viewer
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
    # status line
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
    visualModeBg: purple1,

    # color scheme
    defaultChar: white,
    gtKeyword: skyBlue1,
    gtFunctionName: gold1,
    gtTypeName: green,
    gtBoolean: yellow,
    gtStringLit: yellow,
    gtSpecialVar: green,
    gtBuiltin: yellow,
    gtBinNumber: aqua,
    gtDecNumber: aqua,
    gtFloatNumber: aqua,
    gtHexNumber: aqua,
    gtOctNumber: aqua,
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
    popupWindow: gray100,
    popupWindowBg: black,
    popupWinCurrentLine: blue,
    popupWinCurrentLineBg: black,
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
    # Backup manager
    currentBackup: gray100,
    currentBackupBg: teal,
    # diff viewer
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
    # status line
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
    visualModeBg: purple1,

    # color scheme
    defaultChar: white,
    gtKeyword: skyBlue1,
    gtFunctionName: gold1,
    gtTypeName: green,
    gtBoolean: yellow,
    gtStringLit: yellow,
    gtSpecialVar: green,
    gtBuiltin: yellow,
    gtBinNumber: aqua,
    gtDecNumber: aqua,
    gtFloatNumber: aqua,
    gtHexNumber: aqua,
    gtOctNumber: aqua,
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
    popupWindow: gray100,
    popupWindowBg: black,
    popupWinCurrentLine: blue,
    popupWinCurrentLineBg: black,
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
    # Backup manager
    currentBackup: gray100,
    currentBackupBg: teal,
    # diff viewer
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
    # status line
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
    visualModeBg: purple1,

    # color scheme
    defaultChar: gray100,
    gtKeyword: seaGreen12,
    gtFunctionName: gold1,
    gtTypeName: green,
    gtBoolean: yellow,
    gtStringLit: purple1,
    gtSpecialVar: green,
    gtBuiltin: yellow,
    gtBinNumber: aqua,
    gtDecNumber: aqua,
    gtFloatNumber: aqua,
    gtHexNumber: aqua,
    gtOctNumber: aqua,
    gtComment: gray,
    gtLongComment: gray,
    gtWhitespace: gray,
    gtPreprocessor: green,
    gtPragma: yellow,

    # filer mode
    currentFile: black,
    currentFileBg: deepPink11,
    file: black,
    fileBg: default,
    dir: deepPink11,
    dirBg: default,
    pcLink: teal,
    pcLinkBg: default,
    # pop up window
    popupWindow: black,
    popupWindowBg: gray,
    popupWinCurrentLine: blue,
    popupWinCurrentLineBg: gray,
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
    # Backup manager
    currentBackup: black,
    currentBackupBg: deepPink11,
    # diff viewer
    addedLine: green,
    addedLineBg: default,
    deletedLine: red,
    deletedLineBg: default,
    # configuration mode
    currentSetting: black,
    currentSettingBg: deepPink11,
    # Highlight current line background
    currentLineBg: gray27
  ),
  vivid: EditorColor(
    editorBg: default,
    lineNum: gray54,
    lineNumBg: default,
    currentLineNum: deepPink11,
    currentLineNumBg: default,
    # status line
    statusLineNormalMode: black,
    statusLineNormalModeBg: deepPink11,
    statusLineModeNormalMode: black,
    statusLineModeNormalModeBg: gray100,
    statusLineNormalModeInactive: deepPink11,
    statusLineNormalModeInactiveBg: white,

    statusLineInsertMode: black,
    statusLineInsertModeBg: deepPink11,
    statusLineModeInsertMode: black,
    statusLineModeInsertModeBg: gray100,
    statusLineInsertModeInactive: deepPink11,
    statusLineInsertModeInactiveBg: white,

    statusLineVisualMode: black,
    statusLineVisualModeBg: deepPink11,
    statusLineModeVisualMode: black,
    statusLineModeVisualModeBg: gray100,
    statusLineVisualModeInactive: deepPink11,
    statusLineVisualModeInactiveBg: white,

    statusLineReplaceMode: black,
    statusLineReplaceModeBg: deepPink11,
    statusLineModeReplaceMode: black,
    statusLineModeReplaceModeBg: gray100,
    statusLineReplaceModeInactive: deepPink11,
    statusLineReplaceModeInactiveBg: white,

    statusLineFilerMode: black,
    statusLineFilerModeBg: deepPink11,
    statusLineModeFilerMode: black,
    statusLineModeFilerModeBg: gray100,
    statusLineFilerModeInactive: deepPink11,
    statusLineFilerModeInactiveBg: white,

    statusLineExMode: black,
    statusLineExModeBg: deepPink11,
    statusLineModeExMode: black,
    statusLineModeExModeBg: gray100,
    statusLineExModeInactive: deepPink11,
    statusLineExModeInactiveBg: white,

    statusLineGitBranch: deepPink11,
    statusLineGitBranchBg: black,
    # tab line
    tab: white,
    tabBg: default,
    currentTab: black,
    currentTabBg: deepPink11,
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
    visualModeBg: purple1,

    # color scheme
    defaultChar: gray100,
    gtKeyword: deepPink11,
    gtFunctionName: gold1,
    gtTypeName: green,
    gtBoolean: yellow,
    gtStringLit: purple1,
    gtSpecialVar: green,
    gtBuiltin: aqua,
    gtBinNumber: aqua,
    gtDecNumber: aqua,
    gtFloatNumber: aqua,
    gtHexNumber: aqua,
    gtOctNumber: aqua,
    gtComment: gray,
    gtLongComment: gray,
    gtWhitespace: gray,
    gtPreprocessor: green,
    gtPragma: aqua,

    # filer mode
    currentFile: gray100,
    currentFileBg: deepPink11,
    file: gray100,
    fileBg: default,
    dir: deepPink11,
    dirBg: default,
    pcLink: cyan1,
    pcLinkBg: default,
    # pop up window
    popupWindow: gray100,
    popupWindowBg: black,
    popupWinCurrentLine: deepPink11,
    popupWinCurrentLineBg: black,
    # replace text highlighting
    replaceText: default,
    replaceTextBg: red,
    # pair of paren highlighting
    parenText: default,
    parenTextBg: deepPink11,
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
    reservedWord: deepPink11,
    reservedWordBg: black,
    # Backup manager
    currentBackup: gray100,
    currentBackupBg: deepPink11,
    # diff viewer
    addedLine: green,
    addedLineBg: default,
    deletedLine: red,
    deletedLineBg: default,
    # configuration mode
    currentSetting: gray100,
    currentSettingBg: deepPink11,
    # Highlight current line background
    currentLineBg: gray27
  ),
]

proc setColorPair*(colorPair: EditorColorPair | int,
                   character, background: Color) {.inline.} =

  initpair(cshort(ord(colorPair)),
            cshort(ord(character)),
            cshort(ord(background)))

proc setCursesColor*(editorColor: EditorColor) =
  # Not set when running unit tests
  when not defined unitTest:
    startcolor()   # enable color
    usedefaultcolors()    # set terminal default color

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
    setColorPair(EditorColorPair.binNumber,
                 editorColor.gtBinNumber,
                 editorColor.editorBg)
    setColorPair(EditorColorPair.decNumber,
                 editorColor.gtDecNumber,
                 editorColor.editorBg)
    setColorPair(EditorColorPair.floatNumber,
                 editorColor.gtFloatNumber,
                 editorColor.editorBg)
    setColorPair(EditorColorPair.hexNumber,
                 editorColor.gtHexNumber,
                 editorColor.editorBg)
    setColorPair(EditorColorPair.octNumber,
                 editorColor.gtOctNumber,
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
    setColorPair(EditorColorPair.popupWindow,
                 editorColor.popupWindow,
                 editorColor.popupWindowBg)
    setColorPair(EditorColorPair.popupWinCurrentLine,
                 editorColor.popupWinCurrentLine,
                 editorColor.popupWinCurrentLineBg)

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

    # Backup manager
    setColorPair(EditorColorPair.currentBackup,
                 editorColor.currentBackup,
                 editorColor.currentBackupBg)

    # diff viewer
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

proc getColorFromEditorColorPair*(theme: colorTheme,
                                  pair: EditorColorPair): (Color, Color) =

  let editorColor = colorThemeTable[theme]

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
  of EditorColorPair.binNumber:
    return (editorColor.gtBinNumber, editorColor.editorBg)
  of EditorColorPair.decNumber:
    return (editorColor.gtDecNumber, editorColor.editorBg)
  of EditorColorPair.floatNumber:
    return (editorColor.gtFloatNumber, editorColor.editorBg)
  of EditorColorPair.hexNumber:
    return (editorColor.gtHexNumber, editorColor.editorBg)
  of EditorColorPair.octNumber:
    return (editorColor.gtOctNumber, editorColor.editorBg)
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
  of EditorColorPair.popupWindow:
    return (editorColor.popupWindow, editorColor.popupWindowBg)
  of EditorColorPair.popupWinCurrentLine:
    return (editorColor.popupWinCurrentLine, editorColor.popupWinCurrentLineBg)
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
  of EditorColorPair.currentBackup:
    return (editorColor.currentBackup, editorColor.currentBackupBg)
  of EditorColorPair.currentSetting:
    return (editorColor.currentSetting, editorColor.currentSettingBg)
  of EditorColorPair.parenText:
    return (editorColor.parenText, editorColor.parenTextBg)
  of EditorColorPair.currentWord:
    return (editorColor.currentWord, editorColor.currentWordBg)
  of EditorColorPair.highlightFullWidthSpace:
    return (editorColor.highlightFullWidthSpace, editorColor.highlightFullWidthSpaceBg)

macro setColor*(theme: colorTheme,
                editorColor: string,
                color: Color): untyped =

    parseStmt(fmt"""
      colorThemeTable[{repr(theme)}].{editorColor} = {repr(color)}
    """)

# Environment where only 8 colors can be used
proc convertToConsoleEnvironmentColor*(theme: colorTheme) =
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
      of maroon, red, darkRed1, darkRed2, red31, mediumVioletRed,
         indianRed1, red32, indianRed2, red1, orangeRed1, indianRed11,
         indianRed12, paleVioletRed1, deepPink41, deepPink42, deepPink4,
         magenta3: true
      else: false

  proc isGreen(color: Color): bool =
    case color:
      of green, darkGreen, green4, springGreen4, green31, springGreen31,
         lightSeaGreen, green32, springGreen33, springGreen21, green1,
         springGreen22, springGreen1, mediumSpringGreen, darkSeaGreen41,
         darkSeaGreen42, paleGreen31, seaGreen3, seaGreen2, seaGreen11,
         seaGreen12, darkSeaGreen, darkOliveGreen31, paleGreen32,
         darkSeaGreen31, lightGreen1, lightGreen2, paleGreen11,
         darkOliveGreen32, darkSeaGreen32, darkSeaGreen21, greenYellow,
         darkOliveGreen2, paleGreen12, darkSeaGreen22, darkSeaGreen11,
         darkOliveGreen11, darkOliveGreen12, darkSeaGreen12,
         lime, orange41, chartreuse4, paleTurquoise4, chartreuse31,
         chartreuse32, chartreuse21, Wheat4, chartreuse22, chartreuse1,
         darkGoldenrod, lightSalmon31, rosyBrown, gold31, darkKhaki,
         navajoWhite3: true
      else: false

  # is olive (yellow)
  proc isOlive(color: Color): bool =
    case color:
      of olive,
         yellow, yellow41, yellow42, yellow31, yellow32, lightYellow3,
         yellow2, yellow1, orange42, lightPink4, plum4, wheat4, darkOrange31,
         darkOrange32, orange3, lightSalmon32, gold32, lightGoldenrod3, tan,
         mistyRose3, khaki3, lightGoldenrod2, darkOrange, salmon1, orange1,
         sandyBrown, lightSalmon1, gold1, lightGoldenrod21, lightGoldenrod22,
         navajoWhite1, lightGoldenrod1, khaki1, wheat1, cornsilk1: true
      else: false

  # is navy (blue)
  proc isNavy(color: Color): bool =
    case color:
      of navy,
         blue, navyBlue, darkBlue, blue31, blue32, blue1, deepSkyBlue41,
         deepSkyBlue42, deepSkyBlue43, dodgerBlue31, dodgerBlue32,
         deepSkyBlue31, deepSkyBlue32, dodgerBlue1, deepSkyBlue2,
         deepSkyBlue1, blueViolet, slateBlue31, slateBlue32, royalBlue1,
         steelBlue, steelBlue3, cornflowerBlue, cadetBlue1, cadetBlue2,
         skyBlue3, steelBlue11, steelBlue12, slateBlue1, lightSlateBlue,
         lightSkyBlue31, lightSkyBlue32, skyBlue2, skyBlue1,
         lightSteelBlue3, lightSteelBlue, lightSkyBlue1, lightSteelBlue1,
         aqua, darkTurquoise, turquoise2, aquamarine11: true
      else: false

  proc isPurple(color: Color): bool =
    case color:
      of purple1,
         purple41, purple42, purple3, mediumPurple4, purple2,
         mediumPurple31, mediumPurple32, mediumPurple, purple,
         mediumPurple21, mediumPurple22, mediumPurple1, fuchsia,
         darkMagenta1, darkMagenta2, darkViolet1, darkViolet2, hotPink31,
         mediumOrchid3, mediumOrchid, deepPink31, deepPink32, magenta31,
         magenta32, magenta21, hotPink32, hotPink2, orchid, mediumOrchid11,
         lightPink3, pink3, plum3, violet, thistle3, plum2, deepPink2,
         deepPink11, deepPink12, magenta22, magenta1, hotPink11,
         hotPink12, mediumOrchid12, lightCoral, orchid2, orchid1, lightPink1,
         pink1, plum1, mistyRose1, thistle1: true
      else: false

  # is teal (cyan)
  proc isTeal(color: Color): bool =
    case color:
      of teal, darkCyan, cyan3, cyan2, cyan1, lightCyan3, lightCyan1,
         turquoise4, turquoise2, aquamarine3, mediumTurquoise, aquamarine12,
         paleTurquoise1, honeydew2: true
      else: false

  for name, color in colorThemeTable[theme].fieldPairs:
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
      setColor(theme, name, Color.purple1)
    elif isTeal(color):
      setColor(theme, name, Color.teal)
    else:
      # is silver (white)
      setColor(theme, name, Color.silver)

    setCursesColor(colorThemeTable[theme])
