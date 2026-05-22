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

## Canonical metadata for every `:set` option.
##
## `SetOptionTable` is the single source of truth consumed by:
## - `command_handlers/command_handler.nim:executeSet` for parser dispatch
## - `help_generator.nim:renderSetOptionsSection` for help text generation
## - `command_completion.nim:SetOptions` for the completion popup
##
## Adding a new `:set xxx` option means appending one entry here. No other
## file needs to be updated.

type
  BoolSettingOption* = enum
    ## Boolean setting options that can be toggled via `:set` command.
    bsoNumber
    bsoRelativeNumber
    bsoCursorLine
    bsoCursorColumn
    bsoStatusLine
    bsoSyntax
    bsoIndentationLines
    bsoAutoIndent
    bsoAutoCloseParen
    bsoAutoDeleteParen
    bsoClipboard
    bsoSmoothScroll
    bsoLiveReloadOfConf
    bsoShowIcons
    bsoHighlightCurrentLine
    bsoHighlightCurrentWord
    bsoHighlightFullWidthSpace
    bsoHighlightPairOfParen
    bsoHighlightFindChar
    bsoHighlightColorCode
    bsoHighlightGitConflict
    bsoHighlightGitConflictTwoColor
    bsoMultipleStatusLine
    bsoIgnoreCase
    bsoSmartCase
    bsoIncSearch
    bsoHlSearch
    bsoBuildOnSave
    bsoShowGitInactive
    bsoLineWrap
    bsoExpandTab
    bsoScrollbar

  IntSettingOption* = enum
    ## Integer setting options that can be set via `:set X=N`.
    isoTabStop
    isoShiftWidth
    isoSoftTabStop
    isoScrollbarWidth

  FloatSettingOption* = enum
    ## Float setting options that can be set via `:set X=N.N`.
    fsoScrollFriction
    fsoScrollAirDrag

  IntBound* = enum
    ## Validation rule for integer-valued options. The variant determines
    ## both the accepted range and the error wording.
    ibPositive ## value > 0, error wording "must be positive"
    ibNonNegative ## value >= 0, error wording "must be non-negative"

  SetOptionKind* = enum
    sokBool
    sokInt
    sokFloat

  SetOptionSpec* = object
    longName*: string
    shortName*: string ## "" if no short alias
    description*: string
      ## Combined "Show/hide …" / "Enable/disable …" wording, used by both
      ## the help text and the completion popup. Bool toggles share this
      ## single string for positive and negative forms.
    case kind*: SetOptionKind
    of sokBool:
      boolOption*: BoolSettingOption
    of sokInt:
      intOption*: IntSettingOption
      intBound*: IntBound
      intExample*: int ## Used in `requires a value (e.g., X=N)` messages
    of sokFloat:
      floatOption*: FloatSettingOption
      floatExample*: float
        ## All current float options use `>= 0` with `must be non-negative`,
        ## so no bound variant is needed. Used in error message example.

const SetOptionTable*: seq[SetOptionSpec] = @[
  SetOptionSpec(
    longName: "number",
    shortName: "nu",
    description: "Show/hide line numbers",
    kind: sokBool,
    boolOption: bsoNumber,
  ),
  SetOptionSpec(
    longName: "relativenumber",
    shortName: "rnu",
    description: "Show/hide relative line numbers",
    kind: sokBool,
    boolOption: bsoRelativeNumber,
  ),
  SetOptionSpec(
    longName: "cursorline",
    shortName: "cul",
    description: "Highlight the current line",
    kind: sokBool,
    boolOption: bsoCursorLine,
  ),
  SetOptionSpec(
    longName: "cursorcolumn",
    shortName: "cuc",
    description: "Highlight the current column",
    kind: sokBool,
    boolOption: bsoCursorColumn,
  ),
  SetOptionSpec(
    longName: "statusline",
    shortName: "stl",
    description: "Show/hide status line",
    kind: sokBool,
    boolOption: bsoStatusLine,
  ),
  SetOptionSpec(
    longName: "syntax",
    shortName: "syn",
    description: "Enable/disable syntax highlighting",
    kind: sokBool,
    boolOption: bsoSyntax,
  ),
  SetOptionSpec(
    longName: "indentationlines",
    shortName: "indl",
    description: "Enable/disable indentation guide lines",
    kind: sokBool,
    boolOption: bsoIndentationLines,
  ),
  SetOptionSpec(
    longName: "autoindent",
    shortName: "ai",
    description: "Enable/disable auto indent",
    kind: sokBool,
    boolOption: bsoAutoIndent,
  ),
  SetOptionSpec(
    longName: "autocloseparen",
    shortName: "acp",
    description: "Enable/disable auto close paren",
    kind: sokBool,
    boolOption: bsoAutoCloseParen,
  ),
  SetOptionSpec(
    longName: "autodeleteparen",
    shortName: "adp",
    description: "Enable/disable auto delete paren",
    kind: sokBool,
    boolOption: bsoAutoDeleteParen,
  ),
  SetOptionSpec(
    longName: "clipboard",
    shortName: "cb",
    description: "Enable/disable system clipboard",
    kind: sokBool,
    boolOption: bsoClipboard,
  ),
  SetOptionSpec(
    longName: "smoothscroll",
    shortName: "sms",
    description: "Enable/disable smooth scroll",
    kind: sokBool,
    boolOption: bsoSmoothScroll,
  ),
  SetOptionSpec(
    longName: "livereload",
    shortName: "lr",
    description: "Enable/disable live reload of config",
    kind: sokBool,
    boolOption: bsoLiveReloadOfConf,
  ),
  SetOptionSpec(
    longName: "icon",
    shortName: "icons",
    description: "Show/hide icons in filer mode",
    kind: sokBool,
    boolOption: bsoShowIcons,
  ),
  SetOptionSpec(
    longName: "highlightcurrentline",
    shortName: "hcl",
    description: "Highlight the current line",
    kind: sokBool,
    boolOption: bsoHighlightCurrentLine,
  ),
  SetOptionSpec(
    longName: "highlightcurrentword",
    shortName: "hcw",
    description: "Highlight other uses of the current word",
    kind: sokBool,
    boolOption: bsoHighlightCurrentWord,
  ),
  SetOptionSpec(
    longName: "highlightfullspace",
    shortName: "hfs",
    description: "Highlight full width space",
    kind: sokBool,
    boolOption: bsoHighlightFullWidthSpace,
  ),
  SetOptionSpec(
    longName: "highlightparen",
    shortName: "hp",
    description: "Highlight matching paren",
    kind: sokBool,
    boolOption: bsoHighlightPairOfParen,
  ),
  SetOptionSpec(
    longName: "highlightfindchar",
    shortName: "hfc",
    description: "Highlight f/F/t/T matches",
    kind: sokBool,
    boolOption: bsoHighlightFindChar,
  ),
  SetOptionSpec(
    longName: "highlightcolorcode",
    shortName: "hcc",
    description: "Highlight inline color codes",
    kind: sokBool,
    boolOption: bsoHighlightColorCode,
  ),
  SetOptionSpec(
    longName: "highlightgitconflict",
    shortName: "hgc",
    description: "Highlight git merge conflict blocks",
    kind: sokBool,
    boolOption: bsoHighlightGitConflict,
  ),
  SetOptionSpec(
    longName: "highlightgitconflicttwocolor",
    shortName: "hgctc",
    description: "Use two-color (ours/theirs) conflict scheme",
    kind: sokBool,
    boolOption: bsoHighlightGitConflictTwoColor,
  ),
  SetOptionSpec(
    longName: "multistatusline",
    shortName: "msl",
    description: "Enable/disable multiple status line",
    kind: sokBool,
    boolOption: bsoMultipleStatusLine,
  ),
  SetOptionSpec(
    longName: "ignorecase",
    shortName: "ic",
    description: "Enable/disable ignorecase",
    kind: sokBool,
    boolOption: bsoIgnoreCase,
  ),
  SetOptionSpec(
    longName: "smartcase",
    shortName: "scs",
    description: "Enable/disable smartcase",
    kind: sokBool,
    boolOption: bsoSmartCase,
  ),
  SetOptionSpec(
    longName: "incsearch",
    shortName: "is",
    description: "Enable/disable incremental search",
    kind: sokBool,
    boolOption: bsoIncSearch,
  ),
  SetOptionSpec(
    longName: "hlsearch",
    shortName: "hls",
    description: "Enable/disable search highlighting",
    kind: sokBool,
    boolOption: bsoHlSearch,
  ),
  SetOptionSpec(
    longName: "buildonsave",
    shortName: "bos",
    description: "Enable/disable build on save",
    kind: sokBool,
    boolOption: bsoBuildOnSave,
  ),
  SetOptionSpec(
    longName: "showgitinactive",
    shortName: "sgi",
    description: "Show/hide git branch in inactive window",
    kind: sokBool,
    boolOption: bsoShowGitInactive,
  ),
  SetOptionSpec(
    longName: "wrap",
    shortName: "",
    description: "Enable/disable line wrap",
    kind: sokBool,
    boolOption: bsoLineWrap,
  ),
  SetOptionSpec(
    longName: "expandtab",
    shortName: "et",
    description: "Enable/disable expand tab to spaces",
    kind: sokBool,
    boolOption: bsoExpandTab,
  ),
  SetOptionSpec(
    longName: "scrollbar",
    shortName: "",
    description: "Enable/disable scrollbar",
    kind: sokBool,
    boolOption: bsoScrollbar,
  ),
  SetOptionSpec(
    longName: "scrollbarwidth",
    shortName: "",
    description: "Change scrollbar width",
    kind: sokInt,
    intOption: isoScrollbarWidth,
    intBound: ibNonNegative,
    intExample: 1,
  ),
  SetOptionSpec(
    longName: "tabstop",
    shortName: "ts",
    description: "Change tab stop width",
    kind: sokInt,
    intOption: isoTabStop,
    intBound: ibPositive,
    intExample: 4,
  ),
  SetOptionSpec(
    longName: "shiftwidth",
    shortName: "sw",
    description: "Change indent width",
    kind: sokInt,
    intOption: isoShiftWidth,
    intBound: ibNonNegative,
    intExample: 4,
  ),
  SetOptionSpec(
    longName: "softtabstop",
    shortName: "sts",
    description: "Change soft tab stop width",
    kind: sokInt,
    intOption: isoSoftTabStop,
    intBound: ibNonNegative,
    intExample: 4,
  ),
  SetOptionSpec(
    longName: "scrollfriction",
    shortName: "sfr",
    description: "Change smooth scroll friction",
    kind: sokFloat,
    floatOption: fsoScrollFriction,
    floatExample: 80.0,
  ),
  SetOptionSpec(
    longName: "scrollairdrag",
    shortName: "sad",
    description: "Change smooth scroll air drag",
    kind: sokFloat,
    floatOption: fsoScrollAirDrag,
    floatExample: 2.0,
  ),
]

proc intBoundError*(bound: IntBound): string =
  ## The error suffix paired with `IntBound` (e.g., `"must be positive"`).
  case bound
  of ibPositive: "must be positive"
  of ibNonNegative: "must be non-negative"

proc intBoundOk*(bound: IntBound, value: int): bool =
  ## Whether `value` satisfies the bound's constraint.
  case bound
  of ibPositive:
    value > 0
  of ibNonNegative:
    value >= 0
