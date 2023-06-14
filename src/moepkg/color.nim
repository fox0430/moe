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
import pkg/results
import ui

type
  # 0 ~ 255
  # -1 is the terminal default color.
  Rgb* = object
    red*, green*, blue*: int16

  RgbPair* = object
    foreground*, background*: Rgb

  ColorLayer* {.pure.} = enum
    foreground
    background

  # 16 for the terminal.
  Color16* {.pure.} =  enum
    default             = -1   # The terminal default
    black               = 0    ## hex: #000000
    maroon              = 1    ## hex: #800000
    green               = 2    ## hex: #008000
    olive               = 3    ## hex: #808000
    navy                = 4    ## hex: #000080
    purple1             = 5    ## hex: #800080
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

  # 256 for the terminal.
  Color256* {.pure.} = enum
    default             = -1   # The terminal default
    black               = 0    ## hex: #000000
    maroon              = 1    ## hex: #800000
    green               = 2    ## hex: #008000
    olive               = 3    ## hex: #808000
    navy                = 4    ## hex: #000080
    purple1             = 5    ## hex: #800080
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
    blue31              = 19   ## hex: #0000af
    blue32              = 20   ## hex: #0000d7
    blue1               = 21   ## hex: #0000ff
    darkGreen           = 22   ## hex: #005f00
    deepSkyBlue41       = 23   ## hex: #005f5f
    deepSkyBlue42       = 24   ## hex: #005f87
    deepSkyBlue43       = 25   ## hex: #005faf
    dodgerBlue31        = 26   ## hex: #005fd7
    dodgerBlue32        = 27   ## hex: #005fff
    green4              = 28   ## hex: #008700
    springGreen4        = 29   ## hex: #00875f
    turquoise4          = 30   ## hex: #008787
    deepSkyBlue31       = 31   ## hex: #0087af
    deepSkyBlue32       = 32   ## hex: #0087d7
    dodgerBlue1         = 33   ## hex: #0087ff
    green31             = 34   ## hex: #00af00
    springGreen31       = 35   ## hex: #00af5f
    darkCyan            = 36   ## hex: #00af87
    lightSeaGreen       = 37   ## hex: #00afaf
    deepSkyBlue2        = 38   ## hex: #00afd7
    deepSkyBlue1        = 39   ## hex: #00afff
    green32             = 40   ## hex: #00d700
    springGreen33       = 41   ## hex: #00d75f
    springGreen21       = 42   ## hex: #00d787
    cyan3               = 43   ## hex: #00d7af
    darkTurquoise       = 44   ## hex: #00d7df
    turquoise2          = 45   ## hex: #00d7ff
    green1              = 46   ## hex: #00ff00
    springGreen22       = 47   ## hex: #00ff5f
    springGreen1        = 48   ## hex: #00ff87
    mediumSpringGreen   = 49   ## hex: #00ffaf
    cyan2               = 50   ## hex: #00ffd7
    cyan1               = 51   ## hex: #00ffff
    darkRed1            = 52   ## hex: #5f0000
    deepPink41          = 53   ## hex: #5f005f
    purple41            = 54   ## hex: #5f0087
    purple42            = 55   ## hex: #5f00af
    purple3             = 56   ## hex: #5f00df
    blueViolet          = 57   ## hex: #5f00ff
    orange41            = 58   ## hex: #5f5f00
    gray37              = 59   ## hex: #5f5f5f
    mediumPurple4       = 60   ## hex: #5f5f87
    slateBlue31         = 61   ## hex: #5f5faf
    slateBlue32         = 62   ## hex: #5f5fd7
    royalBlue1          = 63   ## hex: #5f5fff
    chartreuse4         = 64   ## hex: #5f8700
    darkSeaGreen41      = 65   ## hex: #5f875f
    paleTurquoise4      = 66   ## hex: #5f8787
    steelBlue           = 67   ## hex: #5f87af
    steelBlue3          = 68   ## hex: #5f87d7
    cornflowerBlue      = 69   ## hex: #5f87ff
    chartreuse31        = 70   ## hex: #5faf00
    darkSeaGreen42      = 71   ## hex: #5faf5f
    cadetBlue1          = 72   ## hex: #5faf87
    cadetBlue2          = 73   ## hex: #5fafaf
    skyBlue3            = 74   ## hex: #5fafd7
    steelBlue11         = 75   ## hex: #5fafff
    chartreuse32        = 76   ## hex: #5fd000
    paleGreen31         = 77   ## hex: #5fd75f
    seaGreen3           = 78   ## hex: #5fd787
    aquamarine3         = 79   ## hex: #5fd7af
    mediumTurquoise     = 80   ## hex: #5fd7d7
    steelBlue12         = 81   ## hex: #5fd7ff
    chartreuse21        = 82   ## hex: #5fff00
    seaGreen2           = 83   ## hex: #5fff5f
    seaGreen11          = 84   ## hex: #5fff87
    seaGreen12          = 85   ## hex: #5fffaf
    aquamarine11        = 86   ## hex: #5fffd7
    darkSlateGray2      = 87   ## hex: #5fffff
    darkRed2            = 88   ## hex: #870000
    deepPink42          = 89   ## hex: #87005f
    darkMagenta1        = 90   ## hex: #870087
    darkMagenta2        = 91   ## hex: #8700af
    darkViolet1         = 92   ## hex: #8700d7
    purple2             = 93   ## hex: #8700ff
    orange42            = 94   ## hex: #875f00
    lightPink4          = 95   ## hex: #875f5f
    plum4               = 96   ## hex: #875f87
    mediumPurple31      = 97   ## hex: #875faf
    mediumPurple32      = 98   ## hex: #875fd7
    slateBlue1          = 99   ## hex: #875fff
    yellow41            = 100  ## hex: #878700
    wheat4              = 101  ## hex: #87875f
    gray53              = 102  ## hex: #878787
    lightSlategray      = 103  ## hex: #8787af
    mediumPurple        = 104  ## hex: #8787d7
    lightSlateBlue      = 105  ## hex: #8787ff
    yellow42            = 106  ## hex: #87af00
    Wheat4              = 107  ## hex: #87af5f
    darkSeaGreen        = 108  ## hex: #87af87
    lightSkyBlue31      = 109  ## hex: #87afaf
    lightSkyBlue32      = 110  ## hex: #87afd7
    skyBlue2            = 111  ## hex: #87afff
    chartreuse22        = 112  ## hex: #87d700
    darkOliveGreen31    = 113  ## hex: #87d75f
    paleGreen32         = 114  ## hex: #87d787
    darkSeaGreen31      = 115  ## hex: #87d7af
    darkSlateGray3      = 116  ## hex: #87d7d7
    skyBlue1            = 117  ## hex: #87d7ff
    chartreuse1         = 118  ## hex: #87ff00
    lightGreen1         = 119  ## hex: #87ff5f
    lightGreen2         = 120  ## hex: #87ff87
    paleGreen11         = 121  ## hex: #87ffaf
    aquamarine12        = 122  ## hex: #87ffd7
    darkSlateGray1      = 123  ## hex: #87ffff
    red31               = 124  ## hex: #af0000
    deepPink4           = 125  ## hex: #af005f
    mediumVioletRed     = 126  ## hex: #af0087
    magenta3            = 127  ## hex: #af00af
    darkViolet2         = 128  ## hex: #af00d7
    purple              = 129  ## hex: #af00ff
    darkOrange31        = 130  ## hex: #af5f00
    indianRed1          = 131  ## hex: #af5f5f
    hotPink31           = 132  ## hex: #af5f87
    mediumOrchid3       = 133  ## hex: #af5faf
    mediumOrchid        = 134  ## hex: #af5fd7
    mediumPurple21      = 135  ## hex: #af5fff
    darkGoldenrod       = 136  ## hex: #af8700
    lightSalmon31       = 137  ## hex: #af875f
    rosyBrown           = 138  ## hex: #af8787
    gray63              = 139  ## hex: #af87af
    mediumPurple22      = 140  ## hex: #af87d7
    mediumPurple1       = 141  ## hex: #af87ff
    gold31              = 142  ## hex: #afaf00
    darkKhaki           = 143  ## hex: #afaf5f
    navajoWhite3        = 144  ## hex: #afaf87
    gray69              = 145  ## hex: #afafaf
    lightSteelBlue3     = 146  ## hex: #afafd7
    lightSteelBlue      = 147  ## hex: #afafff
    yellow31            = 148  ## hex: #afd700
    darkOliveGreen32    = 149  ## hex: #afd75f
    darkSeaGreen32      = 150  ## hex: #afd787
    darkSeaGreen21      = 151  ## hex: #afd7af
    lightCyan3          = 152  ## hex: #afafd7
    lightSkyBlue1       = 153  ## hex: #afd7ff
    greenYellow         = 154  ## hex: #afff00
    darkOliveGreen2     = 155  ## hex: #afff5f
    paleGreen12         = 156  ## hex: #afff87
    darkSeaGreen22      = 157  ## hex: #afffaf
    darkSeaGreen11      = 158  ## hex: #afffd7
    paleTurquoise1      = 159  ## hex: #afffff
    red32               = 160  ## hex: #d70000
    deepPink31          = 161  ## hex: #d7005f
    deepPink32          = 162  ## hex: #d70087
    magenta31           = 163  ## hex: #d700af
    magenta32           = 164  ## hex: #d700d7
    magenta21           = 165  ## hex: #d700ff
    darkOrange32        = 166  ## hex: #d75f00
    indianRed2          = 167  ## hex: #d75f5f
    hotPink32           = 168  ## hex: #d75f87
    hotPink2            = 169  ## hex: #d75faf
    orchid              = 170  ## hex: #d75fd7
    mediumOrchid11      = 171  ## hex: #d75fff
    orange3             = 172  ## hex: #d78700
    lightSalmon32       = 173  ## hex: #d7875f
    lightPink3          = 174  ## hex: #d78787
    pink3               = 175  ## hex: #d787af
    plum3               = 176  ## hex: #d787d7
    violet              = 177  ## hex: #d787ff
    gold32              = 178  ## hex: #d7af00
    lightGoldenrod3     = 179  ## hex: #d7af5f
    tan                 = 180  ## hex: #d7af87
    mistyRose3          = 181  ## hex: #d7afaf
    thistle3            = 182  ## hex: #d7afd7
    plum2               = 183  ## hex: #d7afff
    yellow32            = 184  ## hex: #d7d700
    khaki3              = 185  ## hex: #d7d75f
    lightGoldenrod2     = 186  ## hex: #d7d787
    lightYellow3        = 187  ## hex: #d7d7af
    gray84              = 188  ## hex: #d7d7d7
    lightSteelBlue1     = 189  ## hex: #d7d7ff
    yellow2             = 190  ## hex: #d7ff00
    darkOliveGreen11    = 191  ## hex: #d7ff5f
    darkOliveGreen12    = 192  ## hex: #d7ff87
    darkSeaGreen12      = 193  ## hex: #d7ffaf
    honeydew2           = 194  ## hex: #d7ffd7
    lightCyan1          = 195  ## hex: #d7ffff
    red1                = 196  ## hex: #ff0000
    deepPink2           = 197  ## hex: #ff005f
    deepPink11          = 198  ## hex: #ff0087
    deepPink12          = 199  ## hex: #ff00af
    magenta22           = 200  ## hex: #ff00d7
    magenta1            = 201  ## hex: #ff00ff
    orangeRed1          = 202  ## hex: #ff5f00
    indianRed11         = 203  ## hex: #ff5f5f
    indianRed12         = 204  ## hex: #ff5f87
    hotPink11           = 205  ## hex: #ff5faf
    hotPink12           = 206  ## hex: #ff5fd7
    mediumOrchid12      = 207  ## hex: #ff5fff
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
    lightGoldenrod21    = 221  ## hex: #ffd75f
    lightGoldenrod22    = 222  ## hex: #ffd787
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

## Parses a hex color value from a string s.
## Examples: "#000000", "ff0000"
proc hexToRgb*(s: string): Result[Rgb, string] =
  if not (s.len == 6 or (s.len == 7 and s.startsWith('#'))):
    return Result[Rgb, string].err "Invalid hex color"

  let hexStr =
    if s.startsWith('#'): s[1 .. 6]
    else: s

  var rgb: Rgb
  try:
    rgb = Rgb(
      red: fromHex[int16](hexStr[0..1]),
      green: fromHex[int16](hexStr[2..3]),
      blue: fromHex[int16](hexStr[4..5]))
  except CatchableError as e:
    return Result[Rgb, string].err fmt"Failed to parse hex color: {$e.msg}"

  return Result[Rgb, string].ok rgb

## Converts from the Rgb to a hex color code with `#`.
## Example: Rgb(red: 0, green: 0, blue: 0) -> "#000000"
proc toHex*(rgb: Rgb): string {.inline.} =
  fmt"#{rgb.red.toHex(2)}{rgb.green.toHex(2)}{rgb.blue.toHex(2)}"

## Return true if valid hex color code.
## '#' is required if `isPrefix` is true.
## Range: 000000 ~ ffffff
proc isHexColor*(s: string, isPrefix: bool = true): bool =
  if (not isPrefix or s.startsWith('#')) and s.len == 7:
    var
      r, g, b: int
    try:
      r = fromHex[int](s[1..2])
      g = fromHex[int](s[3..4])
      b = fromHex[int](s[5..6])
    except ValueError:
      return false

    return (r >= 0 and r <= 255) and
           (g >= 0 and g <= 255) and
           (b >= 0 and b <= 255)

proc isTermDefaultColor*(rgb: Rgb): bool {.inline.} =
  rgb == Rgb(red: -1, green: -1, blue: -1)

## Return the inverse color.
proc inverseColor*(color: Rgb): Rgb =
  if color.isTermDefaultColor:
    return color

  result.red = abs(color.red - 255)
  result.green = abs(color.green - 255)
  result.blue  = abs(color.blue - 255)

# maps annotations of the enum to a hexToColor table
# TODO: Rewrite color.mapAnnotationToTable
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

# Calculates the difference between two rgb colors
template calcRGBDifference(col1: Rgb, col2: Rgb): int =
  abs(col1[0] - col2[0]) + abs(col1[1] - col2[1]) + abs(col1[2] - col2[2])

# Converts an rgb value to a color,
# the closest color is approximated
# TODO: Rewrite color.rgbToColor
#proc rgbToColor*(rgb: Rgb): Color =
#  var closestColor     : Color
#  var lowestDifference : int    = 100000
#  for key, value in colorToRGBTable:
#    let keyRed   = value[0]
#    let keyGreen = value[1]
#    let keyBlue  = value[2]
#    let difference = calcRGBDifference((red, green, blue),
#                                       (keyRed, keyGreen, keyBlue))
#    if difference < lowestDifference:
#      lowestDifference = difference
#      closestColor     = Color(key)
#      if difference == 0:
#        break
#  return closestColor

# Returns the closest inverse Color for col.
# TODO: Rewrite color.inverseColor
#proc inverseColor*(col: Color): Color =
#  if not colorToHexTable.hasKey(int(col)):
#    return Color.default
#
#  var rgb      = colorToRGBTable[int(col)]
#  rgb[0] = abs(rgb[0] - 255)
#  rgb[1] = abs(rgb[1] - 255)
#  rgb[2] = abs(rgb[2] - 255)
#  return rgbToColor(rgb[0], rgb[1], rgb[2])

# Make Color col readable on the background.
# This tries to preserve the color of col as much as
# possible, but adjusts it when needed for
# becoming readable on the background.
# Returns col without changes, if it's already readable.
# TODO: Rewrite color.readableOnBackground
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
#  return rgbToColor(rgb1[0], rgb1[1], rgb1[2])

type
  ColorTheme* {.pure.} = enum
    dark
    light
    vivid
    config
    vscode

  EditorColorIndex* {.pure.} = enum
    termDefaultForeground
    termDefaultBackground
    foreground
    background
    lineNum
    lineNumBg
    currentLineNum
    currentLineNumBg
    # status line
    statusLineNormalMode
    statusLineNormalModeBg
    statusLineModeNormalMode
    statusLineModeNormalModeBg
    statusLineNormalModeInactive
    statusLineNormalModeInactiveBg

    statusLineInsertMode
    statusLineInsertModeBg
    statusLineModeInsertMode
    statusLineModeInsertModeBg
    statusLineInsertModeInactive
    statusLineInsertModeInactiveBg

    statusLineVisualMode
    statusLineVisualModeBg
    statusLineModeVisualMode
    statusLineModeVisualModeBg
    statusLineVisualModeInactive
    statusLineVisualModeInactiveBg

    statusLineReplaceMode
    statusLineReplaceModeBg
    statusLineModeReplaceMode
    statusLineModeReplaceModeBg
    statusLineReplaceModeInactive
    statusLineReplaceModeInactiveBg

    statusLineFilerMode
    statusLineFilerModeBg
    statusLineModeFilerMode
    statusLineModeFilerModeBg
    statusLineFilerModeInactive
    statusLineFilerModeInactiveBg

    statusLineExMode
    statusLineExModeBg
    statusLineModeExMode
    statusLineModeExModeBg
    statusLineExModeInactive
    statusLineExModeInactiveBg

    statusLineGitBranch
    statusLineGitBranchBg
    # tab line
    tab
    tabBg
    currentTab
    currentTabBg
    # command bar
    commandBar
    commandBarBg
    # error message
    errorMessage
    errorMessageBg
    # search result highlighting
    searchResult
    searchResultBg
    # selected area in visual mode
    visualMode
    visualModeBg

    # color scheme
    keyword
    keywordBg
    functionName
    functionNameBg
    typeName
    typeNameBg
    boolean
    booleanBg
    stringLit
    stringLitBg
    specialVar
    specialVarBg
    builtin
    builtinBg
    binNumber
    binNumberBg
    decNumber
    decNumberBg
    floatNumber
    floatNumberBg
    hexNumber
    hexNumberBg
    octNumber
    octNumberBg
    comment
    commentBg
    longComment
    longCommentBg
    whitespace
    whitespaceBg
    preprocessor
    preprocessorBg
    pragma
    pragmaBg

    # filer mode
    currentFile
    currentFileBg
    file
    fileBg
    dir
    dirBg
    pcLink
    pcLinkBg
    # pop up window
    popupWindow
    popupWindowBg
    popupWinCurrentLine
    popupWinCurrentLineBg
    # replace text highlighting
    replaceText
    replaceTextBg

    # pair of paren highlighting
    parenText
    parenTextBg

    # highlight for other uses current word
    currentWord
    currentWordBg

    # full width space
    highlightFullWidthSpace
    highlightFullWidthSpaceBg

    # trailing spaces
    highlightTrailingSpaces
    highlightTrailingSpacesBg

    # reserved words
    reservedWord
    reservedWordBg

    # backup manager
    currentBackup
    currentBackupBg

    # diff viewer
    addedLine
    addedLineBg
    deletedLine
    deletedLineBg

    # configuration mode
    currentSetting
    currentSettingBg

    # highlight curent line background
    currentLineBg

  EditorColorPairIndex* {.pure.} = enum
    # Cannot use 0 in Ncurses color pair.
    default = 1
    lineNum
    currentLineNum
    # status line
    statusLineNormalMode
    statusLineModeNormalMode
    statusLineNormalModeInactive
    statusLineInsertMode
    statusLineModeInsertMode
    statusLineInsertModeInactive
    statusLineVisualMode
    statusLineModeVisualMode
    statusLineVisualModeInactive
    statusLineReplaceMode
    statusLineModeReplaceMode
    statusLineReplaceModeInactive
    statusLineFilerMode
    statusLineModeFilerMode
    statusLineFilerModeInactive
    statusLineExMode
    statusLineModeExMode
    statusLineExModeInactive
    statusLineGitBranch
    # tab lnie
    tab
    # tab line
    currentTab
    # command bar
    commandBar
    # error message
    errorMessage
    # search result highlighting
    searchResult
    # selected area in visual mode
    visualMode

    # Color scheme
    keyword
    functionName
    typeName
    boolean
    specialVar
    builtin
    stringLit
    binNumber
    decNumber
    floatNumber
    hexNumber
    octNumber
    comment
    longComment
    whitespace
    preprocessor
    pragma

    # filer mode
    currentFile
    file
    dir
    pcLink
    # pop up window
    popupWindow
    popupWinCurrentLine
    # replace text highlighting
    replaceText
    # pair of paren highlighting
    parenText
    # other uses current word
    currentWord
    # full width space
    highlightFullWidthSpace
    # trailing spaces
    highlightTrailingSpaces
    # reserved words
    reservedWord
    # Backup manager
    currentBackup
    # diff viewer
    addedLine
    deletedLine
    # configuration mode
    currentSetting
    # highlight curent line background
    currentLineBg

  Color* = object
    index*: EditorColorIndex
    rgb*: Rgb

  ColorPair* = object
    foreground*: Color
    background*: Color

  ThemeColors* = array[EditorColorPairIndex, ColorPair]

const
  TerminalDefaultRgb* = Rgb(red: -1, green: -1, blue: -1)

  ## Default terminal colors.
  DefaultForegroundColor* = Color(
    index: termDefaultForeground,
    rgb: TerminalDefaultRgb)
  DefaultBackgoundColor* = Color(
    index: termDefaultBackground,
    rgb: TerminalDefaultRgb)

  DarkTheme*: ThemeColors = [
    EditorColorPairIndex.default: ColorPair(
      foreground: Color(
        index: EditorColorIndex.foreground,
        rgb: "#ffffff".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.background,
        rgb: TerminalDefaultRgb)),

    EditorColorPairIndex.lineNum: ColorPair(
      foreground: Color(
        index: EditorColorIndex.lineNum,
        rgb: "#8a8a8a".hexToRgb.get),
      background:  Color(
        index: EditorColorIndex.lineNumBg,
        rgb: TerminalDefaultRgb)),
    EditorColorPairIndex.currentLineNum: ColorPair(
      foreground: Color(
        index: EditorColorIndex.currentLineNum,
        rgb: "#008080".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.currentLineNumBg,
        rgb: TerminalDefaultRgb)),

    EditorColorPairIndex.statusLineNormalMode: ColorPair(
      foreground: Color(
        index: EditorColorIndex.statusLineNormalMode,
        rgb: "#ffffff".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.statusLineNormalModeBg,
        rgb: "#0000ff".hexToRgb.get)),
    EditorColorPairIndex.statusLineModeNormalMode: ColorPair(
      foreground: Color(
        index: EditorColorIndex.statusLineModeNormalMode,
        rgb: "#000000".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.statusLineModeNormalModeBg,
        rgb: "#ffffff".hexToRgb.get)),
    EditorColorPairIndex.statusLineNormalModeInactive: ColorPair(
      foreground: Color(
        index: EditorColorIndex.statusLineNormalModeInactive,
        rgb: "#0000ff".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.statusLineNormalModeInactiveBg,
        rgb: "#ffffff".hexToRgb.get)),

    EditorColorPairIndex.statusLineInsertMode: ColorPair(
      foreground: Color(
        index: EditorColorIndex.statusLineInsertMode,
        rgb: "#ffffff".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.statusLineInsertModeBg,
        rgb: "#0000ff".hexToRgb.get)),
    EditorColorPairIndex.statusLineModeInsertMode: ColorPair(
      foreground: Color(
        index: EditorColorIndex.statusLineModeInsertMode,
        rgb: "#000000".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.statusLineModeInsertModeBg,
        rgb: "#ffffff".hexToRgb.get)),
    EditorColorPairIndex.statusLineInsertModeInactive: ColorPair(
      foreground: Color(
        index: EditorColorIndex.statusLineInsertModeInactive,
        rgb: "#0000ff".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.statusLineInsertModeInactiveBg,
        rgb: "#ffffff".hexToRgb.get)),

    EditorColorPairIndex.statusLineVisualMode: ColorPair(
      foreground: Color(
        index: EditorColorIndex.statusLineVisualMode,
        rgb: "#ffffff".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.statusLineVisualModeBg,
        rgb: "#0000ff".hexToRgb.get)),
    EditorColorPairIndex.statusLineModeVisualMode: ColorPair(
      foreground: Color(
        index: EditorColorIndex.statusLineModeVisualMode,
        rgb: "#000000".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.statusLineModeVisualModeBg,
        rgb: "#ffffff".hexToRgb.get)),
    EditorColorPairIndex.statusLineVisualModeInactive: ColorPair(
      foreground: Color(
        index: EditorColorIndex.statusLineVisualModeInactive,
        rgb: "#0000ff".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.statusLineVisualModeInactiveBg,
        rgb: "#ffffff".hexToRgb.get)),

    EditorColorPairIndex.statusLineReplaceMode: ColorPair(
      foreground: Color(
        index: EditorColorIndex.statusLineReplaceMode,
        rgb: "#ffffff".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.statusLineReplaceModeBg,
        rgb: "#0000ff".hexToRgb.get)),
    EditorColorPairIndex.statusLineModeReplaceMode: ColorPair(
      foreground: Color(
        index: EditorColorIndex.statusLineModeReplaceMode,
        rgb: "#000000".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.statusLineModeReplaceModeBg,
        rgb: "#ffffff".hexToRgb.get)),
    EditorColorPairIndex.statusLineReplaceModeInactive: ColorPair(
      foreground: Color(
        index: EditorColorIndex.statusLineReplaceModeInactive,
        rgb: "#0000ff".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.statusLineReplaceModeInactiveBg,
        rgb: "#ffffff".hexToRgb.get)),

    EditorColorPairIndex.statusLineFilerMode: ColorPair(
      foreground: Color(
        index: EditorColorIndex.statusLineReplaceModeInactive,
        rgb: "#ffffff".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.statusLineReplaceModeInactiveBg,
        rgb: "#0000ff".hexToRgb.get)),
    EditorColorPairIndex.statusLineModeFilerMode: ColorPair(
      foreground: Color(
        index: EditorColorIndex.statusLineModeFilerMode,
        rgb: "#000000".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.statusLineModeFilerModeBg,
        rgb: "#ffffff".hexToRgb.get)),
    EditorColorPairIndex.statusLineFilerModeInactive: ColorPair(
      foreground: Color(
        index: EditorColorIndex.statusLineFilerModeInactive,
        rgb: "#0000ff".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.statusLineFilerModeInactiveBg,
        rgb: "#ffffff".hexToRgb.get)),

    EditorColorPairIndex.statusLineExMode: ColorPair(
      foreground: Color(
        index: EditorColorIndex.statusLineExMode,
        rgb: "#ffffff".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.statusLineExModeBg,
        rgb: "#0000ff".hexToRgb.get)),
    EditorColorPairIndex.statusLineModeExMode: ColorPair(
      foreground: Color(
        index: EditorColorIndex.statusLineModeExMode,
        rgb: "#000000".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.statusLineModeExModeBg,
        rgb: "#ffffff".hexToRgb.get)),
    EditorColorPairIndex.statusLineExModeInactive: ColorPair(
      foreground: Color(
        index: EditorColorIndex.statusLineExModeInactive,
        rgb: "#0000ff".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.statusLineExModeInactiveBg,
        rgb: "#ffffff".hexToRgb.get)),

    EditorColorPairIndex.statusLineGitBranch: ColorPair(
      foreground: Color(
        index: EditorColorIndex.statusLineGitBranch,
        rgb: "#ffffff".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.statusLineGitBranchBg,
        rgb: "#0000ff".hexToRgb.get)),

    # Tab line
    EditorColorPairIndex.tab: ColorPair(
      foreground: Color(
        index: EditorColorIndex.tab,
        rgb: "#ffffff".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.tabBg,
        rgb: TerminalDefaultRgb)),

    EditorColorPairIndex.currentTab: ColorPair(
      foreground: Color(
        index: EditorColorIndex.currentTab,
        rgb: "#ffffff".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.currentTabBg,
        rgb: "#0000ff".hexToRgb.get)),

    # Command line
    # TODO: Rename to commandLine
    EditorColorPairIndex.commandBar: ColorPair(
      foreground: Color(
        index: EditorColorIndex.commandBar,
        rgb: "#ffffff".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.commandBarBg,
        rgb: TerminalDefaultRgb)),

    # Error message
    EditorColorPairIndex.errorMessage: ColorPair(
      foreground: Color(
        index: EditorColorIndex.errorMessage,
        rgb: "#ff0000".hexToRgb.get),
      background: DefaultBackgoundColor),

    # Search result highlighting
    EditorColorPairIndex.searchResult: ColorPair(
      foreground: Color(
        index: EditorColorIndex.searchResult,
        rgb: "#ffffff".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.searchResultBg,
        rgb: "#ff0000".hexToRgb.get)),

    # Selected area in Visual mode
    EditorColorPairIndex.visualMode: ColorPair(
      foreground: Color(
        index: EditorColorIndex.visualMode,
        rgb: "#ffffff".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.visualModeBg,
        rgb: "#800080".hexToRgb.get)),

    # Color scheme
    EditorColorPairIndex.keyword: ColorPair(
      foreground: Color(
        index: EditorColorIndex.keyword,
        rgb: "#87d7ff".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.keywordBg,
        rgb: TerminalDefaultRgb)),

    EditorColorPairIndex.functionName: ColorPair(
      foreground: Color(
        index: EditorColorIndex.functionName,
        rgb: "#ffd700".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.functionNameBg,
        rgb: TerminalDefaultRgb)),

    EditorColorPairIndex.typeName: ColorPair(
      foreground: Color(
        index: EditorColorIndex.typeName,
        rgb: "#008000".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.typeNameBg,
        rgb: TerminalDefaultRgb)),

    EditorColorPairIndex.boolean: ColorPair(
      foreground: Color(
        index: EditorColorIndex.boolean,
        rgb: "#ffff00".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.booleanBg,
        rgb: TerminalDefaultRgb)),

    EditorColorPairIndex.specialVar: ColorPair(
      foreground: Color(
        index: EditorColorIndex.specialVar,
        rgb: "#008000".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.specialVarBg,
        rgb: TerminalDefaultRgb)),

    EditorColorPairIndex.builtin: ColorPair(
      foreground: Color(
        index: EditorColorIndex.builtin,
        rgb: "#ffff00".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.builtinBg,
        rgb: TerminalDefaultRgb)),

    EditorColorPairIndex.stringLit: ColorPair(
      foreground: Color(
        index: EditorColorIndex.stringLit,
        rgb: "#ffff00".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.stringLitBg,
        rgb: TerminalDefaultRgb)),

    EditorColorPairIndex.binNumber: ColorPair(
      foreground: Color(
        index: EditorColorIndex.binNumber,
        rgb: "#00ffff".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.binNumberBg,
        rgb: TerminalDefaultRgb)),

    EditorColorPairIndex.decNumber: ColorPair(
      foreground: Color(
        index: EditorColorIndex.decNumber,
        rgb: "#00ffff".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.decNumber,
        rgb: TerminalDefaultRgb)),

    EditorColorPairIndex.floatNumber: ColorPair(
      foreground: Color(
        index: EditorColorIndex.floatNumber,
        rgb: "#00ffff".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.floatNumberBg,
        rgb: TerminalDefaultRgb)),

    EditorColorPairIndex.hexNumber: ColorPair(
      foreground: Color(
        index: EditorColorIndex.hexNumber,
        rgb: "#00ffff".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.hexNumberBg,
        rgb: TerminalDefaultRgb)),

    EditorColorPairIndex.octNumber: ColorPair(
      foreground: Color(
        index: EditorColorIndex.octNumber,
        rgb: "#00ffff".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.octNumber,
        rgb: TerminalDefaultRgb)),

    EditorColorPairIndex.comment: ColorPair(
      foreground: Color(
        index: EditorColorIndex.comment,
        rgb: "#808080".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.commentBg,
        rgb: TerminalDefaultRgb)),

    EditorColorPairIndex.longComment: ColorPair(
      foreground: Color(
        index: EditorColorIndex.longComment,
        rgb: "#808080".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.longComment,
        rgb: TerminalDefaultRgb)),

    EditorColorPairIndex.whitespace: ColorPair(
      foreground: Color(
        index: EditorColorIndex.whitespace,
        rgb: "#808080".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.whitespaceBg,
        rgb: TerminalDefaultRgb)),

    EditorColorPairIndex.preprocessor: ColorPair(
      foreground: Color(
        index: EditorColorIndex.preprocessor,
        rgb: "#008000".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.preprocessorBg,
        rgb: TerminalDefaultRgb)),

    EditorColorPairIndex.pragma: ColorPair(
      foreground: Color(
        index: EditorColorIndex.pragma,
        rgb: "#ffff00".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.pragmaBg,
        rgb: TerminalDefaultRgb)),

    # filer mode
    EditorColorPairIndex.currentFile: ColorPair(
      foreground: Color(
        index: EditorColorIndex.currentFile,
        rgb: "#ffffff".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.currentFileBg,
        rgb: "#008080".hexToRgb.get)),

    EditorColorPairIndex.file: ColorPair(
      foreground: Color(
        index: EditorColorIndex.file,
        rgb: "#ffffff".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.fileBg,
        rgb: TerminalDefaultRgb)),

    EditorColorPairIndex.dir: ColorPair(
      foreground: Color(
        index: EditorColorIndex.dir,
        rgb: "#0000ff".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.fileBg,
        rgb: TerminalDefaultRgb)),

    EditorColorPairIndex.pcLink: ColorPair(
      foreground: Color(
        index: EditorColorIndex.pcLink,
        rgb: "#008080".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.pcLinkBg,
        rgb: TerminalDefaultRgb)),

    # Pop up window
    EditorColorPairIndex.popupWindow: ColorPair(
      foreground: Color(
        index: EditorColorIndex.popupWindow,
        rgb: "#ffffff".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.popupWindowBg,
        rgb: "#000000".hexToRgb.get)),
    EditorColorPairIndex.popupWinCurrentLine: ColorPair(
      foreground: Color(
        index: EditorColorIndex.popupWinCurrentLine,
        rgb: "#0000ff".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.popupWinCurrentLineBg,
        rgb: "#000000".hexToRgb.get)),

    # Replace text highlighting
    EditorColorPairIndex.replaceText: ColorPair(
      foreground: Color(
        index: EditorColorIndex.replaceText,
        rgb: "#ffffff".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.replaceTextBg,
        rgb: "#ff0000".hexToRgb.get)),

    # Pair of paren highlighting
    # TODO: Rename to parenPair?
    EditorColorPairIndex.parenText: ColorPair(
      foreground: Color(
        index: EditorColorIndex.parenText,
        rgb: "#ffffff".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.parenTextBg,
        rgb: "#0000ff".hexToRgb.get)),

    # highlight other uses current word
    EditorColorPairIndex.currentWord: ColorPair(
      foreground: Color(
        index: EditorColorIndex.currentWord,
        rgb: "#ffffff".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.currentWordBg,
        rgb: "#808080".hexToRgb.get)),

    # highlight full width space
    EditorColorPairIndex.highlightFullWidthSpace: ColorPair(
      foreground: Color(
        index: EditorColorIndex.highlightFullWidthSpace,
        rgb: "#ff0000".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.highlightFullWidthSpaceBg,
        rgb: "#ff0000".hexToRgb.get)),

    # highlight trailing spaces
    EditorColorPairIndex.highlightTrailingSpaces: ColorPair(
      foreground: Color(
        index: EditorColorIndex.highlightTrailingSpaces,
        rgb: "#ff0000".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.highlightTrailingSpacesBg,
        rgb: "#ff0000".hexToRgb.get)),

    # highlight reserved words
    EditorColorPairIndex.reservedWord: ColorPair(
      foreground: Color(
        index: EditorColorIndex.reservedWord,
        rgb: "#ffffff".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.reservedWordBg,
        rgb: "#808080".hexToRgb.get)),

    # Backup manager
    # TODO: Rename to BackupManagerCurrentLine?
    EditorColorPairIndex.currentBackup: ColorPair(
      foreground: Color(
        index: EditorColorIndex.currentBackup,
        rgb: "#ffffff".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.currentBackupBg,
        rgb: "#008080".hexToRgb.get)),

    # Diff viewer
    # TODO: Ranme to diffViewerAddedLine?
    EditorColorPairIndex.addedLine: ColorPair(
      foreground: Color(
        index: EditorColorIndex.addedLine,
        rgb: "#008000".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.addedLineBg,
        rgb: TerminalDefaultRgb)),

    # TODO: Ranme to diffViewerDeletedLine ?
    EditorColorPairIndex.deletedLine: ColorPair(
      foreground: Color(
        index: EditorColorIndex.deletedLine,
        rgb: "#ff0000".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.deletedLineBg,
        rgb: TerminalDefaultRgb)),

    # Configuration mode
    # TODO: Ranme to ConfiModeCurrentLine?
    EditorColorPairIndex.currentSetting: ColorPair(
      foreground: Color(
        index: EditorColorIndex.currentSetting,
        rgb: "#ffffff".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.currentSettingBg,
        rgb: "#008080".hexToRgb.get)),

    EditorColorPairIndex.currentLineBg: ColorPair(
      # Don't use the foreground.
      foreground: DefaultForegroundColor,
      background: Color(
        index: EditorColorIndex.currentLineBg,
        rgb: "#000000".hexToRgb.get))
  ]

  LightTheme*: ThemeColors = [
    EditorColorPairIndex.default: ColorPair(
      foreground: Color(
        index: EditorColorIndex.foreground,
        rgb: "#000000".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.background,
        rgb: TerminalDefaultRgb)),

    EditorColorPairIndex.lineNum: ColorPair(
      foreground: Color(
        index: EditorColorIndex.lineNum,
        rgb: "#8a8a8a".hexToRgb.get),
      background:  Color(
        index: EditorColorIndex.lineNumBg,
        rgb: TerminalDefaultRgb)),
    EditorColorPairIndex.currentLineNum: ColorPair(
      foreground: Color(
        index: EditorColorIndex.currentLineNum,
        rgb: "#000000".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.currentLineNumBg,
        rgb: TerminalDefaultRgb)),

    EditorColorPairIndex.statusLineNormalMode: ColorPair(
      foreground: Color(
        index: EditorColorIndex.statusLineNormalMode,
        rgb: "#0000ff".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.statusLineNormalModeBg,
        rgb: "#8a8a8a".hexToRgb.get)),
    EditorColorPairIndex.statusLineModeNormalMode: ColorPair(
      foreground: Color(
        index: EditorColorIndex.statusLineModeNormalMode,
        rgb: "#ffffff".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.statusLineModeNormalModeBg,
        rgb: "#008080".hexToRgb.get)),
    EditorColorPairIndex.statusLineNormalModeInactive: ColorPair(
      foreground: Color(
        index: EditorColorIndex.statusLineNormalModeInactive,
        rgb: "#008080".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.statusLineNormalModeInactiveBg,
        rgb: "#0000ff".hexToRgb.get)),

    EditorColorPairIndex.statusLineInsertMode: ColorPair(
      foreground: Color(
        index: EditorColorIndex.statusLineInsertMode,
        rgb: "#0000ff".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.statusLineInsertModeBg,
        rgb: "#8a8a8a".hexToRgb.get)),
    EditorColorPairIndex.statusLineModeInsertMode: ColorPair(
      foreground: Color(
        index: EditorColorIndex.statusLineModeInsertMode,
        rgb: "#ffffff".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.statusLineModeInsertModeBg,
        rgb: "#008080".hexToRgb.get)),
    EditorColorPairIndex.statusLineInsertModeInactive: ColorPair(
      foreground: Color(
        index: EditorColorIndex.statusLineInsertModeInactive,
        rgb: "#8a8a8a".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.statusLineInsertModeInactiveBg,
        rgb: "#0000ff".hexToRgb.get)),

    EditorColorPairIndex.statusLineVisualMode: ColorPair(
      foreground: Color(
        index: EditorColorIndex.statusLineVisualMode,
        rgb: "#0000ff".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.statusLineVisualModeBg,
        rgb: "#8a8a8a".hexToRgb.get)),
    EditorColorPairIndex.statusLineModeVisualMode: ColorPair(
      foreground: Color(
        index: EditorColorIndex.statusLineModeVisualMode,
        rgb: "#ffffff".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.statusLineModeVisualModeBg,
        rgb: "#008080".hexToRgb.get)),
    EditorColorPairIndex.statusLineVisualModeInactive: ColorPair(
      foreground: Color(
        index: EditorColorIndex.statusLineVisualModeInactive,
        rgb: "#8a8a8a".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.statusLineVisualModeInactiveBg,
        rgb: "#0000ff".hexToRgb.get)),

    EditorColorPairIndex.statusLineReplaceMode: ColorPair(
      foreground: Color(
        index: EditorColorIndex.statusLineReplaceMode,
        rgb: "#0000ff".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.statusLineReplaceModeBg,
        rgb: "#8a8a8a".hexToRgb.get)),
    EditorColorPairIndex.statusLineModeReplaceMode: ColorPair(
      foreground: Color(
        index: EditorColorIndex.statusLineModeReplaceMode,
        rgb: "#ffffff".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.statusLineModeReplaceModeBg,
        rgb: "#008080".hexToRgb.get)),
    EditorColorPairIndex.statusLineReplaceModeInactive: ColorPair(
      foreground: Color(
        index: EditorColorIndex.statusLineReplaceModeInactive,
        rgb: "#8a8a8a".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.statusLineReplaceModeInactiveBg,
        rgb: "#0000ff".hexToRgb.get)),

    EditorColorPairIndex.statusLineFilerMode: ColorPair(
      foreground: Color(
        index: EditorColorIndex.statusLineReplaceModeInactive,
        rgb: "#0000ff".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.statusLineReplaceModeInactiveBg,
        rgb: "#8a8a8a".hexToRgb.get)),
    EditorColorPairIndex.statusLineModeFilerMode: ColorPair(
      foreground: Color(
        index: EditorColorIndex.statusLineModeFilerMode,
        rgb: "#ffffff".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.statusLineModeFilerModeBg,
        rgb: "#008080".hexToRgb.get)),
    EditorColorPairIndex.statusLineFilerModeInactive: ColorPair(
      foreground: Color(
        index: EditorColorIndex.statusLineFilerModeInactive,
        rgb: "#8a8a8a".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.statusLineFilerModeInactiveBg,
        rgb: "#0000ff".hexToRgb.get)),

    EditorColorPairIndex.statusLineExMode: ColorPair(
      foreground: Color(
        index: EditorColorIndex.statusLineExMode,
        rgb: "#0000ff".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.statusLineExModeBg,
        rgb: "#008080".hexToRgb.get)),
    EditorColorPairIndex.statusLineModeExMode: ColorPair(
      foreground: Color(
        index: EditorColorIndex.statusLineModeExMode,
        rgb: "#ffffff".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.statusLineModeExModeBg,
        rgb: "#008080".hexToRgb.get)),
    EditorColorPairIndex.statusLineExModeInactive: ColorPair(
      foreground: Color(
        index: EditorColorIndex.statusLineExModeInactive,
        rgb: "#8a8a8a".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.statusLineExModeInactiveBg,
        rgb: "#0000ff".hexToRgb.get)),

    EditorColorPairIndex.statusLineGitBranch: ColorPair(
      foreground: Color(
        index: EditorColorIndex.statusLineGitBranch,
        rgb: "#0000ff".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.statusLineGitBranchBg,
        rgb: "#8a8a8a".hexToRgb.get)),

    # Tab line
    EditorColorPairIndex.tab: ColorPair(
      foreground: Color(
        index: EditorColorIndex.tab,
        rgb: "#0000ff".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.tabBg,
        rgb: "#8a8a8a".hexToRgb.get)),

    EditorColorPairIndex.currentTab: ColorPair(
      foreground: Color(
        index: EditorColorIndex.currentTab,
        rgb: "#ffffff".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.currentTabBg,
        rgb: "#0000ff".hexToRgb.get)),

    # Command line
    # TODO: Rename to commandLine
    EditorColorPairIndex.commandBar: ColorPair(
      foreground: Color(
        index: EditorColorIndex.commandBar,
        rgb: "#000000".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.commandBarBg,
        rgb: TerminalDefaultRgb)),

    # Error message
    EditorColorPairIndex.errorMessage: ColorPair(
      foreground: Color(
        index: EditorColorIndex.errorMessage,
        rgb: "#ff0000".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.errorMessageBg,
        rgb: TerminalDefaultRgb)),

    # Search result highlighting
    EditorColorPairIndex.searchResult: ColorPair(
      foreground: Color(
        index: EditorColorIndex.searchResult,
        rgb: "#000000".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.searchResultBg,
        rgb: "#ff0000".hexToRgb.get)),

    # Selected area in Visual mode
    EditorColorPairIndex.visualMode: ColorPair(
      foreground: Color(
        index: EditorColorIndex.visualMode,
        rgb: "#000000".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.visualModeBg,
        rgb: "#800080".hexToRgb.get)),

    # Color scheme
    EditorColorPairIndex.keyword: ColorPair(
      foreground: Color(
        index: EditorColorIndex.keyword,
        rgb: "#5fffaf".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.keywordBg,
        rgb: TerminalDefaultRgb)),

    EditorColorPairIndex.functionName: ColorPair(
      foreground: Color(
        index: EditorColorIndex.functionName,
        rgb: "#ffd700".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.functionNameBg,
        rgb: TerminalDefaultRgb)),

    EditorColorPairIndex.typeName: ColorPair(
      foreground: Color(
        index: EditorColorIndex.typeName,
        rgb: "#008000".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.typeNameBg,
        rgb: TerminalDefaultRgb)),

    EditorColorPairIndex.boolean: ColorPair(
      foreground: Color(
        index: EditorColorIndex.boolean,
        rgb: "#ffff00".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.booleanBg,
        rgb: TerminalDefaultRgb)),

    EditorColorPairIndex.specialVar: ColorPair(
      foreground: Color(
        index: EditorColorIndex.specialVar,
        rgb: "#008000".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.specialVarBg,
        rgb: TerminalDefaultRgb)),

    EditorColorPairIndex.builtin: ColorPair(
      foreground: Color(
        index: EditorColorIndex.builtin,
        rgb: "#ffff00".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.builtinBg,
        rgb: TerminalDefaultRgb)),

    EditorColorPairIndex.stringLit: ColorPair(
      foreground: Color(
        index: EditorColorIndex.stringLit,
        rgb: "#800080".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.stringLitBg,
        rgb: TerminalDefaultRgb)),

    EditorColorPairIndex.binNumber: ColorPair(
      foreground: Color(
        index: EditorColorIndex.binNumber,
        rgb: "#00ffff".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.binNumberBg,
        rgb: TerminalDefaultRgb)),

    EditorColorPairIndex.decNumber: ColorPair(
      foreground: Color(
        index: EditorColorIndex.decNumber,
        rgb: "#00ffff".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.decNumber,
        rgb: TerminalDefaultRgb)),

    EditorColorPairIndex.floatNumber: ColorPair(
      foreground: Color(
        index: EditorColorIndex.floatNumber,
        rgb: "#00ffff".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.floatNumberBg,
        rgb: TerminalDefaultRgb)),

    EditorColorPairIndex.hexNumber: ColorPair(
      foreground: Color(
        index: EditorColorIndex.hexNumber,
        rgb: "#00ffff".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.hexNumberBg,
        rgb: TerminalDefaultRgb)),

    EditorColorPairIndex.octNumber: ColorPair(
      foreground: Color(
        index: EditorColorIndex.octNumber,
        rgb: "#00ffff".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.octNumber,
        rgb: TerminalDefaultRgb)),

    EditorColorPairIndex.comment: ColorPair(
      foreground: Color(
        index: EditorColorIndex.comment,
        rgb: "#808080".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.commentBg,
        rgb: TerminalDefaultRgb)),

    EditorColorPairIndex.longComment: ColorPair(
      foreground: Color(
        index: EditorColorIndex.longComment,
        rgb: "#808080".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.longComment,
        rgb: TerminalDefaultRgb)),

    EditorColorPairIndex.whitespace: ColorPair(
      foreground: Color(
        index: EditorColorIndex.whitespace,
        rgb: "#808080".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.whitespaceBg,
        rgb: TerminalDefaultRgb)),

    EditorColorPairIndex.preprocessor: ColorPair(
      foreground: Color(
        index: EditorColorIndex.preprocessor,
        rgb: "#808080".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.preprocessorBg,
        rgb: TerminalDefaultRgb)),

    EditorColorPairIndex.pragma: ColorPair(
      foreground: Color(
        index: EditorColorIndex.pragma,
        rgb: "#ffff00".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.pragmaBg,
        rgb: TerminalDefaultRgb)),

    # filer mode
    EditorColorPairIndex.currentFile: ColorPair(
      foreground: Color(
        index: EditorColorIndex.currentFile,
        rgb: "#000000".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.currentFileBg,
        rgb: "#ff0087".hexToRgb.get)),

    EditorColorPairIndex.file: ColorPair(
      foreground: Color(
        index: EditorColorIndex.file,
        rgb: "#000000".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.fileBg,
        rgb: TerminalDefaultRgb)),

    EditorColorPairIndex.dir: ColorPair(
      foreground: Color(
        index: EditorColorIndex.dir,
        rgb: "#ff0087".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.fileBg,
        rgb: TerminalDefaultRgb)),

    EditorColorPairIndex.pcLink: ColorPair(
      foreground: Color(
        index: EditorColorIndex.pcLink,
        rgb: "#008080".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.pcLinkBg,
        rgb: TerminalDefaultRgb)),

    # Pop up window
    EditorColorPairIndex.popupWindow: ColorPair(
      foreground: Color(
        index: EditorColorIndex.popupWindow,
        rgb: "#000000".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.popupWindowBg,
        rgb: "#808080".hexToRgb.get)),
    EditorColorPairIndex.popupWinCurrentLine: ColorPair(
      foreground: Color(
        index: EditorColorIndex.popupWinCurrentLine,
        rgb: "#0000ff".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.popupWinCurrentLineBg,
        rgb: "#808080".hexToRgb.get)),

    # Replace text highlighting
    EditorColorPairIndex.replaceText: ColorPair(
      foreground: Color(
        index: EditorColorIndex.replaceText,
        rgb: "#000000".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.replaceTextBg,
        rgb: "#ff0000".hexToRgb.get)),

    # Pair of paren highlighting
    # TODO: Rename to parenPair?
    EditorColorPairIndex.parenText: ColorPair(
      foreground: Color(
        index: EditorColorIndex.parenText,
        rgb: "#000000".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.parenTextBg,
        rgb: "#808080".hexToRgb.get)),

    # highlight other uses current word
    EditorColorPairIndex.currentWord: ColorPair(
      foreground: Color(
        index: EditorColorIndex.currentWord,
        rgb: "#000000".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.currentWordBg,
        rgb: "#808080".hexToRgb.get)),

    # highlight full width space
    EditorColorPairIndex.highlightFullWidthSpace: ColorPair(
      foreground: Color(
        index: EditorColorIndex.highlightFullWidthSpace,
        rgb: "#ff0000".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.highlightFullWidthSpaceBg,
        rgb: "#ff0000".hexToRgb.get)),

    # highlight trailing spaces
    EditorColorPairIndex.highlightTrailingSpaces: ColorPair(
      foreground: Color(
        index: EditorColorIndex.highlightTrailingSpaces,
        rgb: "#ff0000".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.highlightTrailingSpacesBg,
        rgb: "#ff0000".hexToRgb.get)),

    # highlight reserved words
    EditorColorPairIndex.reservedWord: ColorPair(
      foreground: Color(
        index: EditorColorIndex.reservedWord,
        rgb: "#ffffff".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.reservedWordBg,
        rgb: "#808080".hexToRgb.get)),

    # Backup manager
    # TODO: Rename to BackupManagerCurrentLine?
    EditorColorPairIndex.currentBackup: ColorPair(
      foreground: Color(
        index: EditorColorIndex.currentBackup,
        rgb: "#000000".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.currentBackupBg,
        rgb: "#ff0087".hexToRgb.get)),

    # Diff viewer
    # TODO: Ranme to diffViewerAddedLine?
    EditorColorPairIndex.addedLine: ColorPair(
      foreground: Color(
        index: EditorColorIndex.addedLine,
        rgb: "#008000".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.addedLineBg,
        rgb: TerminalDefaultRgb)),

    # TODO: Ranme to diffViewerDeletedLine ?
    EditorColorPairIndex.deletedLine: ColorPair(
      foreground: Color(
        index: EditorColorIndex.deletedLine,
        rgb: "#ff0000".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.deletedLineBg,
        rgb: TerminalDefaultRgb)),

    # Configuration mode
    # TODO: Ranme to ConfiModeCurrentLine?
    EditorColorPairIndex.currentSetting: ColorPair(
      foreground: Color(
        index: EditorColorIndex.currentSetting,
        rgb: "#000000".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.currentSettingBg,
        rgb: "#ff0087".hexToRgb.get)),

    EditorColorPairIndex.currentLineBg: ColorPair(
      # Don't use the foreground.
      foreground: DefaultForegroundColor,
      background: Color(
        index: EditorColorIndex.currentLineBg,
        rgb: "#444444".hexToRgb.get))
  ]

  VividTheme*: ThemeColors = [
    EditorColorPairIndex.default: ColorPair(
      foreground: Color(
        index: EditorColorIndex.foreground,
        rgb: "#ffffff".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.background,
        rgb: TerminalDefaultRgb)),

    EditorColorPairIndex.lineNum: ColorPair(
      foreground: Color(
        index: EditorColorIndex.lineNum,
        rgb: "#8a8a8a".hexToRgb.get),
      background:  Color(
        index: EditorColorIndex.lineNumBg,
        rgb: TerminalDefaultRgb)),
    EditorColorPairIndex.currentLineNum: ColorPair(
      foreground: Color(
        index: EditorColorIndex.currentLineNum,
        rgb: "#ff0087".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.currentLineNumBg,
        rgb: TerminalDefaultRgb)),

    EditorColorPairIndex.statusLineNormalMode: ColorPair(
      foreground: Color(
        index: EditorColorIndex.statusLineNormalMode,
        rgb: "#000000".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.statusLineNormalModeBg,
        rgb: "#ff0087".hexToRgb.get)),
    EditorColorPairIndex.statusLineModeNormalMode: ColorPair(
      foreground: Color(
        index: EditorColorIndex.statusLineModeNormalMode,
        rgb: "#000000".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.statusLineModeNormalModeBg,
        rgb: "#ffffff".hexToRgb.get)),
    EditorColorPairIndex.statusLineNormalModeInactive: ColorPair(
      foreground: Color(
        index: EditorColorIndex.statusLineNormalModeInactive,
        rgb: "#ff0087".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.statusLineNormalModeInactiveBg,
        rgb: "#ffffff".hexToRgb.get)),

    EditorColorPairIndex.statusLineInsertMode: ColorPair(
      foreground: Color(
        index: EditorColorIndex.statusLineInsertMode,
        rgb: "#000000".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.statusLineInsertModeBg,
        rgb: "#ff0087".hexToRgb.get)),
    EditorColorPairIndex.statusLineModeInsertMode: ColorPair(
      foreground: Color(
        index: EditorColorIndex.statusLineModeInsertMode,
        rgb: "#000000".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.statusLineModeInsertModeBg,
        rgb: "#ffffff".hexToRgb.get)),
    EditorColorPairIndex.statusLineInsertModeInactive: ColorPair(
      foreground: Color(
        index: EditorColorIndex.statusLineInsertModeInactive,
        rgb: "#ff0087".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.statusLineInsertModeInactiveBg,
        rgb: "#ffffff".hexToRgb.get)),

    EditorColorPairIndex.statusLineVisualMode: ColorPair(
      foreground: Color(
        index: EditorColorIndex.statusLineVisualMode,
        rgb: "#000000".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.statusLineVisualModeBg,
        rgb: "#ff0087".hexToRgb.get)),
    EditorColorPairIndex.statusLineModeVisualMode: ColorPair(
      foreground: Color(
        index: EditorColorIndex.statusLineModeVisualMode,
        rgb: "#000000".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.statusLineModeVisualModeBg,
        rgb: "#ffffff".hexToRgb.get)),
    EditorColorPairIndex.statusLineVisualModeInactive: ColorPair(
      foreground: Color(
        index: EditorColorIndex.statusLineVisualModeInactive,
        rgb: "#ff0087".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.statusLineVisualModeInactiveBg,
        rgb: "#ffffff".hexToRgb.get)),

    EditorColorPairIndex.statusLineReplaceMode: ColorPair(
      foreground: Color(
        index: EditorColorIndex.statusLineReplaceMode,
        rgb: "#000000".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.statusLineReplaceModeBg,
        rgb: "#ff0087".hexToRgb.get)),
    EditorColorPairIndex.statusLineModeReplaceMode: ColorPair(
      foreground: Color(
        index: EditorColorIndex.statusLineModeReplaceMode,
        rgb: "#000000".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.statusLineModeReplaceModeBg,
        rgb: "#ffffff".hexToRgb.get)),
    EditorColorPairIndex.statusLineReplaceModeInactive: ColorPair(
      foreground: Color(
        index: EditorColorIndex.statusLineReplaceModeInactive,
        rgb: "#ff0087".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.statusLineReplaceModeInactiveBg,
        rgb: "#ffffff".hexToRgb.get)),

    EditorColorPairIndex.statusLineFilerMode: ColorPair(
      foreground: Color(
        index: EditorColorIndex.statusLineReplaceModeInactive,
        rgb: "#000000".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.statusLineReplaceModeInactiveBg,
        rgb: "#ff0087".hexToRgb.get)),
    EditorColorPairIndex.statusLineModeFilerMode: ColorPair(
      foreground: Color(
        index: EditorColorIndex.statusLineModeFilerMode,
        rgb: "#000000".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.statusLineModeFilerModeBg,
        rgb: "#ffffff".hexToRgb.get)),
    EditorColorPairIndex.statusLineFilerModeInactive: ColorPair(
      foreground: Color(
        index: EditorColorIndex.statusLineFilerModeInactive,
        rgb: "#ff0087".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.statusLineFilerModeInactiveBg,
        rgb: "#ffffff".hexToRgb.get)),

    EditorColorPairIndex.statusLineExMode: ColorPair(
      foreground: Color(
        index: EditorColorIndex.statusLineExMode,
        rgb: "#000000".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.statusLineExModeBg,
        rgb: "#ff0087".hexToRgb.get)),
    EditorColorPairIndex.statusLineModeExMode: ColorPair(
      foreground: Color(
        index: EditorColorIndex.statusLineModeExMode,
        rgb: "#000000".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.statusLineModeExModeBg,
        rgb: "#ffffff".hexToRgb.get)),
    EditorColorPairIndex.statusLineExModeInactive: ColorPair(
      foreground: Color(
        index: EditorColorIndex.statusLineExModeInactive,
        rgb: "#ff0087".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.statusLineExModeInactiveBg,
        rgb: "#ffffff".hexToRgb.get)),

    EditorColorPairIndex.statusLineGitBranch: ColorPair(
      foreground: Color(
        index: EditorColorIndex.statusLineGitBranch,
        rgb: "#ff0087".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.statusLineGitBranchBg,
        rgb: "#000000".hexToRgb.get)),

    # Tab line
    EditorColorPairIndex.tab: ColorPair(
      foreground: Color(
        index: EditorColorIndex.tab,
        rgb: "#ffffff".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.tabBg,
        rgb: TerminalDefaultRgb)),

    EditorColorPairIndex.currentTab: ColorPair(
      foreground: Color(
        index: EditorColorIndex.currentTab,
        rgb: "#000000".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.currentTabBg,
        rgb: "#ff0087".hexToRgb.get)),

    # Command line
    # TODO: Rename to commandLine
    EditorColorPairIndex.commandBar: ColorPair(
      foreground: Color(
        index: EditorColorIndex.commandBar,
        rgb: "#ffffff".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.commandBarBg,
        rgb: TerminalDefaultRgb)),

    # Error message
    EditorColorPairIndex.errorMessage: ColorPair(
      foreground: Color(
        index: EditorColorIndex.errorMessage,
        rgb: "#ff0000".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.errorMessageBg,
        rgb: TerminalDefaultRgb)),

    # Search result highlighting
    EditorColorPairIndex.searchResult: ColorPair(
      foreground: Color(
        index: EditorColorIndex.searchResult,
        rgb: "#ffffff".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.searchResultBg,
        rgb: "#ff0087".hexToRgb.get)),

    # Selected area in Visual mode
    EditorColorPairIndex.visualMode: ColorPair(
      foreground: Color(
        index: EditorColorIndex.visualMode,
        rgb: "#ffffff".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.visualModeBg,
        rgb: "#ff0087".hexToRgb.get)),

    # Color scheme
    EditorColorPairIndex.keyword: ColorPair(
      foreground: Color(
        index: EditorColorIndex.keyword,
        rgb: "#ff0087".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.keywordBg,
        rgb: TerminalDefaultRgb)),

    EditorColorPairIndex.functionName: ColorPair(
      foreground: Color(
        index: EditorColorIndex.functionName,
        rgb: "#ffd700".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.functionNameBg,
        rgb: TerminalDefaultRgb)),

    EditorColorPairIndex.typeName: ColorPair(
      foreground: Color(
        index: EditorColorIndex.typeName,
        rgb: "#ffd700".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.typeNameBg,
        rgb: TerminalDefaultRgb)),

    EditorColorPairIndex.boolean: ColorPair(
      foreground: Color(
        index: EditorColorIndex.boolean,
        rgb: "#ffff00".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.booleanBg,
        rgb: TerminalDefaultRgb)),

    EditorColorPairIndex.specialVar: ColorPair(
      foreground: Color(
        index: EditorColorIndex.specialVar,
        rgb: "#008000".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.specialVarBg,
        rgb: TerminalDefaultRgb)),

    EditorColorPairIndex.builtin: ColorPair(
      foreground: Color(
        index: EditorColorIndex.builtin,
        rgb: "#00ffff".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.builtinBg,
        rgb: TerminalDefaultRgb)),

    EditorColorPairIndex.stringLit: ColorPair(
      foreground: Color(
        index: EditorColorIndex.stringLit,
        rgb: "#ff0087".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.stringLitBg,
        rgb: TerminalDefaultRgb)),

    EditorColorPairIndex.binNumber: ColorPair(
      foreground: Color(
        index: EditorColorIndex.binNumber,
        rgb: "#00ffff".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.binNumberBg,
        rgb: TerminalDefaultRgb)),

    EditorColorPairIndex.decNumber: ColorPair(
      foreground: Color(
        index: EditorColorIndex.decNumber,
        rgb: "#00ffff".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.decNumber,
        rgb: TerminalDefaultRgb)),

    EditorColorPairIndex.floatNumber: ColorPair(
      foreground: Color(
        index: EditorColorIndex.floatNumber,
        rgb: "#00ffff".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.floatNumberBg,
        rgb: TerminalDefaultRgb)),

    EditorColorPairIndex.hexNumber: ColorPair(
      foreground: Color(
        index: EditorColorIndex.hexNumber,
        rgb: "#00ffff".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.hexNumberBg,
        rgb: TerminalDefaultRgb)),

    EditorColorPairIndex.octNumber: ColorPair(
      foreground: Color(
        index: EditorColorIndex.octNumber,
        rgb: "#00ffff".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.octNumber,
        rgb: TerminalDefaultRgb)),

    EditorColorPairIndex.comment: ColorPair(
      foreground: Color(
        index: EditorColorIndex.comment,
        rgb: "#808080".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.commentBg,
        rgb: TerminalDefaultRgb)),

    EditorColorPairIndex.longComment: ColorPair(
      foreground: Color(
        index: EditorColorIndex.longComment,
        rgb: "#808080".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.longComment,
        rgb: TerminalDefaultRgb)),

    EditorColorPairIndex.whitespace: ColorPair(
      foreground: Color(
        index: EditorColorIndex.whitespace,
        rgb: "#808080".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.whitespaceBg,
        rgb: TerminalDefaultRgb)),

    EditorColorPairIndex.preprocessor: ColorPair(
      foreground: Color(
        index: EditorColorIndex.preprocessor,
        rgb: "#808080".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.preprocessorBg,
        rgb: TerminalDefaultRgb)),

    EditorColorPairIndex.pragma: ColorPair(
      foreground: Color(
        index: EditorColorIndex.pragma,
        rgb: "#ffff00".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.pragmaBg,
        rgb: TerminalDefaultRgb)),

    # filer mode
    EditorColorPairIndex.currentFile: ColorPair(
      foreground: Color(
        index: EditorColorIndex.currentFile,
        rgb: "#ffffff".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.currentFileBg,
        rgb: "#ff0087".hexToRgb.get)),

    EditorColorPairIndex.file: ColorPair(
      foreground: Color(
        index: EditorColorIndex.file,
        rgb: "#ffffff".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.fileBg,
        rgb: TerminalDefaultRgb)),

    EditorColorPairIndex.dir: ColorPair(
      foreground: Color(
        index: EditorColorIndex.dir,
        rgb: "#ff0087".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.fileBg,
        rgb: TerminalDefaultRgb)),

    EditorColorPairIndex.pcLink: ColorPair(
      foreground: Color(
        index: EditorColorIndex.pcLink,
        rgb: "#00ffff".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.pcLinkBg,
        rgb: TerminalDefaultRgb)),

    # Pop up window
    EditorColorPairIndex.popupWindow: ColorPair(
      foreground: Color(
        index: EditorColorIndex.popupWindow,
        rgb: "#ffffff".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.popupWindowBg,
        rgb: "#000000".hexToRgb.get)),
    EditorColorPairIndex.popupWinCurrentLine: ColorPair(
      foreground: Color(
        index: EditorColorIndex.popupWinCurrentLine,
        rgb: "#ff0087".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.popupWinCurrentLineBg,
        rgb: "#000000".hexToRgb.get)),

    # Replace text highlighting
    EditorColorPairIndex.replaceText: ColorPair(
      foreground: Color(
        index: EditorColorIndex.replaceText,
        rgb: "#000000".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.replaceTextBg,
        rgb: "#ff0087".hexToRgb.get)),

    # Pair of paren highlighting
    # TODO: Rename to parenPair?
    EditorColorPairIndex.parenText: ColorPair(
      foreground: Color(
        index: EditorColorIndex.parenText,
        rgb: "#000000".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.parenTextBg,
        rgb: "#808080".hexToRgb.get)),

    # highlight other uses current word
    EditorColorPairIndex.currentWord: ColorPair(
      foreground: Color(
        index: EditorColorIndex.currentWord,
        rgb: "#000000".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.currentWordBg,
        rgb: "#808080".hexToRgb.get)),

    # highlight full width space
    EditorColorPairIndex.highlightFullWidthSpace: ColorPair(
      foreground: Color(
        index: EditorColorIndex.highlightFullWidthSpace,
        rgb: "#ff0000".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.highlightFullWidthSpaceBg,
        rgb: "#ff0000".hexToRgb.get)),

    # highlight trailing spaces
    EditorColorPairIndex.highlightTrailingSpaces: ColorPair(
      foreground: Color(
        index: EditorColorIndex.highlightTrailingSpaces,
        rgb: "#ff0000".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.highlightTrailingSpacesBg,
        rgb: "#ff0000".hexToRgb.get)),

    # highlight reserved words
    EditorColorPairIndex.reservedWord: ColorPair(
      foreground: Color(
        index: EditorColorIndex.reservedWord,
        rgb: "#ff0087".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.reservedWordBg,
        rgb: "#000000".hexToRgb.get)),

    # Backup manager
    # TODO: Rename to BackupManagerCurrentLine?
    EditorColorPairIndex.currentBackup: ColorPair(
      foreground: Color(
        index: EditorColorIndex.currentBackup,
        rgb: "#ffffff".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.currentBackupBg,
        rgb: "#ff0087".hexToRgb.get)),

    # Diff viewer
    # TODO: Ranme to diffViewerAddedLine?
    EditorColorPairIndex.addedLine: ColorPair(
      foreground: Color(
        index: EditorColorIndex.addedLine,
        rgb: "#008000".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.addedLineBg,
        rgb: TerminalDefaultRgb)),

    # TODO: Ranme to diffViewerDeletedLine ?
    EditorColorPairIndex.deletedLine: ColorPair(
      foreground: Color(
        index: EditorColorIndex.deletedLine,
        rgb: "#ff0000".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.deletedLineBg,
        rgb: TerminalDefaultRgb)),

    # Configuration mode
    # TODO: Ranme to ConfiModeCurrentLine?
    EditorColorPairIndex.currentSetting: ColorPair(
      foreground: Color(
        index: EditorColorIndex.currentSetting,
        rgb: "#ffffff".hexToRgb.get),
      background: Color(
        index: EditorColorIndex.currentSettingBg,
        rgb: "#ff0087".hexToRgb.get)),

    EditorColorPairIndex.currentLineBg: ColorPair(
      # Don't use the foreground.
      foreground: DefaultForegroundColor,
      background: Color(
        index: EditorColorIndex.currentLineBg,
        rgb: "#444444".hexToRgb.get))
  ]

var
  ColorThemeTable*: array[ColorTheme, ThemeColors] = [
    dark: DarkTheme,
    light: LightTheme,
    vivid: VividTheme,
    config: DarkTheme,
    vscode: DarkTheme
  ]

proc isTermDefaultColor*(i: EditorColorIndex): bool {.inline.} =
  i == termDefaultForeground or i == termDefaultBackground

## Init a Rgb definition of Color.
proc initColor*(c: Color) {.inline.} =
  if not (c.rgb.isTermDefaultColor or c.index.isTermDefaultColor):
    c.index.int16.initNcursesColor(c.rgb.red, c.rgb.green, c.rgb.blue)

## Init a Ncurses color pair.
proc initColorPair*(
  pairIndex: EditorColorPairIndex | int,
  foreground, background: Color) =

    let
      fg: int16 =
        if foreground.rgb.isTermDefaultColor: -1
        else: foreground.index.int16
      bg: int16 =
        if background.rgb.isTermDefaultColor: -1
        else: background.index.int16

    initNcursesColorPair(pairIndex.int, fg, bg)

## Init a new Ncurses color pair.
proc initColorPair(
  pairIndex: EditorColorPairIndex,
  pair: ColorPair) {.inline.} =

    pairIndex.initColorPair(pair.foreground, pair.background)

## Init Ncurses colors and color pairs.
proc initEditrorColor*(theme: ColorTheme) =
  for pairIndex, colorPair in ColorThemeTable[theme]:
    # Init all color pair defines.
    colorPair.foreground.initColor
    colorPair.background.initColor

    pairIndex.initColorPair(colorPair)

proc foregroundRgb*(
  theme: ColorTheme,
  pairIndex: EditorColorPairIndex): Rgb {.inline.} =

    ColorThemeTable[theme][pairIndex].foreground.rgb

proc backgroundRgb*(
  theme: ColorTheme,
  pairIndex: EditorColorPairIndex): Rgb {.inline.} =

    ColorThemeTable[theme][pairIndex].background.rgb

## Return a RGB pair from ColorThemeTable.
proc rgbPairFromEditorColorPair*(
  theme: ColorTheme,
  pairIndex: EditorColorPairIndex): RgbPair =

    return RgbPair(
      foreground: ColorThemeTable[theme][pairIndex].foreground.rgb,
      background: ColorThemeTable[theme][pairIndex].background.rgb)

## Return true if `s` exists in `EditorColorPairIndex`.
proc isEditorColorPairIndex*(s: string): bool =
  for i in EditorColorPairIndex:
    if $i == s: return true

## Set a Rgb to ColorThemeTable.
proc setForegroundRgb*(
  theme: ColorTheme,
  pairIndex: EditorColorPairIndex,
  rgb: Rgb) {.inline.} = ColorThemeTable[theme][pairIndex].foreground.rgb = rgb

## Set a Rgb to ColorThemeTable.
proc setBackgroundRgb*(
  theme: ColorTheme,
  pairIndex: EditorColorPairIndex,
  rgb: Rgb) {.inline.} = ColorThemeTable[theme][pairIndex].background.rgb = rgb

# Environment where only 8 colors can be used
# TODO: Rewrite or remove color.convertToConsoleEnvironmentColor
#proc convertToConsoleEnvironmentColor*(theme: ColorTheme) =
#  proc isDefault(color: Color): bool {.inline.} = color == DefaultColor
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
#      of maroon, red, darkRed1, darkRed2, red31, mediumVioletRed,
#         indianRed1, red32, indianRed2, red1, orangeRed1, indianRed11,
#         indianRed12, paleVioletRed1, deepPink41, deepPink42, deepPink4,
#         magenta3: true
#      else: false
#
#  proc isGreen(color: Color): bool =
#    case color:
#      of green, darkGreen, green4, springGreen4, green31, springGreen31,
#         lightSeaGreen, green32, springGreen33, springGreen21, green1,
#         springGreen22, springGreen1, mediumSpringGreen, darkSeaGreen41,
#         darkSeaGreen42, paleGreen31, seaGreen3, seaGreen2, seaGreen11,
#         seaGreen12, darkSeaGreen, darkOliveGreen31, paleGreen32,
#         darkSeaGreen31, lightGreen1, lightGreen2, paleGreen11,
#         darkOliveGreen32, darkSeaGreen32, darkSeaGreen21, greenYellow,
#         darkOliveGreen2, paleGreen12, darkSeaGreen22, darkSeaGreen11,
#         darkOliveGreen11, darkOliveGreen12, darkSeaGreen12,
#         lime, orange41, chartreuse4, paleTurquoise4, chartreuse31,
#         chartreuse32, chartreuse21, Wheat4, chartreuse22, chartreuse1,
#         darkGoldenrod, lightSalmon31, rosyBrown, gold31, darkKhaki,
#         navajoWhite3: true
#      else: false
#
#  # is olive (yellow)
#  proc isOlive(color: Color): bool =
#    case color:
#      of olive,
#         yellow, yellow41, yellow42, yellow31, yellow32, lightYellow3,
#         yellow2, yellow1, orange42, lightPink4, plum4, wheat4, darkOrange31,
#         darkOrange32, orange3, lightSalmon32, gold32, lightGoldenrod3, tan,
#         mistyRose3, khaki3, lightGoldenrod2, darkOrange, salmon1, orange1,
#         sandyBrown, lightSalmon1, gold1, lightGoldenrod21, lightGoldenrod22,
#         navajoWhite1, lightGoldenrod1, khaki1, wheat1, cornsilk1: true
#      else: false
#
#  # is navy (blue)
#  proc isNavy(color: Color): bool =
#    case color:
#      of navy,
#         blue, navyBlue, darkBlue, blue31, blue32, blue1, deepSkyBlue41,
#         deepSkyBlue42, deepSkyBlue43, dodgerBlue31, dodgerBlue32,
#         deepSkyBlue31, deepSkyBlue32, dodgerBlue1, deepSkyBlue2,
#         deepSkyBlue1, blueViolet, slateBlue31, slateBlue32, royalBlue1,
#         steelBlue, steelBlue3, cornflowerBlue, cadetBlue1, cadetBlue2,
#         skyBlue3, steelBlue11, steelBlue12, slateBlue1, lightSlateBlue,
#         lightSkyBlue31, lightSkyBlue32, skyBlue2, skyBlue1,
#         lightSteelBlue3, lightSteelBlue, lightSkyBlue1, lightSteelBlue1,
#         aqua, darkTurquoise, turquoise2, aquamarine11: true
#      else: false
#
#  proc isPurple(color: Color): bool =
#    case color:
#      of purple1,
#         purple41, purple42, purple3, mediumPurple4, purple2,
#         mediumPurple31, mediumPurple32, mediumPurple, purple,
#         mediumPurple21, mediumPurple22, mediumPurple1, fuchsia,
#         darkMagenta1, darkMagenta2, darkViolet1, darkViolet2, hotPink31,
#         mediumOrchid3, mediumOrchid, deepPink31, deepPink32, magenta31,
#         magenta32, magenta21, hotPink32, hotPink2, orchid, mediumOrchid11,
#         lightPink3, pink3, plum3, violet, thistle3, plum2, deepPink2,
#         deepPink11, deepPink12, magenta22, magenta1, hotPink11,
#         hotPink12, mediumOrchid12, lightCoral, orchid2, orchid1, lightPink1,
#         pink1, plum1, mistyRose1, thistle1: true
#      else: false
#
#  # is teal (cyan)
#  proc isTeal(color: Color): bool =
#    case color:
#      of teal, darkCyan, cyan3, cyan2, cyan1, lightCyan3, lightCyan1,
#         turquoise4, turquoise2, aquamarine3, mediumTurquoise, aquamarine12,
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
#      setColor(theme, name, Color.purple1)
#    elif isTeal(color):
#      setColor(theme, name, Color.teal)
#    else:
#      # is silver (white)
#      setColor(theme, name, Color.silver)
#
#    setCursesColor(ColorThemeTable[theme])
