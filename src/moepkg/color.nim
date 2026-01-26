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

## Color system for moe editor
##
## This module provides RGB color handling, theme color definitions,
## and conversion utilities for the editor's color scheme.

import std/[strutils, strformat, options, os]

import pkg/[results, celina]

type ColorModeKind* = enum
  ## Color mode for terminal output
  cmk8color ## 8 basic ANSI colors (0-7)
  cmk16color ## 16 ANSI colors (0-15, includes bright)
  cmk256color ## 256-color palette
  cmk24bit ## True color (24-bit RGB)
  cmkNone ## No colors (terminal defaults only)

var globalColorMode* = cmk24bit ## Current color mode setting

proc rgbTo8Color*(r, g, b: int16): uint8 =
  ## Convert RGB to 8-color ANSI index (0-7).
  ## Uses threshold-based mapping to basic colors.
  ##
  ## ANSI 8 colors: black(0), red(1), green(2), yellow(3),
  ##                blue(4), magenta(5), cyan(6), white(7)

  # Threshold for considering a channel "on"
  const threshold = 128'i16

  # Map RGB channels to 3-bit color index
  let
    rBit = if r >= threshold: 1'u8 else: 0'u8
    gBit = if g >= threshold: 2'u8 else: 0'u8
    bBit = if b >= threshold: 4'u8 else: 0'u8

  result = rBit or gBit or bBit

proc rgbTo16Color*(r, g, b: int16): uint8 =
  ## Convert RGB to 16-color ANSI index (0-15).
  ## Colors 0-7 are normal, 8-15 are bright variants.
  ##
  ## ANSI 16 colors:
  ##   0: black,   1: red,     2: green,   3: yellow
  ##   4: blue,    5: magenta, 6: cyan,    7: white
  ##   8: bright black (gray), 9-15: bright variants

  # Calculate luminance (perceived brightness, 0-255 range)
  # Use int to avoid overflow: 255 * 587 = 149,685 exceeds int16 max
  let luminance = (r.int * 299 + g.int * 587 + b.int * 114) div 1000

  # Check for grayscale (R ≈ G ≈ B)
  let
    maxCh = max(max(r, g), b)
    minCh = min(min(r, g), b)
    isGrayscale = (maxCh - minCh) < 32

  if isGrayscale:
    # Map grayscale to 4 levels: black, dark gray, light gray, white
    if luminance < 64:
      return 0'u8 # Black
    elif luminance < 128:
      return 8'u8 # Bright black (dark gray)
    elif luminance < 192:
      return 7'u8 # White (actually light gray in most terminals)
    else:
      return 15'u8 # Bright white

  # For chromatic colors, use lower threshold to catch dark colors
  const threshold = 85'i16
  let
    rBit = if r >= threshold: 1'u8 else: 0'u8
    gBit = if g >= threshold: 2'u8 else: 0'u8
    bBit = if b >= threshold: 4'u8 else: 0'u8
    baseColor = rBit or gBit or bBit

  # Use bright variant if any channel is high
  if maxCh >= 192:
    result = baseColor + 8
  else:
    result = baseColor

type
  ## RGB color with values 0-255. -1 indicates terminal default color.
  Rgb* = object
    red*, green*, blue*: int16

  RgbPair* = object
    foreground*, background*: Rgb

  ## All editor color pair indices for UI elements and syntax highlighting
  EditorColorPairIndex* = enum
    # Basic
    default
    lineNum
    currentLineNum

    # Status line - Normal mode
    statusLineNormalMode
    statusLineNormalModeLabel
    statusLineNormalModeInactive

    # Status line - Insert mode
    statusLineInsertMode
    statusLineInsertModeLabel
    statusLineInsertModeInactive

    # Status line - Visual mode
    statusLineVisualMode
    statusLineVisualModeLabel
    statusLineVisualModeInactive

    # Status line - Replace mode
    statusLineReplaceMode
    statusLineReplaceModeLabel
    statusLineReplaceModeInactive

    # Status line - Filer mode
    statusLineFilerMode
    statusLineFilerModeLabel
    statusLineFilerModeInactive

    # Status line - Ex mode
    statusLineExMode
    statusLineExModeLabel
    statusLineExModeInactive

    # Status line - Git info
    statusLineGitChangedLines
    statusLineGitBranch

    # Tab line
    tab
    currentTab

    # Command line
    commandLine

    # Messages
    errorMessage
    warnMessage

    # Search result
    searchResult

    # Visual mode selection
    selectArea

    # Syntax highlighting - Core
    keyword
    functionName
    typeName
    boolean
    specialVar
    builtin
    charLit
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
    identifier
    table
    date
    operator
    property

    # Syntax highlighting - Extended (LSP semantic tokens)
    namespace
    className
    enumName
    enumMember
    interfaceName
    typeParameter
    parameter
    variable
    lspString
    event
    function
    `method`
    `macro`
    regexp
    decorator
    angle
    arithmetic
    attribute
    attributeBracket
    bitwise
    brace
    bracket
    builtinAttribute
    builtinType
    colon
    comma
    comparison
    constParameter
    derive
    deriveHelper
    dot
    escapeSequence
    invalidEscapeSequence
    formatSpecifier
    generic
    label
    lifetime
    logical
    macroBang
    parenthesis
    punctuation
    selfKeyword
    selfTypeKeyword
    semicolon
    typeAlias
    toolModule
    union
    unresolvedReference

    # LSP features
    inlayHint
    inlineValue
    codeLens

    # Filer mode
    currentFile
    file
    dir
    pcLink

    # Popup window
    popupWindow
    popupWinCurrentLine

    # Highlighting
    replaceText
    parenPair
    currentWord
    highlightFullWidthSpace
    highlightTrailingSpaces
    reservedWord

    # Syntax checker
    syntaxCheckInfo
    syntaxCheckHint
    syntaxCheckWarn
    syntaxCheckErr

    # Git
    gitConflict

    # Backup manager
    backupManagerCurrentLine

    # Diff viewer
    diffViewerAddedLine
    diffViewerDeletedLine

    # Configuration mode
    configModeCurrentLine

    # Current line background
    currentLineBg
    foldingLine

    # Side bar
    sidebarGitAddedSign
    sidebarGitDeletedSign
    sidebarGitChangedSign
    sidebarSyntaxCheckInfoSign
    sidebarSyntaxCheckHintSign
    sidebarSyntaxCheckWarnSign
    sidebarSyntaxCheckErrSign

    # Viewer common colors
    viewerHeader
    viewerSelectedLine
    viewerEmptyMessage

    # Filer mode specific
    filerDirectory
    filerSymlink
    filerSymlinkDir
    filerHiddenFile

    # Buffer manager specific
    bufferManagerActive
    bufferManagerModified

    # Configuration mode specific
    configModeSection
    configModeBoolTrue
    configModeBoolFalse
    configModeEnum
    configModeInt
    configModeEditMode
    configModePopupBg
    configModePopupSelected

    # Diff viewer specific
    diffViewerHeader
    diffViewerMeta

    # Other viewers
    recentFileMissing
    debugViewerSectionHeader
    referencesViewerHeader
    documentSymbolViewerHeader
    callHierarchyViewerHeader
    helpViewerSectionHeader

  ## A single color with RGB value
  ThemeColor* = object
    rgb*: Rgb

  ## A foreground/background color pair
  ColorPair* = object
    foreground*: ThemeColor
    background*: ThemeColor

  ## All theme colors indexed by EditorColorPairIndex
  ThemeColors* = array[EditorColorPairIndex, ColorPair]

const
  ## Terminal default RGB (-1 indicates use terminal default)
  TerminalDefaultRgb* = Rgb(red: -1, green: -1, blue: -1)

  ## Default terminal colors
  DefaultForegroundColor* = ThemeColor(rgb: TerminalDefaultRgb)
  DefaultBackgroundColor* = ThemeColor(rgb: TerminalDefaultRgb)

proc isTermDefaultColor*(rgb: Rgb): bool {.inline.} =
  ## Check if this RGB represents the terminal default color
  rgb == TerminalDefaultRgb

proc hexToRgb*(s: string): Result[Rgb, string] =
  ## Parse a hex color string to RGB.
  ## Examples: "#000000", "ff0000"

  if not (s.len == 6 or (s.len == 7 and s.startsWith('#'))):
    return Result[Rgb, string].err "Invalid hex color"

  let hexStr =
    if s.startsWith('#'):
      s[1 .. 6]
    else:
      s

  var rgb: Rgb
  try:
    rgb = Rgb(
      red: fromHex[int16](hexStr[0 .. 1]),
      green: fromHex[int16](hexStr[2 .. 3]),
      blue: fromHex[int16](hexStr[4 .. 5]),
    )
  except CatchableError as e:
    return Result[Rgb, string].err fmt"Failed to parse hex color: {e.msg}"

  return Result[Rgb, string].ok rgb

proc parseThemeColor*(s: string): Result[Rgb, string] =
  ## Parse a color string for theme files.
  ## Supports:
  ##   - "termDefault" for terminal default color
  ##   - "#RRGGBB" or "RRGGBB" hex color format
  ##
  ## Examples:
  ##   parseThemeColor("termDefault") -> TerminalDefaultRgb
  ##   parseThemeColor("#ff0000") -> Rgb(red: 255, green: 0, blue: 0)

  if s == "termDefault":
    return Result[Rgb, string].ok TerminalDefaultRgb

  return hexToRgb(s)

proc toHex*(rgb: Rgb, withPrefix: bool = true): Option[string] =
  ## Convert RGB to hex color string.
  ## Returns None for terminal default color.

  if rgb.isTermDefaultColor:
    return none(string)

  let
    r = rgb.red.uint64.toHex(2).toLowerAscii
    g = rgb.green.uint64.toHex(2).toLowerAscii
    b = rgb.blue.uint64.toHex(2).toLowerAscii

  if withPrefix:
    return some(fmt"#{r}{g}{b}")
  else:
    return some(fmt"{r}{g}{b}")

proc isHexColor*(s: string, withPrefix: bool = true): bool =
  ## Check if string is a valid hex color code.

  if (not withPrefix and s.len == 6) or (s.startsWith('#') and s.len == 7):
    let hexStr =
      if s.startsWith('#'):
        s[1 .. 6]
      else:
        s[0 .. 5]

    var r, g, b: int
    try:
      r = fromHex[int](hexStr[0 .. 1])
      g = fromHex[int](hexStr[2 .. 3])
      b = fromHex[int](hexStr[4 .. 5])
    except ValueError:
      return false

    return (r >= 0 and r <= 255) and (g >= 0 and g <= 255) and (b >= 0 and b <= 255)

  return false

proc rgb*(hex: string): Rgb =
  ## Helper to create RGB from hex string. Panics on invalid input.
  hexToRgb(hex).get

proc inverseColor*(color: Rgb): Rgb =
  ## Return the inverse (complementary) color.

  if color.isTermDefaultColor:
    return color

  result.red = abs(color.red - 255)
  result.green = abs(color.green - 255)
  result.blue = abs(color.blue - 255)

proc rgbTo256Color(r, g, b: int16): uint8 =
  ## Convert RGB values to nearest 256-color palette index.
  ## Uses the 6x6x6 color cube (indices 16-231) and grayscale ramp (232-255).

  # Check if it's a grayscale color
  if r == g and g == b:
    if r < 8:
      return 16 # Black
    elif r > 248:
      return 231 # White
    else:
      # Use grayscale ramp (232-255, 24 levels)
      return uint8(((r - 8) * 24) div 240 + 232)

  # Convert to 6x6x6 color cube (indices 16-231)
  # Each component maps to 0-5
  let
    ri = uint8((r * 6) div 256)
    gi = uint8((g * 6) div 256)
    bi = uint8((b * 6) div 256)

  return uint8(16 + 36 * ri + 6 * gi + bi)

proc toColorValue*(rgb: Rgb): ColorValue =
  ## Convert Rgb to celina ColorValue, respecting globalColorMode.

  if rgb.isTermDefaultColor:
    return ColorValue(kind: Default)

  case globalColorMode
  of cmkNone:
    # No colors - use terminal default
    return ColorValue(kind: Default)
  of cmk8color:
    # Convert to 8 basic ANSI colors
    let index = rgbTo8Color(rgb.red, rgb.green, rgb.blue)
    return ColorValue(kind: Indexed256, indexed256: index)
  of cmk16color:
    # Convert to 16 ANSI colors (includes bright variants)
    let index = rgbTo16Color(rgb.red, rgb.green, rgb.blue)
    return ColorValue(kind: Indexed256, indexed256: index)
  of cmk256color:
    # Convert to 256-color palette
    let index = rgbTo256Color(rgb.red, rgb.green, rgb.blue)
    return ColorValue(kind: Indexed256, indexed256: index)
  of cmk24bit:
    # True color RGB
    return ColorValue(
      kind: ColorKind.Rgb,
      rgb: RgbColor(r: rgb.red.uint8, g: rgb.green.uint8, b: rgb.blue.uint8),
    )

proc toStyle*(colorPair: ColorPair): Style =
  ## Convert ColorPair to celina Style.

  result = Style(
    fg: colorPair.foreground.rgb.toColorValue,
    bg: colorPair.background.rgb.toColorValue,
    modifiers: {},
  )

proc toStyle*(colorPair: ColorPair, modifiers: set[StyleModifier]): Style =
  ## Convert ColorPair to celina Style with modifiers.

  result = Style(
    fg: colorPair.foreground.rgb.toColorValue,
    bg: colorPair.background.rgb.toColorValue,
    modifiers: modifiers,
  )

# Global theme colors (will be initialized from theme.nim)
var themeColors*: ThemeColors

proc getThemeColor*(index: EditorColorPairIndex): ColorPair {.inline.} =
  ## Get color pair from current theme.
  themeColors[index]

proc getThemeStyle*(index: EditorColorPairIndex): Style {.inline.} =
  ## Get celina Style from current theme.
  themeColors[index].toStyle

proc getThemeStyle*(
    index: EditorColorPairIndex, modifiers: set[StyleModifier]
): Style {.inline.} =
  ## Get celina Style from current theme with modifiers.
  themeColors[index].toStyle(modifiers)

proc setThemeColors*(colors: ThemeColors) =
  ## Set the current theme colors.
  themeColors = colors

var cachedTerminalCapability: Option[ColorModeKind] = none(ColorModeKind)

proc detectTerminalColorCapability*(): ColorModeKind =
  ## Detect terminal color capability from environment variables.
  ## Result is cached after first call.
  ##
  ## Detection order:
  ## 1. COLORTERM=truecolor or 24bit → 24bit
  ## 2. TERM ends with "-256color" or contains "256color" → 256 colors
  ## 3. TERM is a known color terminal → 16 colors
  ## 4. TERM contains "-color" suffix → 16 colors
  ## 5. Otherwise → 8 colors

  if cachedTerminalCapability.isSome:
    return cachedTerminalCapability.get

  let colorterm = getEnv("COLORTERM").toLowerAscii
  if colorterm in ["truecolor", "24bit"]:
    cachedTerminalCapability = some(cmk24bit)
    return cmk24bit

  let term = getEnv("TERM").toLowerAscii

  # Check for 256 color support
  if term.endsWith("-256color") or "256color" in term:
    cachedTerminalCapability = some(cmk256color)
    return cmk256color

  # Known 16-color capable terminals
  const knownColorTerminals = [
    "xterm",
    "xterm-color",
    "screen",
    "screen-color",
    "tmux",
    "tmux-color",
    "rxvt",
    "rxvt-unicode",
    "linux", # Linux console
    "cygwin",
    "ansi",
  ]

  for known in knownColorTerminals:
    if term == known or term.startsWith(known & "-"):
      cachedTerminalCapability = some(cmk16color)
      return cmk16color

  # Check for generic color suffix (e.g., "foo-color")
  if term.endsWith("-color"):
    cachedTerminalCapability = some(cmk16color)
    return cmk16color

  # Fallback to 8 colors for unknown terminals
  cachedTerminalCapability = some(cmk8color)
  return cmk8color

proc colorModeRank(mode: ColorModeKind): int {.inline.} =
  ## Return rank of color mode (higher = more colors)
  case mode
  of cmk8color: 0
  of cmk16color: 1
  of cmk256color: 2
  of cmk24bit: 3
  of cmkNone: -1
    # Special case

proc applyColorModeFallback*(requested: ColorModeKind): ColorModeKind =
  ## Apply fallback if the requested color mode exceeds terminal capability.
  ## Returns the requested mode if supported, otherwise falls back to
  ## the highest supported mode.

  if requested == cmkNone:
    return cmkNone

  let capability = detectTerminalColorCapability()

  if colorModeRank(requested) <= colorModeRank(capability):
    return requested
  else:
    return capability
