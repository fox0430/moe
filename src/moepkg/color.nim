import std/[strutils, tables, macros, strformat, options, sequtils]
import pkg/termtools
import unicodeext

type
  # Hex color code
  ColorCode* = array[6, char]

  # None is the terminal default color
  ColorPair* = object
    fg*: Option[ColorCode]
    bg*: Option[ColorCode]

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

proc `$`*(colorCode: ColorCode): string =
  for ch in colorCode: result &= ch

proc toRGBInt*(colorCode: ColorCode): tuple[r, g, b: int] =
  let colorCodeStr = $colorCode
  result.r = fromHex[int](colorCodeStr[0..1])
  result.g = fromHex[int](colorCodeStr[2..3])
  result.b = fromHex[int](colorCodeStr[4..5])

proc initColorPair*(fgColorStr, bgColorStr: string): ColorPair {.inline.} =
  result.fg = toColorCode(fgColorStr)
  result.bg = toColorCode(bgColorStr)

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

#type EditorColorCode* = object
#  editorBg*: Option[ColorCode]
#  lineNum*: Option[ColorCode]
#  lineNumBg*: Option[ColorCode]
#  currentLineNum*: Option[ColorCode]
#  currentLineNumBg*: Option[ColorCode]
#  # status line
#  statusLineNormalMode*: Option[ColorCode]
#  statusLineNormalModeBg*: Option[ColorCode]
#  statusLineModeNormalMode*: Option[ColorCode]
#  statusLineModeNormalModeBg*: Option[ColorCode]
#  statusLineNormalModeInactive*: Option[ColorCode]
#  statusLineNormalModeInactiveBg*: Option[ColorCode]
#
#  statusLineInsertMode*: Option[ColorCode]
#  statusLineInsertModeBg*: Option[ColorCode]
#  statusLineModeInsertMode*: Option[ColorCode]
#  statusLineModeInsertModeBg*: Option[ColorCode]
#  statusLineInsertModeInactive*: Option[ColorCode]
#  statusLineInsertModeInactiveBg*: Option[ColorCode]
#
#  statusLineVisualMode*: Option[ColorCode]
#  statusLineVisualModeBg*: Option[ColorCode]
#  statusLineModeVisualMode*: Option[ColorCode]
#  statusLineModeVisualModeBg*: Option[ColorCode]
#  statusLineVisualModeInactive*: Option[ColorCode]
#  statusLineVisualModeInactiveBg*: Option[ColorCode]
#
#  statusLineReplaceMode*: Option[ColorCode]
#  statusLineReplaceModeBg*: Option[ColorCode]
#  statusLineModeReplaceMode*: Option[ColorCode]
#  statusLineModeReplaceModeBg*: Option[ColorCode]
#  statusLineReplaceModeInactive*: Option[ColorCode]
#  statusLineReplaceModeInactiveBg*: Option[ColorCode]
#
#  statusLineFilerMode*: Option[ColorCode]
#  statusLineFilerModeBg*: Option[ColorCode]
#  statusLineModeFilerMode*: Option[ColorCode]
#  statusLineModeFilerModeBg*: Option[ColorCode]
#  statusLineFilerModeInactive*: Option[ColorCode]
#  statusLineFilerModeInactiveBg*: Option[ColorCode]
#
#  statusLineExMode*: Option[ColorCode]
#  statusLineExModeBg*: Option[ColorCode]
#  statusLineModeExMode*: Option[ColorCode]
#  statusLineModeExModeBg*: Option[ColorCode]
#  statusLineExModeInactive*: Option[ColorCode]
#  statusLineExModeInactiveBg*: Option[ColorCode]
#
#  statusLineGitBranch*: Option[ColorCode]
#  statusLineGitBranchBg*: Option[ColorCode]
#  # tab line
#  tab*: Option[ColorCode]
#  tabBg*: Option[ColorCode]
#  currentTab*: Option[ColorCode]
#  currentTabBg*: Option[ColorCode]
#  # command bar
#  commandBar*: Option[ColorCode]
#  commandBarBg*: Option[ColorCode]
#  # error message
#  errorMessage*: Option[ColorCode]
#  errorMessageBg*: Option[ColorCode]
#  # search result highlighting
#  searchResult*: Option[ColorCode]
#  searchResultBg*: Option[ColorCode]
#  # selected area in visual mode
#  visualMode*: Option[ColorCode]
#  visualModeBg*: Option[ColorCode]
#
#  # color scheme
#  defaultChar*: Option[ColorCode]
#  gtKeyword*: Option[ColorCode]
#  gtFunctionName*: Option[ColorCode]
#  gtTypeName*: Option[ColorCode]
#  gtBoolean*: Option[ColorCode]
#  gtStringLit*: Option[ColorCode]
#  gtSpecialVar*: Option[ColorCode]
#  gtBuiltin*: Option[ColorCode]
#  gtDecNumber*: Option[ColorCode]
#  gtComment*: Option[ColorCode]
#  gtLongComment*: Option[ColorCode]
#  gtWhitespace*: Option[ColorCode]
#  gtPreprocessor*: Option[ColorCode]
#  gtPragma*: Option[ColorCode]
#
#  # filer mode
#  currentFile*: Option[ColorCode]
#  currentFileBg*: Option[ColorCode]
#  file*: Option[ColorCode]
#  fileBg*: Option[ColorCode]
#  dir*: Option[ColorCode]
#  dirBg*: Option[ColorCode]
#  pcLink*: Option[ColorCode]
#  pcLinkBg*: Option[ColorCode]
#  # pop up window
#  popUpWindow*: Option[ColorCode]
#  popUpWindowBg*: Option[ColorCode]
#  popUpWinCurrentLine*: Option[ColorCode]
#  popUpWinCurrentLineBg*: Option[ColorCode]
#  # replace text highlighting
#  replaceText*: Option[ColorCode]
#  replaceTextBg*: Option[ColorCode]
#
#  # pair of paren highlighting
#  parenText*: Option[ColorCode]
#  parenTextBg*: Option[ColorCode]
#
#  # highlight other uses current word
#  currentWord*: Option[ColorCode]
#  currentWordBg*: Option[ColorCode]
#
#  # highlight full width space
#  highlightFullWidthSpace*: Option[ColorCode]
#  highlightFullWidthSpaceBg*: Option[ColorCode]
#
#  # highlight trailing spaces
#  highlightTrailingSpaces*: Option[ColorCode]
#  highlightTrailingSpacesBg*: Option[ColorCode]
#
#  # highlight reserved words
#  reservedWord*: Option[ColorCode]
#  reservedWordBg*: Option[ColorCode]
#
#  # highlight history manager
#  currentHistory*: Option[ColorCode]
#  currentHistoryBg*: Option[ColorCode]
#
#  # highlight diff
#  addedLine*: Option[ColorCode]
#  addedLineBg*: Option[ColorCode]
#  deletedLine*: Option[ColorCode]
#  deletedLineBg*: Option[ColorCode]
#
#  # configuration mode
#  currentSetting*: Option[ColorCode]
#  currentSettingBg*: Option[ColorCode]
#
#  # highlight curent line background
#  currentLineBg*: Option[ColorCode]

type
  EditorColorPair* = object
    default*: ColorPair
    lineNum*: ColorPair
    currentLineNum*: ColorPair
    # status line
    statusLineNormalMode*: ColorPair
    statusLineModeNormalMode*: ColorPair
    statusLineNormalModeInactive*: ColorPair
    statusLineInsertMode*: ColorPair
    statusLineModeInsertMode*: ColorPair
    statusLineInsertModeInactive*: ColorPair
    statusLineVisualMode*: ColorPair
    statusLineModeVisualMode*: ColorPair
    statusLineVisualModeInactive*: ColorPair
    statusLineReplaceMode*: ColorPair
    statusLineModeReplaceMode*: ColorPair
    statusLineReplaceModeInactive*: ColorPair
    statusLineFilerMode*: ColorPair
    statusLineModeFilerMode*: ColorPair
    statusLineFilerModeInactive*: ColorPair
    statusLineExMode*: ColorPair
    statusLineModeExMode*: ColorPair
    statusLineExModeInactive*: ColorPair
    statusLineGitBranch*: ColorPair
    # tab lnie
    tab*: ColorPair
    # tab line
    currentTab*: ColorPair
    # command bar
    commandBar*: ColorPair
    # error message
    errorMessage*: ColorPair
    # search result highlighting
    searchResult*: ColorPair
    # selected area in visual mode
    visualMode*: ColorPair

    # color scheme
    defaultChar*: ColorPair
    keyword*: ColorPair
    functionName*: ColorPair
    typeName*: ColorPair
    boolean*:  ColorPair
    specialVar*: ColorPair
    builtin*: ColorPair
    stringLit*: ColorPair
    decNumber*: ColorPair
    comment*: ColorPair
    longComment*: ColorPair
    whitespace*: ColorPair
    preprocessor*: ColorPair
    pragma*: ColorPair

    # filer mode
    currentFile*: ColorPair
    file*: ColorPair
    dir*: ColorPair
    pcLink*: ColorPair
    # pop up window
    popUpWindow*: ColorPair
    popUpWinCurrentLine*: ColorPair
    # replace text highlighting
    replaceText*: ColorPair
    # pair of paren highlighting
    parenText*: ColorPair
    # highlight other uses current word
    currentWord*: ColorPair
    # highlight full width space
    highlightFullWidthSpace*: ColorPair
    # highlight trailing spaces
    highlightTrailingSpaces*: ColorPair
    # highlight reserved words
    reservedWord*: ColorPair
    # highlight history manager
    currentHistory*: ColorPair
    # highlight diff
    addedLine*: ColorPair
    deletedLine*: ColorPair
    # configuration mode
    currentSetting*: ColorPair
    # Highlight current line background
    currentLine*: ColorPair

# TODO: Fix
var currentColorTheme* = ColorTheme.dark

var ColorThemeTable*: array[ColorTheme, EditorColorPair] = [
  config: EditorColorPair(
    default: ColorPair(fg: none(ColorCode),  bg: none(ColorCode)),

    # Line number
    lineNum: ColorPair(fg: toColorCode("8a8a8a"), bg: none(ColorCode)),
    currentLineNum: ColorPair(fg: toColorCode("008080"), bg: none(ColorCode)),

    # Status line
    statusLineNormalMode: ColorPair(fg: toColorCode("ffffff"), bg: toColorCode("0000ff")),
    statusLineModeNormalMode: ColorPair(fg: toColorCode("000000"), bg: toColorCode("ffffff")),
    statusLineNormalModeInactive: ColorPair(fg: toColorCode("0000ff"), bg: toColorCode("ffffff")),

    statusLineInsertMode: ColorPair(fg: toColorCode("ffffff"), bg:toColorCode("0000ff")),
    statusLineModeInsertMode: ColorPair(fg: toColorCode("000000"), bg: toColorCode("ffffff")),
    statusLineInsertModeInactive: ColorPair(fg: toColorCode("0000ff"), bg: toColorCode("ffffff")),

    statusLineVisualMode: ColorPair(fg: toColorCode("ffffff"), bg: toColorCode("0000ff")),
    statusLineModeVisualMode: ColorPair(fg: toColorCode("000000"), bg: toColorCode("ffffff")),
    statusLineVisualModeInactive: ColorPair(fg: toColorCode("0000ff"), bg: toColorCode("ffffff")),

    statusLineReplaceMode: ColorPair(fg: toColorCode("ffffff"), bg: toColorCode("0000ff")),
    statusLineModeReplaceMode: ColorPair(fg: toColorCode("000000"), bg: toColorCode("ffffff")),
    statusLineReplaceModeInactive: ColorPair(fg: toColorCode("0000ff"), bg: toColorCode("ffffff")),

    statusLineFilerMode: ColorPair(fg: toColorCode("ffffff"), bg: toColorCode("0000ff")),
    statusLineModeFilerMode: ColorPair(fg: toColorCode("000000"), bg: toColorCode("ffffff")),
    statusLineFilerModeInactive: ColorPair(fg: toColorCode("0000ff"), bg: toColorCode("ffffff")),

    statusLineExMode: ColorPair(fg: toColorCode("ffffff"), bg: toColorCode("0000ff")),
    statusLineModeExMode: ColorPair(fg: toColorCode("000000"), bg: toColorCode("ffffff")),
    statusLineExModeInactive: ColorPair(fg: toColorCode("0000ff"), bg: toColorCode("ffffff")),

    statusLineGitBranch: ColorPair(fg: toColorCode("ffffff"), bg: toColorCode("0000ff")),
    # tab line
    tab: ColorPair(fg: toColorCode("ffffff"), bg: none(ColorCode)),
    currentTab: ColorPair(fg: toColorCode("ffffff"), bg: toColorCode("0000ff")),
    # command  bar
    commandBar: ColorPair(fg: toColorCode("ffffff"), bg: none(ColorCode)),
    # error message
    errorMessage: ColorPair(fg: toColorCode("ff0000"), bg: none(ColorCode)),
    # search result highlighting
    searchResult: ColorPair(fg: none(ColorCode), bg: toColorCode("ff0000")),
    # selected area in visual mode
    visualMode: ColorPair(fg: toColorCode("ffffff"), bg: toColorCode("800080")),

    # color scheme
    defaultChar: ColorPair(fg: toColorCode("ffffff"), bg: none(ColorCode)),
    keyword: ColorPair(fg: toColorCode("87d7ff"), bg: none(ColorCode)),
    functionName: ColorPair(fg: toColorCode("ffd700"), bg: none(ColorCode)),
    typeName: ColorPair(fg: toColorCode("008000"), bg: none(ColorCode)),
    boolean: ColorPair(fg: toColorCode("ffff00"), bg: none(ColorCode)),
    stringLit: ColorPair(fg: toColorCode("ffff00"), bg: none(ColorCode)),
    specialVar: ColorPair(fg: toColorCode("008000"), bg: none(ColorCode)),
    builtin: ColorPair(fg: toColorCode("ffff00"), bg: none(ColorCode)),
    decNumber: ColorPair(fg: toColorCode("00ffff"), bg: none(ColorCode)),
    comment: ColorPair(fg: toColorCode("808080"), bg: none(ColorCode)),
    longComment: ColorPair(fg: toColorCode("808080"), bg: none(ColorCode)),
    whitespace: ColorPair(fg: toColorCode("808080"), bg: none(ColorCode)),
    preprocessor: ColorPair(fg: toColorCode("008000"), bg: none(ColorCode)),
    pragma: ColorPair(fg: toColorCode("ffff00"), bg: none(ColorCode)),

    # filer mode
    currentFile: ColorPair(fg: toColorCode("ffffff"), bg: toColorCode("008080")),
    file: ColorPair(fg: toColorCode("ffffff"), bg: none(ColorCode)),
    dir: ColorPair(fg: toColorCode("0000ff"), bg: none(ColorCode)),
    pcLink: ColorPair(fg: toColorCode("008080"), bg: toColorCode("000000")),
    # pop up window
    popUpWindow: ColorPair(fg: toColorCode("ffffff"), bg: toColorCode("000000")),
    popUpWinCurrentLine: ColorPair(fg: toColorCode("0000ff"), bg: toColorCode("000000")),
    # replace text highlighting
    # TODO: Fix color code. (default)
    replaceText: ColorPair(fg: none(ColorCode), bg: toColorCode("ff0000")),
    # pair of paren highlighting
    # TODO: Fix color code. (default)
    parenText: ColorPair(fg: none(ColorCode), bg: toColorCode("0000ff")),
    # highlight other uses current word
    currentWord: ColorPair(fg: none(ColorCode), bg: toColorCode("808080")),
    # highlight full width space
    highlightFullWidthSpace: ColorPair(fg: toColorCode("ff0000"), bg: toColorCode("ff0000")),
    # highlight trailing spaces
    highlightTrailingSpaces: ColorPair(fg: toColorCode("ff0000"), bg: toColorCode("ff0000")),
    # highlight reserved words
    reservedWord: ColorPair(fg: toColorCode("ffffff"), bg: toColorCode("808080")),
    # highlight history manager
    currentHistory: ColorPair(fg: toColorCode("ffffff"), bg: toColorCode("008080")),
    # highlight diff
    addedLine: ColorPair(fg: toColorCode("008000"), bg: none(ColorCode)),
    deletedLine: ColorPair(fg: toColorCode("ff0000"), bg: none(ColorCode)),
    # configuration mode
    currentSetting: ColorPair(fg: toColorCode("ffffff"), bg: toColorCode("008080")),
    # Highlight current line background
    currentLine: ColorPair(fg: none(ColorCode), bg: toColorCode("444444"))
  ),
  vscode: EditorColorPair(
    default: ColorPair(fg: none(ColorCode), bg: none(ColorCode)),

    # Line number
    lineNum: ColorPair(fg: toColorCode("8a8a8a"), bg: none(ColorCode)),
    currentLineNum: ColorPair(fg: toColorCode("008080"), bg: none(ColorCode)),

    # Status line
    statusLineNormalMode: ColorPair(fg: toColorCode("ffffff"), bg: toColorCode("0000ff")),
    statusLineModeNormalMode: ColorPair(fg: toColorCode("000000"), bg: toColorCode("ffffff")),
    statusLineNormalModeInactive: ColorPair(fg: toColorCode("0000ff"), bg: toColorCode("ffffff")),

    statusLineInsertMode: ColorPair(fg: toColorCode("ffffff"), bg:toColorCode("0000ff")),
    statusLineModeInsertMode: ColorPair(fg: toColorCode("000000"), bg: toColorCode("ffffff")),
    statusLineInsertModeInactive: ColorPair(fg: toColorCode("0000ff"), bg: toColorCode("ffffff")),

    statusLineVisualMode: ColorPair(fg: toColorCode("ffffff"), bg: toColorCode("0000ff")),
    statusLineModeVisualMode: ColorPair(fg: toColorCode("000000"), bg: toColorCode("ffffff")),
    statusLineVisualModeInactive: ColorPair(fg: toColorCode("0000ff"), bg: toColorCode("ffffff")),

    statusLineReplaceMode: ColorPair(fg: toColorCode("ffffff"), bg: toColorCode("0000ff")),
    statusLineModeReplaceMode: ColorPair(fg: toColorCode("000000"), bg: toColorCode("ffffff")),
    statusLineReplaceModeInactive: ColorPair(fg: toColorCode("0000ff"), bg: toColorCode("ffffff")),

    statusLineFilerMode: ColorPair(fg: toColorCode("ffffff"), bg: toColorCode("0000ff")),
    statusLineModeFilerMode: ColorPair(fg: toColorCode("000000"), bg: toColorCode("ffffff")),
    statusLineFilerModeInactive: ColorPair(fg: toColorCode("0000ff"), bg: toColorCode("ffffff")),

    statusLineExMode: ColorPair(fg: toColorCode("ffffff"), bg: toColorCode("0000ff")),
    statusLineModeExMode: ColorPair(fg: toColorCode("000000"), bg: toColorCode("ffffff")),
    statusLineExModeInactive: ColorPair(fg: toColorCode("0000ff"), bg: toColorCode("ffffff")),

    statusLineGitBranch: ColorPair(fg: toColorCode("ffffff"), bg: toColorCode("0000ff")),
    # tab line
    tab: ColorPair(fg: toColorCode("ffffff"), bg: none(ColorCode)),
    currentTab: ColorPair(fg: toColorCode("ffffff"), bg: toColorCode("0000ff")),
    # command  bar
    commandBar: ColorPair(fg: toColorCode("ffffff"), bg: none(ColorCode)),
    # error message
    errorMessage: ColorPair(fg: toColorCode("ff0000"), bg: none(ColorCode)),
    # search result highlighting
    searchResult: ColorPair(fg: none(ColorCode), bg: toColorCode("ff0000")),
    # selected area in visual mode
    visualMode: ColorPair(fg: toColorCode("ffffff"), bg: toColorCode("800080")),

    # color scheme
    defaultChar: ColorPair(fg: toColorCode("ffffff"), bg: none(ColorCode)),
    keyword: ColorPair(fg: toColorCode("87d7ff"), bg: none(ColorCode)),
    functionName: ColorPair(fg: toColorCode("ffd700"), bg: none(ColorCode)),
    typeName: ColorPair(fg: toColorCode("008000"), bg: none(ColorCode)),
    boolean: ColorPair(fg: toColorCode("ffff00"), bg: none(ColorCode)),
    stringLit: ColorPair(fg: toColorCode("ffff00"), bg: none(ColorCode)),
    specialVar: ColorPair(fg: toColorCode("008000"), bg: none(ColorCode)),
    builtin: ColorPair(fg: toColorCode("ffff00"), bg: none(ColorCode)),
    decNumber: ColorPair(fg: toColorCode("00ffff"), bg: none(ColorCode)),
    comment: ColorPair(fg: toColorCode("808080"), bg: none(ColorCode)),
    longComment: ColorPair(fg: toColorCode("808080"), bg: none(ColorCode)),
    whitespace: ColorPair(fg: toColorCode("808080"), bg: none(ColorCode)),
    preprocessor: ColorPair(fg: toColorCode("008000"), bg: none(ColorCode)),
    pragma: ColorPair(fg: toColorCode("ffff00"), bg: none(ColorCode)),

    # filer mode
    currentFile: ColorPair(fg: toColorCode("ffffff"), bg: toColorCode("008080")),
    file: ColorPair(fg: toColorCode("ffffff"), bg: none(ColorCode)),
    dir: ColorPair(fg: toColorCode("0000ff"), bg: none(ColorCode)),
    pcLink: ColorPair(fg: toColorCode("008080"), bg: toColorCode("000000")),
    # pop up window
    popUpWindow: ColorPair(fg: toColorCode("ffffff"), bg: toColorCode("000000")),
    popUpWinCurrentLine: ColorPair(fg: toColorCode("0000ff"), bg: toColorCode("000000")),
    # replace text highlighting
    # TODO: Fix color code. (default)
    replaceText: ColorPair(fg: none(ColorCode), bg: toColorCode("ff0000")),
    # pair of paren highlighting
    # TODO: Fix color code. (default)
    parenText: ColorPair(fg: none(ColorCode), bg: toColorCode("0000ff")),
    # highlight other uses current word
    currentWord: ColorPair(fg: none(ColorCode), bg: toColorCode("808080")),
    # highlight full width space
    highlightFullWidthSpace: ColorPair(fg: toColorCode("ff0000"), bg: toColorCode("ff0000")),
    # highlight trailing spaces
    highlightTrailingSpaces: ColorPair(fg: toColorCode("ff0000"), bg: toColorCode("ff0000")),
    # highlight reserved words
    reservedWord: ColorPair(fg: toColorCode("ffffff"), bg: toColorCode("808080")),
    # highlight history manager
    currentHistory: ColorPair(fg: toColorCode("ffffff"), bg: toColorCode("008080")),
    # highlight diff
    addedLine: ColorPair(fg: toColorCode("008000"), bg: none(ColorCode)),
    deletedLine: ColorPair(fg: toColorCode("ff0000"), bg: none(ColorCode)),
    # configuration mode
    currentSetting: ColorPair(fg: toColorCode("ffffff"), bg: toColorCode("008080")),
    # Highlight current line background
    currentLine: ColorPair(fg: none(ColorCode), bg: toColorCode("444444"))
  ),
  dark: EditorColorPair(
    default: ColorPair(fg: none(ColorCode),  bg: none(ColorCode)),

    # Line number
    lineNum: ColorPair(fg: toColorCode("8a8a8a"), bg: none(ColorCode)),
    currentLineNum: ColorPair(fg: toColorCode("008080"), bg: none(ColorCode)),

    # Status line
    statusLineNormalMode: ColorPair(fg: toColorCode("ffffff"), bg: toColorCode("0000ff")),
    statusLineModeNormalMode: ColorPair(fg: toColorCode("000000"), bg: toColorCode("ffffff")),
    statusLineNormalModeInactive: ColorPair(fg: toColorCode("0000ff"), bg: toColorCode("ffffff")),

    statusLineInsertMode: ColorPair(fg: toColorCode("ffffff"), bg:toColorCode("0000ff")),
    statusLineModeInsertMode: ColorPair(fg: toColorCode("000000"), bg: toColorCode("ffffff")),
    statusLineInsertModeInactive: ColorPair(fg: toColorCode("0000ff"), bg: toColorCode("ffffff")),

    statusLineVisualMode: ColorPair(fg: toColorCode("ffffff"), bg: toColorCode("0000ff")),
    statusLineModeVisualMode: ColorPair(fg: toColorCode("000000"), bg: toColorCode("ffffff")),
    statusLineVisualModeInactive: ColorPair(fg: toColorCode("0000ff"), bg: toColorCode("ffffff")),

    statusLineReplaceMode: ColorPair(fg: toColorCode("ffffff"), bg: toColorCode("0000ff")),
    statusLineModeReplaceMode: ColorPair(fg: toColorCode("000000"), bg: toColorCode("ffffff")),
    statusLineReplaceModeInactive: ColorPair(fg: toColorCode("0000ff"), bg: toColorCode("ffffff")),

    statusLineFilerMode: ColorPair(fg: toColorCode("ffffff"), bg: toColorCode("0000ff")),
    statusLineModeFilerMode: ColorPair(fg: toColorCode("000000"), bg: toColorCode("ffffff")),
    statusLineFilerModeInactive: ColorPair(fg: toColorCode("0000ff"), bg: toColorCode("ffffff")),

    statusLineExMode: ColorPair(fg: toColorCode("ffffff"), bg: toColorCode("0000ff")),
    statusLineModeExMode: ColorPair(fg: toColorCode("000000"), bg: toColorCode("ffffff")),
    statusLineExModeInactive: ColorPair(fg: toColorCode("0000ff"), bg: toColorCode("ffffff")),

    statusLineGitBranch: ColorPair(fg: toColorCode("ffffff"), bg: toColorCode("0000ff")),
    # tab line
    tab: ColorPair(fg: toColorCode("ffffff"), bg: none(ColorCode)),
    currentTab: ColorPair(fg: toColorCode("ffffff"), bg: toColorCode("0000ff")),
    # command  bar
    commandBar: ColorPair(fg: toColorCode("ffffff"), bg: none(ColorCode)),
    # error message
    errorMessage: ColorPair(fg: toColorCode("ff0000"), bg: none(ColorCode)),
    # search result highlighting
    searchResult: ColorPair(fg: none(ColorCode), bg: toColorCode("ff0000")),
    # selected area in visual mode
    visualMode: ColorPair(fg: toColorCode("ffffff"), bg: toColorCode("800080")),

    # color scheme
    defaultChar: ColorPair(fg: toColorCode("ffffff"), bg: none(ColorCode)),
    keyword: ColorPair(fg: toColorCode("87d7ff"), bg: none(ColorCode)),
    functionName: ColorPair(fg: toColorCode("ffd700"), bg: none(ColorCode)),
    typeName: ColorPair(fg: toColorCode("008000"), bg: none(ColorCode)),
    boolean: ColorPair(fg: toColorCode("ffff00"), bg: none(ColorCode)),
    stringLit: ColorPair(fg: toColorCode("ffff00"), bg: none(ColorCode)),
    specialVar: ColorPair(fg: toColorCode("008000"), bg: none(ColorCode)),
    builtin: ColorPair(fg: toColorCode("ffff00"), bg: none(ColorCode)),
    decNumber: ColorPair(fg: toColorCode("00ffff"), bg: none(ColorCode)),
    comment: ColorPair(fg: toColorCode("808080"), bg: none(ColorCode)),
    longComment: ColorPair(fg: toColorCode("808080"), bg: none(ColorCode)),
    whitespace: ColorPair(fg: toColorCode("808080"), bg: none(ColorCode)),
    preprocessor: ColorPair(fg: toColorCode("008000"), bg: none(ColorCode)),
    pragma: ColorPair(fg: toColorCode("ffff00"), bg: none(ColorCode)),

    # filer mode
    currentFile: ColorPair(fg: toColorCode("ffffff"), bg: toColorCode("008080")),
    file: ColorPair(fg: toColorCode("ffffff"), bg: none(ColorCode)),
    dir: ColorPair(fg: toColorCode("0000ff"), bg: none(ColorCode)),
    pcLink: ColorPair(fg: toColorCode("008080"), bg: toColorCode("000000")),
    # pop up window
    popUpWindow: ColorPair(fg: toColorCode("ffffff"), bg: toColorCode("000000")),
    popUpWinCurrentLine: ColorPair(fg: toColorCode("0000ff"), bg: toColorCode("000000")),
    # replace text highlighting
    # TODO: Fix color code. (default)
    replaceText: ColorPair(fg: none(ColorCode), bg: toColorCode("ff0000")),
    # pair of paren highlighting
    # TODO: Fix color code. (default)
    parenText: ColorPair(fg: none(ColorCode), bg: toColorCode("0000ff")),
    # highlight other uses current word
    currentWord: ColorPair(fg: none(ColorCode), bg: toColorCode("808080")),
    # highlight full width space
    highlightFullWidthSpace: ColorPair(fg: toColorCode("ff0000"), bg: toColorCode("ff0000")),
    # highlight trailing spaces
    highlightTrailingSpaces: ColorPair(fg: toColorCode("ff0000"), bg: toColorCode("ff0000")),
    # highlight reserved words
    reservedWord: ColorPair(fg: toColorCode("ffffff"), bg: toColorCode("808080")),
    # highlight history manager
    currentHistory: ColorPair(fg: toColorCode("ffffff"), bg: toColorCode("008080")),
    # highlight diff
    addedLine: ColorPair(fg: toColorCode("008000"), bg: none(ColorCode)),
    deletedLine: ColorPair(fg: toColorCode("ff0000"), bg: none(ColorCode)),
    # configuration mode
    currentSetting: ColorPair(fg: toColorCode("ffffff"), bg: toColorCode("008080")),
    # Highlight current line background
    currentLine: ColorPair(fg: none(ColorCode), bg: toColorCode("444444"))
  ),
  light: EditorColorPair(
    default: ColorPair(fg: none(ColorCode),  bg: none(ColorCode)),

    # Line number
    lineNum: ColorPair(fg: toColorCode("8a8a8a"), bg: none(ColorCode)),
    currentLineNum: ColorPair(fg: toColorCode("008000"), bg: none(ColorCode)),

    # statsu line
    statusLineNormalMode: ColorPair(fg: toColorCode("0000ff"), bg: toColorCode("8a8a8a")),
    statusLineModeNormalMode: ColorPair(fg: toColorCode("ffffff"), bg: toColorCode("008080")),
    statusLineNormalModeInactive: ColorPair(fg: toColorCode("8a8a8a"), bg: toColorCode("0000ff")),

    statusLineInsertMode: ColorPair(fg: toColorCode("0000ff"), bg:toColorCode("8a8a8a")),
    statusLineModeInsertMode: ColorPair(fg: toColorCode("ffffff"), bg: toColorCode("008080")),
    statusLineInsertModeInactive: ColorPair(fg: toColorCode("8a8a8a"), bg: toColorCode("0000ff")),


    statusLineVisualMode: ColorPair(fg: toColorCode("0000ff"), bg: toColorCode("8a8a8a")),
    statusLineModeVisualMode: ColorPair(fg: toColorCode("ffffff"), bg: toColorCode("008080")),
    statusLineVisualModeInactive: ColorPair(fg: toColorCode("8a8a8a"), bg: toColorCode("0000ff")),

    statusLineReplaceMode: ColorPair(fg: toColorCode("0000ff"), bg: toColorCode("8a8a8a")),
    statusLineModeReplaceMode: ColorPair(fg: toColorCode("008080"), bg: toColorCode("8a8a8a")),
    statusLineReplaceModeInactive: ColorPair(fg: toColorCode("8a8a8a"), bg: toColorCode("0000ff")),

    statusLineFilerMode: ColorPair(fg: toColorCode("0000ff"), bg: toColorCode("8a8a8a")),
    statusLineModeFilerMode: ColorPair(fg: toColorCode("ffffff"), bg: toColorCode("008080")),
    statusLineFilerModeInactive: ColorPair(fg: toColorCode("8a8a8a"), bg: toColorCode("0000ff")),

    statusLineExMode: ColorPair(fg: toColorCode("0000ff"), bg: toColorCode("8a8a8a")),
    statusLineModeExMode: ColorPair(fg: toColorCode("ffffff"), bg: toColorCode("008080")),
    statusLineExModeInactive: ColorPair(fg: toColorCode("8a8a8a"), bg: toColorCode("0000ff")),

    statusLineGitBranch: ColorPair(fg: toColorCode("0000ff"), bg: toColorCode("8a8a8a")),
    # tab line
    tab: ColorPair(fg: toColorCode("0000ff"), bg: toColorCode("8a8a8a")),
    currentTab: ColorPair(fg: toColorCode("ffffff"), bg: toColorCode("0000ff")),
    # command bar
    commandBar: ColorPair(fg: toColorCode("000000"), bg: none(ColorCode)),
    # error message
    errorMessage: ColorPair(fg: toColorCode("ff0000"), bg: none(ColorCode)),
    # search result highlighting
    searchResult: ColorPair(fg: none(ColorCode), bg: toColorCode("ff0000")),
    # selected area in visual mode
    visualMode: ColorPair(fg: toColorCode("000000"), bg: toColorCode("800080")),

    # color scheme
    defaultChar: ColorPair(fg: toColorCode("ffffff"), bg: none(ColorCode)),
    keyword: ColorPair(fg: toColorCode("5fffaf"), bg: none(ColorCode)),
    functionName: ColorPair(fg: toColorCode("ffd700"), bg: none(ColorCode)),
    typeName: ColorPair(fg: toColorCode("008000"), bg: none(ColorCode)),
    boolean: ColorPair(fg: toColorCode("ffff00"), bg: none(ColorCode)),
    stringLit: ColorPair(fg: toColorCode("800080"), bg: none(ColorCode)),
    specialVar: ColorPair(fg: toColorCode("008000"), bg: none(ColorCode)),
    builtin: ColorPair(fg: toColorCode("ffff00"), bg: none(ColorCode)),
    decNumber: ColorPair(fg: toColorCode("00ffff"), bg: none(ColorCode)),
    comment: ColorPair(fg: toColorCode("808080"), bg: none(ColorCode)),
    longComment: ColorPair(fg: toColorCode("808080"), bg: none(ColorCode)),
    whitespace: ColorPair(fg: toColorCode("808080"), bg: none(ColorCode)),
    preprocessor: ColorPair(fg: toColorCode("008000"), bg: none(ColorCode)),
    pragma: ColorPair(fg: toColorCode("ffff00"), bg: none(ColorCode)),

    # filer mode
    currentFile: ColorPair(fg: toColorCode("000000"), bg: toColorCode("ff0087")),
    file: ColorPair(fg: toColorCode("000000"), bg: none(ColorCode)),
    dir: ColorPair(fg: toColorCode("ff0087"), bg: none(ColorCode)),
    pcLink: ColorPair(fg: toColorCode("008080"), bg: toColorCode("000000")),

    # pop up window
    popUpWindow: ColorPair(fg: toColorCode("ffffff"), bg: toColorCode("808080")),
    popUpWinCurrentLine: ColorPair(fg: toColorCode("0000ff"), bg: toColorCode("000000")),

    # replace text highlighting
    replaceText: ColorPair(fg: none(ColorCode), bg: toColorCode("ff0000")),
    # pair of paren highlighting
    parenText: ColorPair(fg: none(ColorCode), bg: toColorCode("808080")),
    # highlight other uses current word
    currentWord: ColorPair(fg: none(ColorCode), bg: toColorCode("808080")),
    # highlight full width space
    highlightFullWidthSpace: ColorPair(fg: toColorCode("ff0000"), bg: toColorCode("ff0000")),
    # highlight trailing spaces
    highlightTrailingSpaces: ColorPair(fg: toColorCode("ff0000"), bg: toColorCode("ff0000")),
    # highlight reserved words
    reservedWord: ColorPair(fg: toColorCode("ffffff"), bg: toColorCode("808080")),
    # highlight history manager
    currentHistory: ColorPair(fg: toColorCode("000000"), bg: toColorCode("ff0087")),
    # highlight diff
    addedLine: ColorPair(fg: toColorCode("008000"), bg: none(ColorCode)),
    deletedLine: ColorPair(fg: toColorCode("ff0000"), bg: none(ColorCode)),
    # configuration mode
    currentSetting: ColorPair(fg: toColorCode("000000"), bg: toColorCode("ff0087")),
    # Highlight current line background
    currentLine: ColorPair(fg: none(ColorCode), bg: toColorCode("444444"))
  ),
  vivid: EditorColorPair(
    default: ColorPair(fg: none(ColorCode),  bg: none(ColorCode)),

    # Line number
    lineNum: ColorPair(fg: toColorCode("8a8a8a"), bg: none(ColorCode)),
    currentLineNum: ColorPair(fg: toColorCode("ff0087"), bg: none(ColorCode)),

    # statsu line
    statusLineNormalMode: ColorPair(fg: toColorCode("000000"), bg: toColorCode("ff0087")),
    statusLineModeNormalMode: ColorPair(fg: toColorCode("000000"), bg: toColorCode("ffffff")),
    statusLineNormalModeInactive: ColorPair(fg: toColorCode("ff0087"), bg: toColorCode("ffffff")),

    statusLineInsertMode: ColorPair(fg: toColorCode("000000"), bg:toColorCode("ff0087")),
    statusLineModeInsertMode: ColorPair(fg: toColorCode("000000"), bg: toColorCode("ffffff")),
    statusLineInsertModeInactive: ColorPair(fg: toColorCode("ff0087"), bg: toColorCode("ffffff")),

    statusLineVisualMode: ColorPair(fg: toColorCode("000000"), bg: toColorCode("ff0087")),
    statusLineModeVisualMode: ColorPair(fg: toColorCode("000000"), bg: toColorCode("ffffff")),
    statusLineVisualModeInactive: ColorPair(fg: toColorCode("ff0087"), bg: toColorCode("ffffff")),

    statusLineReplaceMode: ColorPair(fg: toColorCode("000000"), bg: toColorCode("ff0087")),
    statusLineModeReplaceMode: ColorPair(fg: toColorCode("000000"), bg: toColorCode("ffffff")),
    statusLineReplaceModeInactive: ColorPair(fg: toColorCode("ff0087"), bg: toColorCode("ffffff")),

    statusLineFilerMode: ColorPair(fg: toColorCode("000000"), bg: toColorCode("ff0087")),
    statusLineModeFilerMode: ColorPair(fg: toColorCode("000000"), bg: toColorCode("ffffff")),
    statusLineFilerModeInactive: ColorPair(fg: toColorCode("ff0087"), bg: toColorCode("ffffff")),

    statusLineExMode: ColorPair(fg: toColorCode("000000"), bg: toColorCode("ff0087")),
    statusLineModeExMode: ColorPair(fg: toColorCode("000000"), bg: toColorCode("ffffff")),
    statusLineExModeInactive: ColorPair(fg: toColorCode("ff0087"), bg: toColorCode("ffffff")),

    statusLineGitBranch: ColorPair(fg: toColorCode("ffffff"), bg: toColorCode("0000ff")),
    # tab line
    tab: ColorPair(fg: toColorCode("ffffff"), bg: none(ColorCode)),
    currentTab: ColorPair(fg: toColorCode("000000"), bg: toColorCode("ff0087")),
    # command bar
    commandBar: ColorPair(fg: toColorCode("ffffff"), bg: none(ColorCode)),
    # error message
    errorMessage: ColorPair(fg: toColorCode("ff0000"), bg: none(ColorCode)),
    # search result highlighting
    searchResult: ColorPair(fg: none(ColorCode), bg: toColorCode("ff0000")),
    # selected area in visual mode
    visualMode: ColorPair(fg: toColorCode("ffffff"), bg: toColorCode("800080")),

    # color scheme
    defaultChar: ColorPair(fg: toColorCode("ffffff"), bg: none(ColorCode)),
    keyword: ColorPair(fg: toColorCode("ffffff"), bg: none(ColorCode)),
    functionName: ColorPair(fg: toColorCode("ff0087"), bg: none(ColorCode)),
    typeName: ColorPair(fg: toColorCode("ffd700"), bg: none(ColorCode)),
    boolean: ColorPair(fg: toColorCode("008000"), bg: none(ColorCode)),
    stringLit: ColorPair(fg: toColorCode("ffff00"), bg: none(ColorCode)),
    specialVar: ColorPair(fg: toColorCode("008000"), bg: none(ColorCode)),
    builtin: ColorPair(fg: toColorCode("00ffff"), bg: none(ColorCode)),
    decNumber: ColorPair(fg: toColorCode("00ffff"), bg: none(ColorCode)),
    comment: ColorPair(fg: toColorCode("808080"), bg: none(ColorCode)),
    longComment: ColorPair(fg: toColorCode("808080"), bg: none(ColorCode)),
    whitespace: ColorPair(fg: toColorCode("808080"), bg: none(ColorCode)),
    preprocessor: ColorPair(fg: toColorCode("008000"), bg: none(ColorCode)),
    pragma: ColorPair(fg: toColorCode("00ffff"), bg: none(ColorCode)),

    # filer mode
    currentFile: ColorPair(fg: toColorCode("ffffff"), bg: toColorCode("ff0087")),
    file: ColorPair(fg: toColorCode("ffffff"), bg: none(ColorCode)),
    dir: ColorPair(fg: toColorCode("ff0087"), bg: none(ColorCode)),
    pcLink: ColorPair(fg: toColorCode("00ffff"), bg: toColorCode("000000")),
    # pop up window
    popUpWindow: ColorPair(fg: toColorCode("ffffff"), bg: toColorCode("000000")),
    popUpWinCurrentLine: ColorPair(fg: toColorCode("ff0087"), bg: toColorCode("000000")),
    # replace text highlighting
    replaceText: ColorPair(fg: none(ColorCode), bg: toColorCode("ff0000")),
    # pair of paren highlighting
    parenText: ColorPair(fg: none(ColorCode), bg: toColorCode("ff0087")),
    # highlight other uses current word
    currentWord: ColorPair(fg: none(ColorCode), bg: toColorCode("808080")),
    # highlight full width space
    highlightFullWidthSpace: ColorPair(fg: toColorCode("ff0000"), bg: toColorCode("ff0000")),
    # highlight trailing spaces
    highlightTrailingSpaces: ColorPair(fg: toColorCode("ff0000"), bg: toColorCode("ff0000")),
    # highlight reserved words
    reservedWord: ColorPair(fg: toColorCode("ff0087"), bg: toColorCode("000000")),
    # highlight history manager
    currentHistory: ColorPair(fg: toColorCode("ffffff"), bg: toColorCode("ff0087")),
    # highlight diff
    addedLine: ColorPair(fg: toColorCode("008000"), bg: none(ColorCode)),
    deletedLine: ColorPair(fg: toColorCode("ff0000"), bg: none(ColorCode)),
    # configuration mode
    currentSetting: ColorPair(fg: toColorCode("ffffff"), bg: toColorCode("ff0087")),
    # Highlight current line background
    currentLine: ColorPair(fg: none(ColorCode), bg: toColorCode("444444"))
  ),
]

proc setColorPair*(colorPair: var ColorPair, foreground, background: ColorCode) =
  colorPair.fg = some(foreground)
  colorPair.bg = some(background)

# Return text with color escape seqences.
proc withColor*(buf: seq[Rune], colorPair: ColorPair): string =
  if buf.len > 0:
    if colorPair.fg.isSome:
      let str = replace($buf, """\""", """\\""")
      return str.fgColor("#" & $colorPair.fg.get)
    else:
      return replace($buf, """\""", """\\""")

# Return text with color escape seqences.
proc withColor*(buf: string, colorPair: ColorPair): string =
  if buf.len > 0:
    if colorPair.fg.isSome:
      let str = buf.replace("""\""", """\\""")
      return str.fgColor("#" & $colorPair.fg.get)
    else:
      return buf.replace("""\""", """\\""")

#proc setColorPair*(colorPair: EditorColorPair | int,
#                   character, background: ColorCode) {.inline.} =
#
#  init_pair(cshort(ord(colorPair)),
#            cshort(ord(character)),
#            cshort(ord(background))
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
#proc setColorPair*(colorPair: var ColorPair, foreground, background: Color) =
#  colorPair.fg = foreground
#  colorPair.bg = background
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
