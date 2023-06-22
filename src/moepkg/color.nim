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

import pkg/results
import rgb, ui

type
  ColorLayer* {.pure.} = enum
    foreground
    background

  # 8 for the terminal.
  Color8* {.pure.} =  enum
    default             = -1   # The terminal default
    black               = 0    ## hex: #000000
    maroon              = 1    ## hex: #800000
    green               = 2    ## hex: #008000
    olive               = 3    ## hex: #808000
    navy                = 4    ## hex: #000080
    purple              = 5    ## hex: #800080
    teal                = 6    ## hex: #008080
    silver              = 7    ## hex: #c0c0c0

  # 16 for the terminal.
  Color16* {.pure.} =  enum
    default             = -1   # The terminal default
    black               = 0    ## hex: #000000
    maroon              = 1    ## hex: #800000
    green               = 2    ## hex: #008000
    olive               = 3    ## hex: #808000
    navy                = 4    ## hex: #000080
    purple              = 5    ## hex: #800080
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

## Return the Rgb.
proc rgb(c: Color8): Rgb =
  case c:
    of Color8.default: TerminalDefaultRgb
    of Color8.black: "#000000".hexToRgb.get
    of Color8.maroon: "#800000".hexToRgb.get
    of Color8.green: "#008000".hexToRgb.get
    of Color8.olive: "#808000".hexToRgb.get
    of Color8.navy: "#000080".hexToRgb.get
    of Color8.purple: "#800080".hexToRgb.get
    of Color8.teal: "#008080".hexToRgb.get
    of Color8.silver: "#c0c0c0".hexToRgb.get

## Return the Rgb.
proc rgb(c: Color16): Rgb =
  case c:
    of Color16.default: TerminalDefaultRgb
    of Color16.black: "#000000".hexToRgb.get
    of Color16.maroon: "#800000".hexToRgb.get
    of Color16.green: "#008000".hexToRgb.get
    of Color16.olive: "#808000".hexToRgb.get
    of Color16.navy: "#000080".hexToRgb.get
    of Color16.purple: "#800080".hexToRgb.get
    of Color16.teal: "#008080".hexToRgb.get
    of Color16.silver: "#c0c0c0".hexToRgb.get
    of Color16.gray: "#808080".hexToRgb.get
    of Color16.red: "#ff0000".hexToRgb.get
    of Color16.lime: "#00ff00".hexToRgb.get
    of Color16.yellow: "#ffff00".hexToRgb.get
    of Color16.blue: "#0000ff".hexToRgb.get
    of Color16.fuchsia: "#ff00ff".hexToRgb.get
    of Color16.aqua: "#00ffff".hexToRgb.get
    of Color16.white: "#ffffff".hexToRgb.get

## Return the Rgb.
proc rgb(c: Color256): Rgb =
  case c:
    of Color256.default: TerminalDefaultRgb
    of Color256.black: "#000000".hexToRgb.get
    of Color256.maroon: "#800000".hexToRgb.get
    of Color256.green: "#008000".hexToRgb.get
    of Color256.olive: "#808000".hexToRgb.get
    of Color256.navy: "#000080".hexToRgb.get
    of Color256.purple1: "#800080".hexToRgb.get
    of Color256.teal: "#008080".hexToRgb.get
    of Color256.silver: "#c0c0c0".hexToRgb.get
    of Color256.gray: "#808080".hexToRgb.get
    of Color256.red: "#ff0000".hexToRgb.get
    of Color256.lime: "#00ff00".hexToRgb.get
    of Color256.yellow: "#ffff00".hexToRgb.get
    of Color256.blue: "#0000ff".hexToRgb.get
    of Color256.fuchsia: "#ff00ff".hexToRgb.get
    of Color256.aqua: "#00ffff".hexToRgb.get
    of Color256.white: "#ffffff".hexToRgb.get
    of Color256.gray0: "#000000".hexToRgb.get
    of Color256.navyBlue: "#00005f".hexToRgb.get
    of Color256.darkBlue: "#000087".hexToRgb.get
    of Color256.blue31: "#0000af".hexToRgb.get
    of Color256.blue32: "#0000d7".hexToRgb.get
    of Color256.blue1: "#0000ff".hexToRgb.get
    of Color256.darkGreen: "#005f00".hexToRgb.get
    of Color256.deepSkyBlue41: "#005f5f".hexToRgb.get
    of Color256.deepSkyBlue42: "#005f87".hexToRgb.get
    of Color256.deepSkyBlue43: "#005faf".hexToRgb.get
    of Color256.dodgerBlue31: "#005fd7".hexToRgb.get
    of Color256.dodgerBlue32: "#005fff".hexToRgb.get
    of Color256.green4: "#008700".hexToRgb.get
    of Color256.springGreen4: "#00875f".hexToRgb.get
    of Color256.turquoise4: "#008787".hexToRgb.get
    of Color256.deepSkyBlue31: "#0087af".hexToRgb.get
    of Color256.deepSkyBlue32: "#0087d7".hexToRgb.get
    of Color256.dodgerBlue1: "#0087ff".hexToRgb.get
    of Color256.green31: "#00af00".hexToRgb.get
    of Color256.springGreen31: "#00af5f".hexToRgb.get
    of Color256.darkCyan: "#00af87".hexToRgb.get
    of Color256.lightSeaGreen: "#00afaf".hexToRgb.get
    of Color256.deepSkyBlue2: "#00afd7".hexToRgb.get
    of Color256.deepSkyBlue1: "#00afff".hexToRgb.get
    of Color256.green32: "#00d700".hexToRgb.get
    of Color256.springGreen33: "#00d75f".hexToRgb.get
    of Color256.springGreen21: "#00d787".hexToRgb.get
    of Color256.cyan3: "#00d7af".hexToRgb.get
    of Color256.darkTurquoise: "#00d7df".hexToRgb.get
    of Color256.turquoise2: "#00d7ff".hexToRgb.get
    of Color256.green1: "#00ff00".hexToRgb.get
    of Color256.springGreen22: "#00ff5f".hexToRgb.get
    of Color256.springGreen1: "#00ff87".hexToRgb.get
    of Color256.mediumSpringGreen: "#00ffaf".hexToRgb.get
    of Color256.cyan2: "#00ffd7".hexToRgb.get
    of Color256.cyan1: "#00ffff".hexToRgb.get
    of Color256.darkRed1: "#5f0000".hexToRgb.get
    of Color256.deepPink41: "#5f005f".hexToRgb.get
    of Color256.purple41: "#5f0087".hexToRgb.get
    of Color256.purple42: "#5f00af".hexToRgb.get
    of Color256.purple3: "#5f00df".hexToRgb.get
    of Color256.blueViolet: "#5f00ff".hexToRgb.get
    of Color256.orange41: "#5f5f00".hexToRgb.get
    of Color256.gray37: "#5f5f5f".hexToRgb.get
    of Color256.mediumPurple4: "#5f5f87".hexToRgb.get
    of Color256.slateBlue31: "#5f5faf".hexToRgb.get
    of Color256.slateBlue32: "#5f5fd7".hexToRgb.get
    of Color256.royalBlue1: "#5f5fff".hexToRgb.get
    of Color256.chartreuse4: "#5f8700".hexToRgb.get
    of Color256.darkSeaGreen41: "#5f875f".hexToRgb.get
    of Color256.paleTurquoise4: "#5f8787".hexToRgb.get
    of Color256.steelBlue: "#5f87af".hexToRgb.get
    of Color256.steelBlue3: "#5f87d7".hexToRgb.get
    of Color256.cornflowerBlue: "#5f87ff".hexToRgb.get
    of Color256.chartreuse31: "#5faf00".hexToRgb.get
    of Color256.darkSeaGreen42: "#5faf5f".hexToRgb.get
    of Color256.cadetBlue1: "#5faf87".hexToRgb.get
    of Color256.cadetBlue2: "#5fafaf".hexToRgb.get
    of Color256.skyBlue3: "#5fafd7".hexToRgb.get
    of Color256.steelBlue11: "#5fafff".hexToRgb.get
    of Color256.chartreuse32: "#5fd000".hexToRgb.get
    of Color256.paleGreen31: "#5fd75f".hexToRgb.get
    of Color256.seaGreen3: "#5fd787".hexToRgb.get
    of Color256.aquamarine3: "#5fd7af".hexToRgb.get
    of Color256.mediumTurquoise: "#5fd7d7".hexToRgb.get
    of Color256.steelBlue12: "#5fd7ff".hexToRgb.get
    of Color256.chartreuse21: "#5fff00".hexToRgb.get
    of Color256.seaGreen2: "#5fff5f".hexToRgb.get
    of Color256.seaGreen11: "#5fff87".hexToRgb.get
    of Color256.seaGreen12: "#5fffaf".hexToRgb.get
    of Color256.aquamarine11: "#5fffd7".hexToRgb.get
    of Color256.darkSlateGray2: "#5fffff".hexToRgb.get
    of Color256.darkRed2: "#870000".hexToRgb.get
    of Color256.deepPink42: "#87005f".hexToRgb.get
    of Color256.darkMagenta1: "#870087".hexToRgb.get
    of Color256.darkMagenta2: "#8700af".hexToRgb.get
    of Color256.darkViolet1: "#8700d7".hexToRgb.get
    of Color256.purple2: "#8700ff".hexToRgb.get
    of Color256.orange42: "#875f00".hexToRgb.get
    of Color256.lightPink4: "#875f5f".hexToRgb.get
    of Color256.plum4: "#875f87".hexToRgb.get
    of Color256.mediumPurple31: "#875faf".hexToRgb.get
    of Color256.mediumPurple32: "#875fd7".hexToRgb.get
    of Color256.slateBlue1: "#875fff".hexToRgb.get
    of Color256.yellow41: "#878700".hexToRgb.get
    of Color256.wheat4: "#87875f".hexToRgb.get
    of Color256.gray53: "#878787".hexToRgb.get
    of Color256.lightSlategray: "#8787af".hexToRgb.get
    of Color256.mediumPurple: "#8787d7".hexToRgb.get
    of Color256.lightSlateBlue: "#8787ff".hexToRgb.get
    of Color256.yellow42: "#87af00".hexToRgb.get
    of Color256.Wheat4: "#87af5f".hexToRgb.get
    of Color256.darkSeaGreen: "#87af87".hexToRgb.get
    of Color256.lightSkyBlue31: "#87afaf".hexToRgb.get
    of Color256.lightSkyBlue32: "#87afd7".hexToRgb.get
    of Color256.skyBlue2: "#87afff".hexToRgb.get
    of Color256.chartreuse22: "#87d700".hexToRgb.get
    of Color256.darkOliveGreen31: "#87d75f".hexToRgb.get
    of Color256.paleGreen32: "#87d787".hexToRgb.get
    of Color256.darkSeaGreen31: "#87d7af".hexToRgb.get
    of Color256.darkSlateGray3: "#87d7d7".hexToRgb.get
    of Color256.skyBlue1: "#87d7ff".hexToRgb.get
    of Color256.chartreuse1: "#87ff00".hexToRgb.get
    of Color256.lightGreen1: "#87ff5f".hexToRgb.get
    of Color256.lightGreen2: "#87ff87".hexToRgb.get
    of Color256.paleGreen11: "#87ffaf".hexToRgb.get
    of Color256.aquamarine12: "#87ffd7".hexToRgb.get
    of Color256.darkSlateGray1: "#87ffff".hexToRgb.get
    of Color256.red31: "#af0000".hexToRgb.get
    of Color256.deepPink4: "#af005f".hexToRgb.get
    of Color256.mediumVioletRed: "#af0087".hexToRgb.get
    of Color256.magenta3: "#af00af".hexToRgb.get
    of Color256.darkViolet2: "#af00d7".hexToRgb.get
    of Color256.purple: "#af00ff".hexToRgb.get
    of Color256.darkOrange31: "#af5f00".hexToRgb.get
    of Color256.indianRed1: "#af5f5f".hexToRgb.get
    of Color256.hotPink31: "#af5f87".hexToRgb.get
    of Color256.mediumOrchid3: "#af5faf".hexToRgb.get
    of Color256.mediumOrchid: "#af5fd7".hexToRgb.get
    of Color256.mediumPurple21: "#af5fff".hexToRgb.get
    of Color256.darkGoldenrod: "#af8700".hexToRgb.get
    of Color256.lightSalmon31: "#af875f".hexToRgb.get
    of Color256.rosyBrown: "#af8787".hexToRgb.get
    of Color256.gray63: "#af87af".hexToRgb.get
    of Color256.mediumPurple22: "#af87d7".hexToRgb.get
    of Color256.mediumPurple1: "#af87ff".hexToRgb.get
    of Color256.gold31: "#afaf00".hexToRgb.get
    of Color256.darkKhaki: "#afaf5f".hexToRgb.get
    of Color256.navajoWhite3: "#afaf87".hexToRgb.get
    of Color256.gray69: "#afafaf".hexToRgb.get
    of Color256.lightSteelBlue3: "#afafd7".hexToRgb.get
    of Color256.lightSteelBlue: "#afafff".hexToRgb.get
    of Color256.yellow31: "#afd700".hexToRgb.get
    of Color256.darkOliveGreen32: "#afd75f".hexToRgb.get
    of Color256.darkSeaGreen32: "#afd787".hexToRgb.get
    of Color256.darkSeaGreen21: "#afd7af".hexToRgb.get
    of Color256.lightCyan3: "#afafd7".hexToRgb.get
    of Color256.lightSkyBlue1: "#afd7ff".hexToRgb.get
    of Color256.greenYellow: "#afff00".hexToRgb.get
    of Color256.darkOliveGreen2: "#afff5f".hexToRgb.get
    of Color256.paleGreen12: "#afff87".hexToRgb.get
    of Color256.darkSeaGreen22: "#afffaf".hexToRgb.get
    of Color256.darkSeaGreen11: "#afffd7".hexToRgb.get
    of Color256.paleTurquoise1: "#afffff".hexToRgb.get
    of Color256.red32: "#d70000".hexToRgb.get
    of Color256.deepPink31: "#d7005f".hexToRgb.get
    of Color256.deepPink32: "#d70087".hexToRgb.get
    of Color256.magenta31: "#d700af".hexToRgb.get
    of Color256.magenta32: "#d700d7".hexToRgb.get
    of Color256.magenta21: "#d700ff".hexToRgb.get
    of Color256.darkOrange32: "#d75f00".hexToRgb.get
    of Color256.indianRed2: "#d75f5f".hexToRgb.get
    of Color256.hotPink32: "#d75f87".hexToRgb.get
    of Color256.hotPink2: "#d75faf".hexToRgb.get
    of Color256.orchid: "#d75fd7".hexToRgb.get
    of Color256.mediumOrchid11: "#d75fff".hexToRgb.get
    of Color256.orange3: "#d78700".hexToRgb.get
    of Color256.lightSalmon32: "#d7875f".hexToRgb.get
    of Color256.lightPink3: "#d78787".hexToRgb.get
    of Color256.pink3: "#d787af".hexToRgb.get
    of Color256.plum3: "#d787d7".hexToRgb.get
    of Color256.violet: "#d787ff".hexToRgb.get
    of Color256.gold32: "#d7af00".hexToRgb.get
    of Color256.lightGoldenrod3: "#d7af5f".hexToRgb.get
    of Color256.tan: "#d7af87".hexToRgb.get
    of Color256.mistyRose3: "#d7afaf".hexToRgb.get
    of Color256.thistle3: "#d7afd7".hexToRgb.get
    of Color256.plum2: "#d7afff".hexToRgb.get
    of Color256.yellow32: "#d7d700".hexToRgb.get
    of Color256.khaki3: "#d7d75f".hexToRgb.get
    of Color256.lightGoldenrod2: "#d7d787".hexToRgb.get
    of Color256.lightYellow3: "#d7d7af".hexToRgb.get
    of Color256.gray84: "#d7d7d7".hexToRgb.get
    of Color256.lightSteelBlue1: "#d7d7ff".hexToRgb.get
    of Color256.yellow2: "#d7ff00".hexToRgb.get
    of Color256.darkOliveGreen11: "#d7ff5f".hexToRgb.get
    of Color256.darkOliveGreen12: "#d7ff87".hexToRgb.get
    of Color256.darkSeaGreen12: "#d7ffaf".hexToRgb.get
    of Color256.honeydew2: "#d7ffd7".hexToRgb.get
    of Color256.lightCyan1: "#d7ffff".hexToRgb.get
    of Color256.red1: "#ff0000".hexToRgb.get
    of Color256.deepPink2: "#ff005f".hexToRgb.get
    of Color256.deepPink11: "#ff0087".hexToRgb.get
    of Color256.deepPink12: "#ff00af".hexToRgb.get
    of Color256.magenta22: "#ff00d7".hexToRgb.get
    of Color256.magenta1: "#ff00ff".hexToRgb.get
    of Color256.orangeRed1: "#ff5f00".hexToRgb.get
    of Color256.indianRed11: "#ff5f5f".hexToRgb.get
    of Color256.indianRed12: "#ff5f87".hexToRgb.get
    of Color256.hotPink11: "#ff5faf".hexToRgb.get
    of Color256.hotPink12: "#ff5fd7".hexToRgb.get
    of Color256.mediumOrchid12: "#ff5fff".hexToRgb.get
    of Color256.darkOrange: "#ff8700".hexToRgb.get
    of Color256.salmon1: "#ff875f".hexToRgb.get
    of Color256.lightCoral: "#ff8787".hexToRgb.get
    of Color256.paleVioletRed1: "#ff87af".hexToRgb.get
    of Color256.orchid2: "#ff87d7".hexToRgb.get
    of Color256.orchid1: "#ff87ff".hexToRgb.get
    of Color256.orange1: "#ffaf00".hexToRgb.get
    of Color256.sandyBrown: "#ffaf5f".hexToRgb.get
    of Color256.lightSalmon1: "#ffaf87".hexToRgb.get
    of Color256.lightPink1: "#ffafaf".hexToRgb.get
    of Color256.pink1: "#ffafd7".hexToRgb.get
    of Color256.plum1: "#ffafff".hexToRgb.get
    of Color256.gold1: "#ffd700".hexToRgb.get
    of Color256.lightGoldenrod21: "#ffd75f".hexToRgb.get
    of Color256.lightGoldenrod22: "#ffd787".hexToRgb.get
    of Color256.navajoWhite1: "#ffd7af".hexToRgb.get
    of Color256.mistyRose1: "#ffd7d7".hexToRgb.get
    of Color256.thistle1: "#ffd7ff".hexToRgb.get
    of Color256.yellow1: "#ffff00".hexToRgb.get
    of Color256.lightGoldenrod1: "#ffff5f".hexToRgb.get
    of Color256.khaki1: "#ffff87".hexToRgb.get
    of Color256.wheat1: "#ffffaf".hexToRgb.get
    of Color256.cornsilk1: "#ffffd7".hexToRgb.get
    of Color256.gray100: "#ffffff".hexToRgb.get
    of Color256.gray3: "#080808".hexToRgb.get
    of Color256.gray7: "#121212".hexToRgb.get
    of Color256.gray11: "#1c1c1c".hexToRgb.get
    of Color256.gray15: "#262626".hexToRgb.get
    of Color256.gray19: "#303030".hexToRgb.get
    of Color256.gray23: "#3a3a3a".hexToRgb.get
    of Color256.gray27: "#444444".hexToRgb.get
    of Color256.gray30: "#4e4e4e".hexToRgb.get
    of Color256.gray35: "#585858".hexToRgb.get
    of Color256.gray39: "#626262".hexToRgb.get
    of Color256.gray42: "#6c6c6c".hexToRgb.get
    of Color256.gray46: "#767676".hexToRgb.get
    of Color256.gray50: "#808080".hexToRgb.get
    of Color256.gray54: "#8a8a8a".hexToRgb.get
    of Color256.gray58: "#949494".hexToRgb.get
    of Color256.gray62: "#9e9e9e".hexToRgb.get
    of Color256.gray66: "#a8a8a8".hexToRgb.get
    of Color256.gray70: "#b2b2b2".hexToRgb.get
    of Color256.gray74: "#bcbcbc".hexToRgb.get
    of Color256.gray78: "#c6c6c6".hexToRgb.get
    of Color256.gray82: "#d0d0d0".hexToRgb.get
    of Color256.gray85: "#dadada".hexToRgb.get
    of Color256.gray89: "#e4e4e4".hexToRgb.get
    of Color256.gray93: "#eeeeee".hexToRgb.get

## Return Color8 from Rgb.
proc color8(rgb: Rgb): Result[Color8, string] =
  if rgb == TerminalDefaultRgb:
    return Result[Color8, string].ok Color8.default
  if rgb == "#000000".hexToRgb.get:
    return Result[Color8, string].ok Color8.black
  if rgb == "#800000".hexToRgb.get:
    return Result[Color8, string].ok Color8.maroon
  if rgb == "#008000".hexToRgb.get:
    return Result[Color8, string].ok Color8.green
  if rgb == "#808000".hexToRgb.get:
    return Result[Color8, string].ok Color8.olive
  if rgb == "#000080".hexToRgb.get:
    return Result[Color8, string].ok Color8.navy
  if rgb == "#008080".hexToRgb.get:
    return Result[Color8, string].ok Color8.purple
  if rgb == "#008080".hexToRgb.get:
    return Result[Color8, string].ok Color8.teal
  if rgb == "#c0c0c0".hexToRgb.get:
    return Result[Color8, string].ok Color8.silver
  else:
    return Result[Color8, string].err "Invalid value"

## Return Color16 from Rgb.
proc color16(rgb: Rgb): Result[Color16, string] =
  if rgb == TerminalDefaultRgb:
    return Result[Color16, string].ok Color16.default
  if rgb == "#000000".hexToRgb.get:
    return Result[Color16, string].ok Color16.black
  if rgb == "#800000".hexToRgb.get:
    return Result[Color16, string].ok Color16.maroon
  if rgb == "#008000".hexToRgb.get:
    return Result[Color16, string].ok Color16.green
  if rgb == "#808000".hexToRgb.get:
    return Result[Color16, string].ok Color16.olive
  if rgb == "#000080".hexToRgb.get:
    return Result[Color16, string].ok Color16.navy
  if rgb == "#008080".hexToRgb.get:
    return Result[Color16, string].ok Color16.purple
  if rgb == "#008080".hexToRgb.get:
    return Result[Color16, string].ok Color16.teal
  if rgb == "#c0c0c0".hexToRgb.get:
    return Result[Color16, string].ok Color16.silver
  if rgb == "#808080".hexToRgb.get:
    return Result[Color16, string].ok Color16.gray
  if rgb == "#ff0000".hexToRgb.get:
    return Result[Color16, string].ok Color16.red
  if rgb == "#00ff00".hexToRgb.get:
    return Result[Color16, string].ok Color16.lime
  if rgb == "#ffff00".hexToRgb.get:
    return Result[Color16, string].ok Color16.yellow
  if rgb == "#0000ff".hexToRgb.get:
    return Result[Color16, string].ok Color16.blue
  if rgb == "#ff00ff".hexToRgb.get:
    return Result[Color16, string].ok Color16.fuchsia
  if rgb == "#00ffff".hexToRgb.get:
    return Result[Color16, string].ok Color16.aqua
  if rgb == "#ffffff".hexToRgb.get:
    return Result[Color16, string].ok Color16.white
  else:
    return Result[Color16, string].err "Invalid value"

## Return Color256 from Rgb.
proc color256(rgb: Rgb): Result[Color256, string] =
  if rgb == TerminalDefaultRgb:
    return Result[Color256, string].ok Color256.default
  if rgb == "#000000".hexToRgb.get:
    return Result[Color256, string].ok Color256.black
  if rgb == "#800000".hexToRgb.get:
    return Result[Color256, string].ok Color256.maroon
  if rgb == "#008000".hexToRgb.get:
    return Result[Color256, string].ok Color256.green
  if rgb == "#808000".hexToRgb.get:
    return Result[Color256, string].ok Color256.olive
  if rgb == "#000080".hexToRgb.get:
    return Result[Color256, string].ok Color256.navy
  if rgb == "#008080".hexToRgb.get:
    return Result[Color256, string].ok Color256.purple
  if rgb == "#008080".hexToRgb.get:
    return Result[Color256, string].ok Color256.teal
  if rgb == "#c0c0c0".hexToRgb.get:
    return Result[Color256, string].ok Color256.silver
  if rgb == "#808080".hexToRgb.get:
    return Result[Color256, string].ok Color256.gray
  if rgb == "#ff0000".hexToRgb.get:
    return Result[Color256, string].ok Color256.red
  if rgb == "#00ff00".hexToRgb.get:
    return Result[Color256, string].ok Color256.lime
  if rgb == "#ffff00".hexToRgb.get:
    return Result[Color256, string].ok Color256.yellow
  if rgb == "#0000ff".hexToRgb.get:
    return Result[Color256, string].ok Color256.blue
  if rgb == "#ff00ff".hexToRgb.get:
    return Result[Color256, string].ok Color256.fuchsia
  if rgb == "#00ffff".hexToRgb.get:
    return Result[Color256, string].ok Color256.aqua
  if rgb == "#ffffff".hexToRgb.get:
    return Result[Color256, string].ok Color256.white
  if rgb == "#000000".hexToRgb.get:
    return Result[Color256, string].ok Color256.gray0
  if rgb == "#00005f".hexToRgb.get:
    return Result[Color256, string].ok Color256.navyBlue
  if rgb == "#000087".hexToRgb.get:
    return Result[Color256, string].ok Color256.darkBlue
  if rgb == "#0000af".hexToRgb.get:
    return Result[Color256, string].ok Color256.blue31
  if rgb == "#0000d7".hexToRgb.get:
    return Result[Color256, string].ok Color256.blue32
  if rgb == "#0000ff".hexToRgb.get:
    return Result[Color256, string].ok Color256.blue1
  if rgb == "#005f00".hexToRgb.get:
    return Result[Color256, string].ok Color256.darkGreen
  if rgb == "#005f5f".hexToRgb.get:
    return Result[Color256, string].ok Color256.deepSkyBlue41
  if rgb == "#005f87".hexToRgb.get:
    return Result[Color256, string].ok Color256.deepSkyBlue42
  if rgb == "#005faf".hexToRgb.get:
    return Result[Color256, string].ok Color256.deepSkyBlue43
  if rgb == "#005fd7".hexToRgb.get:
    return Result[Color256, string].ok Color256.dodgerBlue31
  if rgb == "#005fff".hexToRgb.get:
    return Result[Color256, string].ok Color256.dodgerBlue32
  if rgb == "#008700".hexToRgb.get:
    return Result[Color256, string].ok Color256.green4
  if rgb == "#00875f".hexToRgb.get:
    return Result[Color256, string].ok Color256.springGreen4
  if rgb == "#008787".hexToRgb.get:
    return Result[Color256, string].ok Color256.turquoise4
  if rgb == "#0087af".hexToRgb.get:
    return Result[Color256, string].ok Color256.deepSkyBlue31
  if rgb == "#0087d7".hexToRgb.get:
    return Result[Color256, string].ok Color256.deepSkyBlue32
  if rgb == "#0087ff".hexToRgb.get:
    return Result[Color256, string].ok Color256.dodgerBlue1
  if rgb == "#00af00".hexToRgb.get:
    return Result[Color256, string].ok Color256.green31
  if rgb == "#00af5f".hexToRgb.get:
    return Result[Color256, string].ok Color256.springGreen31
  if rgb == "#00af87".hexToRgb.get:
    return Result[Color256, string].ok Color256.darkCyan
  if rgb == "#00afaf".hexToRgb.get:
    return Result[Color256, string].ok Color256.lightSeaGreen
  if rgb == "#00afd7".hexToRgb.get:
    return Result[Color256, string].ok Color256.deepSkyBlue2
  if rgb == "#00afff".hexToRgb.get:
    return Result[Color256, string].ok Color256.deepSkyBlue1
  if rgb == "#00d700".hexToRgb.get:
    return Result[Color256, string].ok Color256.green32
  if rgb == "#00d75f".hexToRgb.get:
    return Result[Color256, string].ok Color256.springGreen33
  if rgb == "#00d787".hexToRgb.get:
    return Result[Color256, string].ok Color256.springGreen21
  if rgb == "#00d7af".hexToRgb.get:
    return Result[Color256, string].ok Color256.cyan3
  if rgb == "#00d7df".hexToRgb.get:
    return Result[Color256, string].ok Color256.darkTurquoise
  if rgb == "#00d7ff".hexToRgb.get:
    return Result[Color256, string].ok Color256.turquoise2
  if rgb == "#00ff00".hexToRgb.get:
    return Result[Color256, string].ok Color256.green1
  if rgb == "#00ff5f".hexToRgb.get:
    return Result[Color256, string].ok Color256.springGreen22
  if rgb == "#00ff87".hexToRgb.get:
    return Result[Color256, string].ok Color256.springGreen1
  if rgb == "#00ffaf".hexToRgb.get:
    return Result[Color256, string].ok Color256.mediumSpringGreen
  if rgb == "#00ffd7".hexToRgb.get:
    return Result[Color256, string].ok Color256.cyan2
  if rgb == "#00ffff".hexToRgb.get:
    return Result[Color256, string].ok Color256.cyan1
  if rgb == "#5f0000".hexToRgb.get:
    return Result[Color256, string].ok Color256.darkRed1
  if rgb == "#5f005f".hexToRgb.get:
    return Result[Color256, string].ok Color256.deepPink41
  if rgb == "#5f0087".hexToRgb.get:
    return Result[Color256, string].ok Color256.purple41
  if rgb == "#5f00af".hexToRgb.get:
    return Result[Color256, string].ok Color256.purple42
  if rgb == "#5f00df".hexToRgb.get:
    return Result[Color256, string].ok Color256.purple3
  if rgb == "#5f00ff".hexToRgb.get:
    return Result[Color256, string].ok Color256.blueViolet
  if rgb == "#5f5f00".hexToRgb.get:
    return Result[Color256, string].ok Color256.orange41
  if rgb == "#5f5f5f".hexToRgb.get:
    return Result[Color256, string].ok Color256.gray37
  if rgb == "#5f5f87".hexToRgb.get:
    return Result[Color256, string].ok Color256.mediumPurple4
  if rgb == "#5f5faf".hexToRgb.get:
    return Result[Color256, string].ok Color256.slateBlue31
  if rgb == "#5f5fd7".hexToRgb.get:
    return Result[Color256, string].ok Color256.slateBlue32
  if rgb == "#5f5fff".hexToRgb.get:
    return Result[Color256, string].ok Color256.royalBlue1
  if rgb == "#5f8700".hexToRgb.get:
    return Result[Color256, string].ok Color256.chartreuse4
  if rgb == "#5f875f".hexToRgb.get:
    return Result[Color256, string].ok Color256.darkSeaGreen41
  if rgb == "#5f8787".hexToRgb.get:
    return Result[Color256, string].ok Color256.paleTurquoise4
  if rgb == "#5f87af".hexToRgb.get:
    return Result[Color256, string].ok Color256.steelBlue
  if rgb == "#5f87d7".hexToRgb.get:
    return Result[Color256, string].ok Color256.steelBlue3
  if rgb == "#5f87ff".hexToRgb.get:
    return Result[Color256, string].ok Color256.cornflowerBlue
  if rgb == "#5faf00".hexToRgb.get:
    return Result[Color256, string].ok Color256.chartreuse31
  if rgb == "#5faf5f".hexToRgb.get:
    return Result[Color256, string].ok Color256.darkSeaGreen42
  if rgb == "#5faf87".hexToRgb.get:
    return Result[Color256, string].ok Color256.cadetBlue1
  if rgb == "#5fafaf".hexToRgb.get:
    return Result[Color256, string].ok Color256.cadetBlue2
  if rgb == "#5fafd7".hexToRgb.get:
    return Result[Color256, string].ok Color256.skyBlue3
  if rgb == "#5fafff".hexToRgb.get:
    return Result[Color256, string].ok Color256.steelBlue11
  if rgb == "#5fd000".hexToRgb.get:
    return Result[Color256, string].ok Color256.chartreuse32
  if rgb == "#5fd75f".hexToRgb.get:
    return Result[Color256, string].ok Color256.paleGreen31
  if rgb == "#5fd787".hexToRgb.get:
    return Result[Color256, string].ok Color256.seaGreen3
  if rgb == "#5fd7af".hexToRgb.get:
    return Result[Color256, string].ok Color256.aquamarine3
  if rgb == "#5fd7d7".hexToRgb.get:
    return Result[Color256, string].ok Color256.mediumTurquoise
  if rgb == "#5fd7ff".hexToRgb.get:
    return Result[Color256, string].ok Color256.steelBlue12
  if rgb == "#5fff00".hexToRgb.get:
    return Result[Color256, string].ok Color256.chartreuse21
  if rgb == "#5fff5f".hexToRgb.get:
    return Result[Color256, string].ok Color256.seaGreen2
  if rgb == "#5fff87".hexToRgb.get:
    return Result[Color256, string].ok Color256.seaGreen11
  if rgb == "#5fffaf".hexToRgb.get:
    return Result[Color256, string].ok Color256.seaGreen12
  if rgb == "#5fffd7".hexToRgb.get:
    return Result[Color256, string].ok Color256.aquamarine11
  if rgb == "#5fffff".hexToRgb.get:
    return Result[Color256, string].ok Color256.darkSlateGray2
  if rgb == "#870000".hexToRgb.get:
    return Result[Color256, string].ok Color256.darkRed2
  if rgb == "#87005f".hexToRgb.get:
    return Result[Color256, string].ok Color256.deepPink42
  if rgb == "#870087".hexToRgb.get:
    return Result[Color256, string].ok Color256.darkMagenta1
  if rgb == "#8700af".hexToRgb.get:
    return Result[Color256, string].ok Color256.darkMagenta2
  if rgb == "#8700d7".hexToRgb.get:
    return Result[Color256, string].ok Color256.darkViolet1
  if rgb == "#8700ff".hexToRgb.get:
    return Result[Color256, string].ok Color256.purple2
  if rgb == "#875f00".hexToRgb.get:
    return Result[Color256, string].ok Color256.orange42
  if rgb == "#875f5f".hexToRgb.get:
    return Result[Color256, string].ok Color256.lightPink4
  if rgb == "#875f87".hexToRgb.get:
    return Result[Color256, string].ok Color256.plum4
  if rgb == "#875faf".hexToRgb.get:
    return Result[Color256, string].ok Color256.mediumPurple31
  if rgb == "#875fd7".hexToRgb.get:
    return Result[Color256, string].ok Color256.mediumPurple32
  if rgb == "#875fff".hexToRgb.get:
    return Result[Color256, string].ok Color256.slateBlue1
  if rgb == "#878700".hexToRgb.get:
    return Result[Color256, string].ok Color256.yellow41
  if rgb == "#87875f".hexToRgb.get:
    return Result[Color256, string].ok Color256.wheat4
  if rgb == "#878787".hexToRgb.get:
    return Result[Color256, string].ok Color256.gray53
  if rgb == "#8787af".hexToRgb.get:
    return Result[Color256, string].ok Color256.lightSlategray
  if rgb == "#8787d7".hexToRgb.get:
    return Result[Color256, string].ok Color256.mediumPurple
  if rgb == "#8787ff".hexToRgb.get:
    return Result[Color256, string].ok Color256.lightSlateBlue
  if rgb == "#87af00".hexToRgb.get:
    return Result[Color256, string].ok Color256.yellow42
  if rgb == "#87af5f".hexToRgb.get:
    return Result[Color256, string].ok Color256.Wheat4
  if rgb == "#87af87".hexToRgb.get:
    return Result[Color256, string].ok Color256.darkSeaGreen
  if rgb == "#87afaf".hexToRgb.get:
    return Result[Color256, string].ok Color256.lightSkyBlue31
  if rgb == "#87afd7".hexToRgb.get:
    return Result[Color256, string].ok Color256.lightSkyBlue32
  if rgb == "#87afff".hexToRgb.get:
    return Result[Color256, string].ok Color256.skyBlue2
  if rgb == "#87d700".hexToRgb.get:
    return Result[Color256, string].ok Color256.chartreuse22
  if rgb == "#87d75f".hexToRgb.get:
    return Result[Color256, string].ok Color256.darkOliveGreen31
  if rgb == "#87d787".hexToRgb.get:
    return Result[Color256, string].ok Color256.paleGreen32
  if rgb == "#87d7af".hexToRgb.get:
    return Result[Color256, string].ok Color256.darkSeaGreen31
  if rgb == "#87d7d7".hexToRgb.get:
    return Result[Color256, string].ok Color256.darkSlateGray3
  if rgb == "#87d7ff".hexToRgb.get:
    return Result[Color256, string].ok Color256.skyBlue1
  if rgb == "#87ff00".hexToRgb.get:
    return Result[Color256, string].ok Color256.chartreuse1
  if rgb == "#87ff5f".hexToRgb.get:
    return Result[Color256, string].ok Color256.lightGreen1
  if rgb == "#87ff87".hexToRgb.get:
    return Result[Color256, string].ok Color256.lightGreen2
  if rgb == "#87ffaf".hexToRgb.get:
    return Result[Color256, string].ok Color256.paleGreen11
  if rgb == "#87ffd7".hexToRgb.get:
    return Result[Color256, string].ok Color256.aquamarine12
  if rgb == "#87ffff".hexToRgb.get:
    return Result[Color256, string].ok Color256.darkSlateGray1
  if rgb == "#af0000".hexToRgb.get:
    return Result[Color256, string].ok Color256.red31
  if rgb == "#af005f".hexToRgb.get:
    return Result[Color256, string].ok Color256.deepPink4
  if rgb == "#af0087".hexToRgb.get:
    return Result[Color256, string].ok Color256.mediumVioletRed
  if rgb == "#af00af".hexToRgb.get:
    return Result[Color256, string].ok Color256.magenta3
  if rgb == "#af00d7".hexToRgb.get:
    return Result[Color256, string].ok Color256.darkViolet2
  if rgb == "#af00ff".hexToRgb.get:
    return Result[Color256, string].ok Color256.purple
  if rgb == "#af5f00".hexToRgb.get:
    return Result[Color256, string].ok Color256.darkOrange31
  if rgb == "#af5f5f".hexToRgb.get:
    return Result[Color256, string].ok Color256.indianRed1
  if rgb == "#af5f87".hexToRgb.get:
    return Result[Color256, string].ok Color256.hotPink31
  if rgb == "#af5faf".hexToRgb.get:
    return Result[Color256, string].ok Color256.mediumOrchid3
  if rgb == "#af5fd7".hexToRgb.get:
    return Result[Color256, string].ok Color256.mediumOrchid
  if rgb == "#af5fff".hexToRgb.get:
    return Result[Color256, string].ok Color256.mediumPurple21
  if rgb == "#af8700".hexToRgb.get:
    return Result[Color256, string].ok Color256.darkGoldenrod
  if rgb == "#af875f".hexToRgb.get:
    return Result[Color256, string].ok Color256.lightSalmon31
  if rgb == "#af8787".hexToRgb.get:
    return Result[Color256, string].ok Color256.rosyBrown
  if rgb == "#af87af".hexToRgb.get:
    return Result[Color256, string].ok Color256.gray63
  if rgb == "#af87d7".hexToRgb.get:
    return Result[Color256, string].ok Color256.mediumPurple22
  if rgb == "#af87ff".hexToRgb.get:
    return Result[Color256, string].ok Color256.mediumPurple1
  if rgb == "#afaf00".hexToRgb.get:
    return Result[Color256, string].ok Color256.gold31
  if rgb == "#afaf5f".hexToRgb.get:
    return Result[Color256, string].ok Color256.darkKhaki
  if rgb == "#afaf87".hexToRgb.get:
    return Result[Color256, string].ok Color256.navajoWhite3
  if rgb == "#afafaf".hexToRgb.get:
    return Result[Color256, string].ok Color256.gray69
  if rgb == "#afafd7".hexToRgb.get:
    return Result[Color256, string].ok Color256.lightSteelBlue3
  if rgb == "#afafff".hexToRgb.get:
    return Result[Color256, string].ok Color256.lightSteelBlue
  if rgb == "#afd700".hexToRgb.get:
    return Result[Color256, string].ok Color256.yellow31
  if rgb == "#afd75f".hexToRgb.get:
    return Result[Color256, string].ok Color256.darkOliveGreen32
  if rgb == "#afd787".hexToRgb.get:
    return Result[Color256, string].ok Color256.darkSeaGreen32
  if rgb == "#afd7af".hexToRgb.get:
    return Result[Color256, string].ok Color256.darkSeaGreen21
  if rgb == "#afafd7".hexToRgb.get:
    return Result[Color256, string].ok Color256.lightCyan3
  if rgb == "#afd7ff".hexToRgb.get:
    return Result[Color256, string].ok Color256.lightSkyBlue1
  if rgb == "#afff00".hexToRgb.get:
    return Result[Color256, string].ok Color256.greenYellow
  if rgb == "#afff5f".hexToRgb.get:
    return Result[Color256, string].ok Color256.darkOliveGreen2
  if rgb == "#afff87".hexToRgb.get:
    return Result[Color256, string].ok Color256.paleGreen12
  if rgb == "#afffaf".hexToRgb.get:
    return Result[Color256, string].ok Color256.darkSeaGreen22
  if rgb == "#afffd7".hexToRgb.get:
    return Result[Color256, string].ok Color256.darkSeaGreen11
  if rgb == "#afffff".hexToRgb.get:
    return Result[Color256, string].ok Color256.paleTurquoise1
  if rgb == "#d70000".hexToRgb.get:
    return Result[Color256, string].ok Color256.red32
  if rgb == "#d7005f".hexToRgb.get:
    return Result[Color256, string].ok Color256.deepPink31
  if rgb == "#d70087".hexToRgb.get:
    return Result[Color256, string].ok Color256.deepPink32
  if rgb == "#d700af".hexToRgb.get:
    return Result[Color256, string].ok Color256.magenta31
  if rgb == "#d700d7".hexToRgb.get:
    return Result[Color256, string].ok Color256.magenta32
  if rgb == "#d700ff".hexToRgb.get:
    return Result[Color256, string].ok Color256.magenta21
  if rgb == "#d75f00".hexToRgb.get:
    return Result[Color256, string].ok Color256.darkOrange32
  if rgb == "#d75f5f".hexToRgb.get:
    return Result[Color256, string].ok Color256.indianRed2
  if rgb == "#d75f87".hexToRgb.get:
    return Result[Color256, string].ok Color256.hotPink32
  if rgb == "#d75faf".hexToRgb.get:
    return Result[Color256, string].ok Color256.hotPink2
  if rgb == "#d75fd7".hexToRgb.get:
    return Result[Color256, string].ok Color256.orchid
  if rgb == "#d75fff".hexToRgb.get:
    return Result[Color256, string].ok Color256.mediumOrchid11
  if rgb == "#d78700".hexToRgb.get:
    return Result[Color256, string].ok Color256.orange3
  if rgb == "#d7875f".hexToRgb.get:
    return Result[Color256, string].ok Color256.lightSalmon32
  if rgb == "#d78787".hexToRgb.get:
    return Result[Color256, string].ok Color256.lightPink3
  if rgb == "#d787af".hexToRgb.get:
    return Result[Color256, string].ok Color256.pink3
  if rgb == "#d787d7".hexToRgb.get:
    return Result[Color256, string].ok Color256.plum3
  if rgb == "#d787ff".hexToRgb.get:
    return Result[Color256, string].ok Color256.violet
  if rgb == "#d7af00".hexToRgb.get:
    return Result[Color256, string].ok Color256.gold32
  if rgb == "#d7af5f".hexToRgb.get:
    return Result[Color256, string].ok Color256.lightGoldenrod3
  if rgb == "#d7af87".hexToRgb.get:
    return Result[Color256, string].ok Color256.tan
  if rgb == "#d7afaf".hexToRgb.get:
    return Result[Color256, string].ok Color256.mistyRose3
  if rgb == "#d7afd7".hexToRgb.get:
    return Result[Color256, string].ok Color256.thistle3
  if rgb == "#d7afff".hexToRgb.get:
    return Result[Color256, string].ok Color256.plum2
  if rgb == "#d7d700".hexToRgb.get:
    return Result[Color256, string].ok Color256.yellow32
  if rgb == "#d7d75f".hexToRgb.get:
    return Result[Color256, string].ok Color256.khaki3
  if rgb == "#d7d787".hexToRgb.get:
    return Result[Color256, string].ok Color256.lightGoldenrod2
  if rgb == "#d7d7af".hexToRgb.get:
    return Result[Color256, string].ok Color256.lightYellow3
  if rgb == "#d7d7d7".hexToRgb.get:
    return Result[Color256, string].ok Color256.gray84
  if rgb == "#d7d7ff".hexToRgb.get:
    return Result[Color256, string].ok Color256.lightSteelBlue1
  if rgb == "#d7ff00".hexToRgb.get:
    return Result[Color256, string].ok Color256.yellow2
  if rgb == "#d7ff5f".hexToRgb.get:
    return Result[Color256, string].ok Color256.darkOliveGreen11
  if rgb == "#d7ff87".hexToRgb.get:
    return Result[Color256, string].ok Color256.darkOliveGreen12
  if rgb == "#d7ffaf".hexToRgb.get:
    return Result[Color256, string].ok Color256.darkSeaGreen12
  if rgb == "#d7ffd7".hexToRgb.get:
    return Result[Color256, string].ok Color256.honeydew2
  if rgb == "#d7ffff".hexToRgb.get:
    return Result[Color256, string].ok Color256.lightCyan1
  if rgb == "#ff0000".hexToRgb.get:
    return Result[Color256, string].ok Color256.red1
  if rgb == "#ff005f".hexToRgb.get:
    return Result[Color256, string].ok Color256.deepPink2
  if rgb == "#ff0087".hexToRgb.get:
    return Result[Color256, string].ok Color256.deepPink11
  if rgb == "#ff00af".hexToRgb.get:
    return Result[Color256, string].ok Color256.deepPink12
  if rgb == "#ff00d7".hexToRgb.get:
    return Result[Color256, string].ok Color256.magenta22
  if rgb == "#ff00ff".hexToRgb.get:
    return Result[Color256, string].ok Color256.magenta1
  if rgb == "#ff5f00".hexToRgb.get:
    return Result[Color256, string].ok Color256.orangeRed1
  if rgb == "#ff5f5f".hexToRgb.get:
    return Result[Color256, string].ok Color256.indianRed11
  if rgb == "#ff5f87".hexToRgb.get:
    return Result[Color256, string].ok Color256.indianRed12
  if rgb == "#ff5faf".hexToRgb.get:
    return Result[Color256, string].ok Color256.hotPink11
  if rgb == "#ff5fd7".hexToRgb.get:
    return Result[Color256, string].ok Color256.hotPink12
  if rgb == "#ff5fff".hexToRgb.get:
    return Result[Color256, string].ok Color256.mediumOrchid12
  if rgb == "#ff8700".hexToRgb.get:
    return Result[Color256, string].ok Color256.darkOrange
  if rgb == "#ff875f".hexToRgb.get:
    return Result[Color256, string].ok Color256.salmon1
  if rgb == "#ff8787".hexToRgb.get:
    return Result[Color256, string].ok Color256.lightCoral
  if rgb == "#ff87af".hexToRgb.get:
    return Result[Color256, string].ok Color256.paleVioletRed1
  if rgb == "#ff87d7".hexToRgb.get:
    return Result[Color256, string].ok Color256.orchid2
  if rgb == "#ff87ff".hexToRgb.get:
    return Result[Color256, string].ok Color256.orchid1
  if rgb == "#ffaf00".hexToRgb.get:
    return Result[Color256, string].ok Color256.orange1
  if rgb == "#ffaf5f".hexToRgb.get:
    return Result[Color256, string].ok Color256.sandyBrown
  if rgb == "#ffaf87".hexToRgb.get:
    return Result[Color256, string].ok Color256.lightSalmon1
  if rgb == "#ffafaf".hexToRgb.get:
    return Result[Color256, string].ok Color256.lightPink1
  if rgb == "#ffafd7".hexToRgb.get:
    return Result[Color256, string].ok Color256.pink1
  if rgb == "#ffafff".hexToRgb.get:
    return Result[Color256, string].ok Color256.plum1
  if rgb == "#ffd700".hexToRgb.get:
    return Result[Color256, string].ok Color256.gold1
  if rgb == "#ffd75f".hexToRgb.get:
    return Result[Color256, string].ok Color256.lightGoldenrod21
  if rgb == "#ffd787".hexToRgb.get:
    return Result[Color256, string].ok Color256.lightGoldenrod22
  if rgb == "#ffd7af".hexToRgb.get:
    return Result[Color256, string].ok Color256.navajoWhite1
  if rgb == "#ffd7d7".hexToRgb.get:
    return Result[Color256, string].ok Color256.mistyRose1
  if rgb == "#ffd7ff".hexToRgb.get:
    return Result[Color256, string].ok Color256.thistle1
  if rgb == "#ffff00".hexToRgb.get:
    return Result[Color256, string].ok Color256.yellow1
  if rgb == "#ffff5f".hexToRgb.get:
    return Result[Color256, string].ok Color256.lightGoldenrod1
  if rgb == "#ffff87".hexToRgb.get:
    return Result[Color256, string].ok Color256.khaki1
  if rgb == "#ffffaf".hexToRgb.get:
    return Result[Color256, string].ok Color256.wheat1
  if rgb == "#ffffd7".hexToRgb.get:
    return Result[Color256, string].ok Color256.cornsilk1
  if rgb == "#ffffff".hexToRgb.get:
    return Result[Color256, string].ok Color256.gray100
  if rgb == "#080808".hexToRgb.get:
    return Result[Color256, string].ok Color256.gray3
  if rgb == "#121212".hexToRgb.get:
    return Result[Color256, string].ok Color256.gray7
  if rgb == "#1c1c1c".hexToRgb.get:
    return Result[Color256, string].ok Color256.gray11
  if rgb == "#262626".hexToRgb.get:
    return Result[Color256, string].ok Color256.gray15
  if rgb == "#303030".hexToRgb.get:
    return Result[Color256, string].ok Color256.gray19
  if rgb == "#3a3a3a".hexToRgb.get:
    return Result[Color256, string].ok Color256.gray23
  if rgb == "#444444".hexToRgb.get:
    return Result[Color256, string].ok Color256.gray27
  if rgb == "#4e4e4e".hexToRgb.get:
    return Result[Color256, string].ok Color256.gray30
  if rgb == "#585858".hexToRgb.get:
    return Result[Color256, string].ok Color256.gray35
  if rgb == "#626262".hexToRgb.get:
    return Result[Color256, string].ok Color256.gray39
  if rgb == "#6c6c6c".hexToRgb.get:
    return Result[Color256, string].ok Color256.gray42
  if rgb == "#767676".hexToRgb.get:
    return Result[Color256, string].ok Color256.gray46
  if rgb == "#808080".hexToRgb.get:
    return Result[Color256, string].ok Color256.gray50
  if rgb == "#8a8a8A".hexToRgb.get:
    return Result[Color256, string].ok Color256.gray54
  if rgb == "#949494".hexToRgb.get:
    return Result[Color256, string].ok Color256.gray58
  if rgb == "#9e9e9e".hexToRgb.get:
    return Result[Color256, string].ok Color256.gray62
  if rgb == "#a8a8a8".hexToRgb.get:
    return Result[Color256, string].ok Color256.gray66
  if rgb == "#b2b2b2".hexToRgb.get:
    return Result[Color256, string].ok Color256.gray70
  if rgb == "#bcbcbc".hexToRgb.get:
    return Result[Color256, string].ok Color256.gray74
  if rgb == "#c6c6c6".hexToRgb.get:
    return Result[Color256, string].ok Color256.gray78
  if rgb == "#d0d0d0".hexToRgb.get:
    return Result[Color256, string].ok Color256.gray82
  if rgb == "#dadada".hexToRgb.get:
    return Result[Color256, string].ok Color256.gray85
  if rgb == "#e4e4e4".hexToRgb.get:
    return Result[Color256, string].ok Color256.gray89
  if rgb == "#eeeeeE".hexToRgb.get:
    return Result[Color256, string].ok Color256.gray93
  else:
    return Result[Color256, string].err "Invalid value"

proc isTermDefaultColor*(i: EditorColorIndex): bool {.inline.} =
  i == termDefaultForeground or i == termDefaultBackground

proc isTermDefaultColor*(c: Color): bool {.inline.} =
  c.rgb.isTermDefaultColor or c.index.isTermDefaultColor

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

## Set a EditorColorIndex to ColorThemeTable.
proc setBackgroundIndex*(
  theme: ColorTheme,
  pairIndex: EditorColorPairIndex,
  colorIndex: EditorColorIndex | int) {.inline.} =

    ColorThemeTable[theme][pairIndex].background.index = colorIndex

## Set a EditorColorIndex to ColorThemeTable.
proc setForegroundIndex*(
  theme: ColorTheme,
  pairIndex: EditorColorPairIndex,
  colorIndex: EditorColorIndex | int) {.inline.} =

    ColorThemeTable[theme][pairIndex].foreground.index = colorIndex

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

## Converts an rgb value to a color,
## the closest color is approximated
proc rgbToColor8*(orignRgb: Rgb): Color8 =
  if orignRgb.isTermDefaultColor: return Color8.default

  var lowestDifference = 100000

  for name in Color8:
    let difference = calcRGBDifference(orignRgb, name.rgb)
    if difference < lowestDifference:
      lowestDifference = difference
      result = name
      if difference == 0:
        break

## Converts an rgb value to a color,
## the closest color is approximated
proc rgbToColor16*(orignRgb: Rgb): Color16 =
  if orignRgb.isTermDefaultColor: return Color16.default

  var lowestDifference = 100000

  for name in Color16:
    let difference = calcRGBDifference(orignRgb, name.rgb)
    if difference < lowestDifference:
      lowestDifference = difference
      result = name
      if difference == 0:
        break

## Converts an rgb value to a color,
## the closest color is approximated
proc rgbToColor256*(orignRgb: Rgb): Color256 =
  if orignRgb.isTermDefaultColor: return Color256.default

  var lowestDifference = 100000

  for name in Color256:
    let difference = calcRGBDifference(orignRgb, name.rgb)
    if difference < lowestDifference:
      lowestDifference = difference
      result = name
      if difference == 0:
        break

## Donwgrade rgb to 256 or 16 or 8.
## Do nothing if greater than 256.
proc downgrade*(rgb: Rgb, colorMode: ColorMode): Rgb =
  case colorMode:
    of ColorMode.c8:
     rgb.rgbToColor8.rgb
    of ColorMode.c16:
     rgb.rgbToColor16.rgb
    of ColorMode.c256:
     rgb.rgbToColor256.rgb
    else:
      rgb

## Donwgrade theme colors to 256 or 16 or 8.
## Do nothing if greater than 256.
proc downgrade*(theme: ColorTheme, mode: ColorMode) =
  if mode.int > 256: return

  for pairIndex, pair in ColorThemeTable[theme]:
    case mode:
      of ColorMode.c8:
       theme.setForegroundRgb(pairIndex, pair.foreground.rgb.rgbToColor8.rgb)
       theme.setBackgroundRgb(pairIndex, pair.background.rgb.rgbToColor8.rgb)
      of ColorMode.c16:
       theme.setForegroundRgb(pairIndex, pair.foreground.rgb.rgbToColor16.rgb)
       theme.setBackgroundRgb(pairIndex, pair.background.rgb.rgbToColor16.rgb)
      of ColorMode.c256:
       theme.setForegroundRgb(pairIndex, pair.foreground.rgb.rgbToColor256.rgb)
       theme.setBackgroundRgb(pairIndex, pair.background.rgb.rgbToColor256.rgb)
      else:
        discard

## Init a Rgb definition of Color.
proc initColor*(c: Color): Result[(), string] =
  # Ignore the terminal default color.
  if not c.isTermDefaultColor:
    let r = c.index.int16.initNcursesColor(c.rgb.red, c.rgb.green, c.rgb.blue)
    if r.isErr: return Result[(), string].err r.error

  return Result[(), string].ok ()

proc initColor*(pair: ColorPair): Result[(), string] =
  block foreground:
    let r = pair.foreground.initColor
    if r.isErr: return Result[(), string].err r.error

  block background:
    let r = pair.background.initColor
    if r.isErr: return Result[(), string].err r.error

  return Result[(), string].ok ()

## Init a Ncurses color pair.
## Downgrade colors if not 24bit support.
proc initColorPair*(
  pairIndex: EditorColorPairIndex | int,
  colorMode: ColorMode,
  foreground, background: Color): Result[(), string] =

    let
      fg: int16 =
        if foreground.isTermDefaultColor:
          -1
        else:
          case colorMode:
            of ColorMode.c8:
              foreground.rgb.rgbToColor8.int16
            of ColorMode.c16:
              foreground.rgb.rgbToColor16.int16
            of ColorMode.c256:
              foreground.rgb.rgbToColor256.int16
            else:
              foreground.index.int16

      bg: int16 =
        if background.isTermDefaultColor:
          -1
        else:
          case colorMode:
            of ColorMode.c8:
              background.rgb.rgbToColor8.int16
            of ColorMode.c16:
              background.rgb.rgbToColor16.int16
            of ColorMode.c256:
              background.rgb.rgbToColor256.int16
            else:
              background.index.int16

    return initNcursesColorPair(pairIndex.int, fg, bg)

## Init a new Ncurses color pair.
proc initColorPair(
  pairIndex: EditorColorPairIndex,
  colorMode: ColorMode,
  pair: ColorPair): Result[(), string] =

    return pairIndex.initColorPair(colorMode, pair.foreground, pair.background)

## Init Ncurses colors and color pairs.
proc initEditrorColor*(
  theme: ColorTheme,
  colorMode: ColorMode): Result[(), string] =

    if colorMode >= ColorMode.c24bit:
      # Override Ncurses default color definitions if TrueColor is supported.
      for _, colorPair in ColorThemeTable[theme]:
        # Init all color defines.
        let r = colorPair.initColor
        if r.isErr: return Result[(), string].err r.error

    for pairIndex, colorPair in ColorThemeTable[theme]:
      let r = pairIndex.initColorPair(colorMode, colorPair)
      if r.isErr: return r

    return Result[(), string].ok ()
