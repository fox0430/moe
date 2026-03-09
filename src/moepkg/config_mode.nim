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

## Configuration mode module
## Provides a UI for viewing and editing configuration settings
##
## Design: Table-driven approach to avoid duplication between building
## the item list and applying changes.

import std/[options, strutils]

import config

type
  ConfigValueKind* = enum
    ## Types of configuration values
    cvkBool # true/false
    cvkInt # integer
    cvkFloat # floating point
    cvkString # string
    cvkEnum # enumerated value
    cvkSection # section header (not editable)

  ## Getter/Setter closures for config values
  BoolGetter = proc(cfg: EditorConfig): bool {.noSideEffect.}
  BoolSetter = proc(cfg: EditorConfig, val: bool)
  IntGetter = proc(cfg: EditorConfig): int {.noSideEffect.}
  IntSetter = proc(cfg: EditorConfig, val: int)
  FloatGetter = proc(cfg: EditorConfig): float {.noSideEffect.}
  FloatSetter = proc(cfg: EditorConfig, val: float)
  EnumGetter = proc(cfg: EditorConfig): string {.noSideEffect.}
  EnumSetter = proc(cfg: EditorConfig, val: string)
  StringGetter = proc(cfg: EditorConfig): string {.noSideEffect.}
  StringSetter = proc(cfg: EditorConfig, val: string)

  ## Config item descriptor - defines how to read/write a config value
  ConfigItemDescriptor = object
    displayName: string
    section: string
    visibleWhen: proc(cfg: EditorConfig): bool {.noSideEffect.}
    case kind: ConfigValueKind
    of cvkBool:
      boolGet: BoolGetter
      boolSet: BoolSetter
    of cvkInt:
      intGet: IntGetter
      intSet: IntSetter
      intMin, intMax: int
    of cvkFloat:
      floatGet: FloatGetter
      floatSet: FloatSetter
      floatMin, floatMax: float
      floatStep: float # Increment/decrement step
    of cvkEnum:
      enumGet: EnumGetter
      enumSet: EnumSetter
      enumOptions: seq[string]
    of cvkString:
      stringGet: StringGetter
      stringSetter: StringSetter
    of cvkSection:
      discard

  ConfigItem* = object ## Represents a single configuration item in the list
    displayName*: string
    section*: string
    depth*: int # Indentation depth (0 for section, 1 for item)
    descriptorIndex*: int # Index into descriptor table (-1 for sections)
    case kind*: ConfigValueKind
    of cvkBool:
      boolValue*: bool
    of cvkInt:
      intValue*: int
      intMin*: int
      intMax*: int
    of cvkFloat:
      floatValue*: float
      floatMin*: float
      floatMax*: float
      floatStep*: float
    of cvkString:
      stringValue*: string
    of cvkEnum:
      enumValue*: string
      enumOptions*: seq[string]
    of cvkSection:
      discard

  ConfigModeState* = ref object ## State for the configuration mode UI
    items*: seq[ConfigItem] # All configuration items
    selectedIndex*: int # Index in items
    topLine*: int # Scroll position
    editMode*: bool # Whether we're editing a value (Int/String)
    editBuffer*: string # Buffer for editing text
    editCursor*: int # Cursor position in edit buffer
    enumPopupOpen*: bool # Whether enum selection popup is open
    enumPopupIndex*: int # Selected index in enum popup
    config*: EditorConfig # Reference to the config being edited

# Config Item Descriptors - Single source of truth for config items

proc makeDescriptors(): seq[ConfigItemDescriptor] =
  ## Build the descriptor table. Each descriptor knows how to read/write
  ## a specific config field.
  result = @[]

  # Standard section
  result.add ConfigItemDescriptor(
    kind: cvkSection, displayName: "Standard", section: "Standard"
  )
  result.add ConfigItemDescriptor(
    kind: cvkBool,
    displayName: "number",
    section: "Standard",
    boolGet: proc(c: EditorConfig): bool =
      c.standard.number,
    boolSet: proc(c: EditorConfig, v: bool) =
      c.standard.number = v,
  )
  result.add ConfigItemDescriptor(
    kind: cvkBool,
    displayName: "relativeNumber",
    section: "Standard",
    boolGet: proc(c: EditorConfig): bool =
      c.standard.relativeNumber,
    boolSet: proc(c: EditorConfig, v: bool) =
      c.standard.relativeNumber = v,
  )
  result.add ConfigItemDescriptor(
    kind: cvkBool,
    displayName: "currentLine",
    section: "Highlight",
    boolGet: proc(c: EditorConfig): bool =
      c.highlight.currentLine,
    boolSet: proc(c: EditorConfig, v: bool) =
      c.highlight.currentLine = v,
  )
  result.add ConfigItemDescriptor(
    kind: cvkBool,
    displayName: "currentColumn",
    section: "Highlight",
    boolGet: proc(c: EditorConfig): bool =
      c.highlight.currentColumn,
    boolSet: proc(c: EditorConfig, v: bool) =
      c.highlight.currentColumn = v,
  )
  result.add ConfigItemDescriptor(
    kind: cvkBool,
    displayName: "statusLine",
    section: "Standard",
    boolGet: proc(c: EditorConfig): bool =
      c.standard.statusLine,
    boolSet: proc(c: EditorConfig, v: bool) =
      c.standard.statusLine = v,
  )
  result.add ConfigItemDescriptor(
    kind: cvkBool,
    displayName: "syntax",
    section: "Standard",
    boolGet: proc(c: EditorConfig): bool =
      c.standard.syntax,
    boolSet: proc(c: EditorConfig, v: bool) =
      c.standard.syntax = v,
  )
  result.add ConfigItemDescriptor(
    kind: cvkBool,
    displayName: "indentationLines",
    section: "Standard",
    boolGet: proc(c: EditorConfig): bool =
      c.standard.indentationLines,
    boolSet: proc(c: EditorConfig, v: bool) =
      c.standard.indentationLines = v,
  )
  result.add ConfigItemDescriptor(
    kind: cvkInt,
    displayName: "tabStop",
    section: "Standard",
    intGet: proc(c: EditorConfig): int =
      c.standard.tabStop,
    intSet: proc(c: EditorConfig, v: int) =
      c.standard.tabStop = v,
    intMin: 1,
    intMax: 16,
  )
  result.add ConfigItemDescriptor(
    kind: cvkInt,
    displayName: "shiftWidth",
    section: "Standard",
    intGet: proc(c: EditorConfig): int =
      c.standard.shiftWidth,
    intSet: proc(c: EditorConfig, v: int) =
      c.standard.shiftWidth = v,
    intMin: 0,
    intMax: 16,
  )
  result.add ConfigItemDescriptor(
    kind: cvkInt,
    displayName: "softTabStop",
    section: "Standard",
    intGet: proc(c: EditorConfig): int =
      c.standard.softTabStop,
    intSet: proc(c: EditorConfig, v: int) =
      c.standard.softTabStop = v,
    intMin: 0,
    intMax: 16,
  )
  result.add ConfigItemDescriptor(
    kind: cvkBool,
    displayName: "expandTab",
    section: "Standard",
    boolGet: proc(c: EditorConfig): bool =
      c.standard.expandTab,
    boolSet: proc(c: EditorConfig, v: bool) =
      c.standard.expandTab = v,
  )
  result.add ConfigItemDescriptor(
    kind: cvkBool,
    displayName: "sidebar",
    section: "Standard",
    boolGet: proc(c: EditorConfig): bool =
      c.standard.sidebar,
    boolSet: proc(c: EditorConfig, v: bool) =
      c.standard.sidebar = v,
  )
  result.add ConfigItemDescriptor(
    kind: cvkBool,
    displayName: "showModifiedLines",
    section: "Standard",
    boolGet: proc(c: EditorConfig): bool =
      c.standard.showModifiedLines,
    boolSet: proc(c: EditorConfig, v: bool) =
      c.standard.showModifiedLines = v,
  )
  result.add ConfigItemDescriptor(
    kind: cvkBool,
    displayName: "autoCloseParen",
    section: "Standard",
    boolGet: proc(c: EditorConfig): bool =
      c.standard.autoCloseParen,
    boolSet: proc(c: EditorConfig, v: bool) =
      c.standard.autoCloseParen = v,
  )
  result.add ConfigItemDescriptor(
    kind: cvkBool,
    displayName: "autoIndent",
    section: "Standard",
    boolGet: proc(c: EditorConfig): bool =
      c.standard.autoIndent,
    boolSet: proc(c: EditorConfig, v: bool) =
      c.standard.autoIndent = v,
  )
  result.add ConfigItemDescriptor(
    kind: cvkBool,
    displayName: "ignorecase",
    section: "Standard",
    boolGet: proc(c: EditorConfig): bool =
      c.standard.ignorecase,
    boolSet: proc(c: EditorConfig, v: bool) =
      c.standard.ignorecase = v,
  )
  result.add ConfigItemDescriptor(
    kind: cvkBool,
    displayName: "smartcase",
    section: "Standard",
    boolGet: proc(c: EditorConfig): bool =
      c.standard.smartcase,
    boolSet: proc(c: EditorConfig, v: bool) =
      c.standard.smartcase = v,
  )
  result.add ConfigItemDescriptor(
    kind: cvkBool,
    displayName: "disableChangeCursor",
    section: "Standard",
    boolGet: proc(c: EditorConfig): bool =
      c.standard.disableChangeCursor,
    boolSet: proc(c: EditorConfig, v: bool) =
      c.standard.disableChangeCursor = v,
  )
  result.add ConfigItemDescriptor(
    kind: cvkEnum,
    displayName: "defaultCursor",
    section: "Standard",
    enumGet: proc(c: EditorConfig): string =
      $c.standard.defaultCursor,
    enumSet: proc(c: EditorConfig, v: string) =
      c.standard.defaultCursor = parseEnum[CursorType](v),
    enumOptions:
      @["terminalDefault", "blinkBlock", "blinkIbeam", "nonBlinkBlock", "nonBlinkIbeam"],
  )
  result.add ConfigItemDescriptor(
    kind: cvkEnum,
    displayName: "normalModeCursor",
    section: "Standard",
    enumGet: proc(c: EditorConfig): string =
      $c.standard.normalModeCursor,
    enumSet: proc(c: EditorConfig, v: string) =
      c.standard.normalModeCursor = parseEnum[CursorType](v),
    enumOptions:
      @["terminalDefault", "blinkBlock", "blinkIbeam", "nonBlinkBlock", "nonBlinkIbeam"],
  )
  result.add ConfigItemDescriptor(
    kind: cvkEnum,
    displayName: "insertModeCursor",
    section: "Standard",
    enumGet: proc(c: EditorConfig): string =
      $c.standard.insertModeCursor,
    enumSet: proc(c: EditorConfig, v: string) =
      c.standard.insertModeCursor = parseEnum[CursorType](v),
    enumOptions:
      @["terminalDefault", "blinkBlock", "blinkIbeam", "nonBlinkBlock", "nonBlinkIbeam"],
  )
  result.add ConfigItemDescriptor(
    kind: cvkBool,
    displayName: "liveReloadOfConf",
    section: "Standard",
    boolGet: proc(c: EditorConfig): bool =
      c.standard.liveReloadOfConf,
    boolSet: proc(c: EditorConfig, v: bool) =
      c.standard.liveReloadOfConf = v,
  )
  result.add ConfigItemDescriptor(
    kind: cvkBool,
    displayName: "incrementalSearch",
    section: "Standard",
    boolGet: proc(c: EditorConfig): bool =
      c.standard.incrementalSearch,
    boolSet: proc(c: EditorConfig, v: bool) =
      c.standard.incrementalSearch = v,
  )
  result.add ConfigItemDescriptor(
    kind: cvkBool,
    displayName: "popupWindowInExmode",
    section: "Standard",
    boolGet: proc(c: EditorConfig): bool =
      c.standard.popupWindowInExmode,
    boolSet: proc(c: EditorConfig, v: bool) =
      c.standard.popupWindowInExmode = v,
  )
  result.add ConfigItemDescriptor(
    kind: cvkBool,
    displayName: "autoDeleteParen",
    section: "Standard",
    boolGet: proc(c: EditorConfig): bool =
      c.standard.autoDeleteParen,
    boolSet: proc(c: EditorConfig, v: bool) =
      c.standard.autoDeleteParen = v,
  )
  result.add ConfigItemDescriptor(
    kind: cvkBool,
    displayName: "liveReloadOfFile",
    section: "Standard",
    boolGet: proc(c: EditorConfig): bool =
      c.standard.liveReloadOfFile,
    boolSet: proc(c: EditorConfig, v: bool) =
      c.standard.liveReloadOfFile = v,
  )
  result.add ConfigItemDescriptor(
    kind: cvkEnum,
    displayName: "colorMode",
    section: "Standard",
    enumGet: proc(c: EditorConfig): string =
      $c.standard.colorMode,
    enumSet: proc(c: EditorConfig, v: string) =
      c.standard.colorMode = parseEnum[ColorMode](v),
    enumOptions: @["8", "16", "256", "24bit", "none"],
  )
  result.add ConfigItemDescriptor(
    kind: cvkBool,
    displayName: "mouse",
    section: "Standard",
    boolGet: proc(c: EditorConfig): bool =
      c.standard.mouse,
    boolSet: proc(c: EditorConfig, v: bool) =
      c.standard.mouse = v,
  )
  result.add ConfigItemDescriptor(
    kind: cvkBool,
    displayName: "lineWrap",
    section: "Standard",
    boolGet: proc(c: EditorConfig): bool =
      c.standard.lineWrap,
    boolSet: proc(c: EditorConfig, v: bool) =
      c.standard.lineWrap = v,
  )
  result.add ConfigItemDescriptor(
    kind: cvkInt,
    displayName: "timeoutlen",
    section: "Standard",
    intGet: proc(c: EditorConfig): int =
      c.standard.timeoutlen,
    intSet: proc(c: EditorConfig, v: int) =
      c.standard.timeoutlen = v,
    intMin: 0,
    intMax: 10000,
  )
  result.add ConfigItemDescriptor(
    kind: cvkEnum,
    displayName: "bufferBackend",
    section: "Standard",
    enumGet: proc(c: EditorConfig): string =
      $c.standard.bufferBackend,
    enumSet: proc(c: EditorConfig, v: string) =
      c.standard.bufferBackend = parseEnum[BufferBackendConfig](v),
    enumOptions: @["auto", "gapBuffer", "sqrtDecomp", "rope", "pieceTable"],
  )

  # Clipboard section
  result.add ConfigItemDescriptor(
    kind: cvkSection, displayName: "Clipboard", section: "Clipboard"
  )
  result.add ConfigItemDescriptor(
    kind: cvkBool,
    displayName: "enable",
    section: "Clipboard",
    boolGet: proc(c: EditorConfig): bool =
      c.clipboard.enable,
    boolSet: proc(c: EditorConfig, v: bool) =
      c.clipboard.enable = v,
  )
  result.add ConfigItemDescriptor(
    kind: cvkEnum,
    displayName: "tool",
    section: "Clipboard",
    enumGet: proc(c: EditorConfig): string =
      $c.clipboard.tool,
    enumSet: proc(c: EditorConfig, v: string) =
      c.clipboard.tool = parseEnum[ClipboardTool](v),
    enumOptions: @["xsel", "xclip", "wl-clipboard", "win32yank", "pbcopy"],
  )

  # StatusLine section
  result.add ConfigItemDescriptor(
    kind: cvkSection, displayName: "StatusLine", section: "StatusLine"
  )
  result.add ConfigItemDescriptor(
    kind: cvkBool,
    displayName: "multipleStatusLine",
    section: "StatusLine",
    boolGet: proc(c: EditorConfig): bool =
      c.statusLine.multipleStatusLine,
    boolSet: proc(c: EditorConfig, v: bool) =
      c.statusLine.multipleStatusLine = v,
  )
  result.add ConfigItemDescriptor(
    kind: cvkBool,
    displayName: "merge",
    section: "StatusLine",
    boolGet: proc(c: EditorConfig): bool =
      c.statusLine.merge,
    boolSet: proc(c: EditorConfig, v: bool) =
      c.statusLine.merge = v,
  )
  result.add ConfigItemDescriptor(
    kind: cvkBool,
    displayName: "mode",
    section: "StatusLine",
    boolGet: proc(c: EditorConfig): bool =
      c.statusLine.mode,
    boolSet: proc(c: EditorConfig, v: bool) =
      c.statusLine.mode = v,
  )
  result.add ConfigItemDescriptor(
    kind: cvkBool,
    displayName: "filename",
    section: "StatusLine",
    boolGet: proc(c: EditorConfig): bool =
      c.statusLine.filename,
    boolSet: proc(c: EditorConfig, v: bool) =
      c.statusLine.filename = v,
  )
  result.add ConfigItemDescriptor(
    kind: cvkBool,
    displayName: "changedMark",
    section: "StatusLine",
    boolGet: proc(c: EditorConfig): bool =
      c.statusLine.changedMark,
    boolSet: proc(c: EditorConfig, v: bool) =
      c.statusLine.changedMark = v,
  )
  result.add ConfigItemDescriptor(
    kind: cvkBool,
    displayName: "directory",
    section: "StatusLine",
    boolGet: proc(c: EditorConfig): bool =
      c.statusLine.directory,
    boolSet: proc(c: EditorConfig, v: bool) =
      c.statusLine.directory = v,
  )
  result.add ConfigItemDescriptor(
    kind: cvkBool,
    displayName: "gitChangedLines",
    section: "StatusLine",
    boolGet: proc(c: EditorConfig): bool =
      c.statusLine.gitChangedLines,
    boolSet: proc(c: EditorConfig, v: bool) =
      c.statusLine.gitChangedLines = v,
  )
  result.add ConfigItemDescriptor(
    kind: cvkBool,
    displayName: "gitBranchName",
    section: "StatusLine",
    boolGet: proc(c: EditorConfig): bool =
      c.statusLine.gitBranchName,
    boolSet: proc(c: EditorConfig, v: bool) =
      c.statusLine.gitBranchName = v,
  )
  result.add ConfigItemDescriptor(
    kind: cvkBool,
    displayName: "showGitInactive",
    section: "StatusLine",
    boolGet: proc(c: EditorConfig): bool =
      c.statusLine.showGitInactive,
    boolSet: proc(c: EditorConfig, v: bool) =
      c.statusLine.showGitInactive = v,
  )
  result.add ConfigItemDescriptor(
    kind: cvkBool,
    displayName: "showModeInactive",
    section: "StatusLine",
    boolGet: proc(c: EditorConfig): bool =
      c.statusLine.showModeInactive,
    boolSet: proc(c: EditorConfig, v: bool) =
      c.statusLine.showModeInactive = v,
  )

  # Highlight section
  result.add ConfigItemDescriptor(
    kind: cvkSection, displayName: "Highlight", section: "Highlight"
  )
  result.add ConfigItemDescriptor(
    kind: cvkBool,
    displayName: "currentLine",
    section: "Highlight",
    boolGet: proc(c: EditorConfig): bool =
      c.highlight.currentLine,
    boolSet: proc(c: EditorConfig, v: bool) =
      c.highlight.currentLine = v,
  )
  result.add ConfigItemDescriptor(
    kind: cvkBool,
    displayName: "currentColumn",
    section: "Highlight",
    boolGet: proc(c: EditorConfig): bool =
      c.highlight.currentColumn,
    boolSet: proc(c: EditorConfig, v: bool) =
      c.highlight.currentColumn = v,
  )
  result.add ConfigItemDescriptor(
    kind: cvkBool,
    displayName: "replaceText",
    section: "Highlight",
    boolGet: proc(c: EditorConfig): bool =
      c.highlight.replaceText,
    boolSet: proc(c: EditorConfig, v: bool) =
      c.highlight.replaceText = v,
  )
  result.add ConfigItemDescriptor(
    kind: cvkBool,
    displayName: "pairOfParen",
    section: "Highlight",
    boolGet: proc(c: EditorConfig): bool =
      c.highlight.pairOfParen,
    boolSet: proc(c: EditorConfig, v: bool) =
      c.highlight.pairOfParen = v,
  )
  result.add ConfigItemDescriptor(
    kind: cvkBool,
    displayName: "fullWidthSpace",
    section: "Highlight",
    boolGet: proc(c: EditorConfig): bool =
      c.highlight.fullWidthSpace,
    boolSet: proc(c: EditorConfig, v: bool) =
      c.highlight.fullWidthSpace = v,
  )
  result.add ConfigItemDescriptor(
    kind: cvkBool,
    displayName: "trailingSpaces",
    section: "Highlight",
    boolGet: proc(c: EditorConfig): bool =
      c.highlight.trailingSpaces,
    boolSet: proc(c: EditorConfig, v: bool) =
      c.highlight.trailingSpaces = v,
  )
  result.add ConfigItemDescriptor(
    kind: cvkBool,
    displayName: "currentWord",
    section: "Highlight",
    boolGet: proc(c: EditorConfig): bool =
      c.highlight.currentWord,
    boolSet: proc(c: EditorConfig, v: bool) =
      c.highlight.currentWord = v,
  )
  result.add ConfigItemDescriptor(
    kind: cvkBool,
    displayName: "findCharHighlight",
    section: "Highlight",
    boolGet: proc(c: EditorConfig): bool =
      c.highlight.findCharHighlight,
    boolSet: proc(c: EditorConfig, v: bool) =
      c.highlight.findCharHighlight = v,
  )

  # AutoBackup section
  result.add ConfigItemDescriptor(
    kind: cvkSection, displayName: "AutoBackup", section: "AutoBackup"
  )
  result.add ConfigItemDescriptor(
    kind: cvkBool,
    displayName: "enable",
    section: "AutoBackup",
    boolGet: proc(c: EditorConfig): bool =
      c.autoBackup.enable,
    boolSet: proc(c: EditorConfig, v: bool) =
      c.autoBackup.enable = v,
  )
  result.add ConfigItemDescriptor(
    kind: cvkInt,
    displayName: "idleTime",
    section: "AutoBackup",
    intGet: proc(c: EditorConfig): int =
      c.autoBackup.idleTime,
    intSet: proc(c: EditorConfig, v: int) =
      c.autoBackup.idleTime = v,
    intMin: 1,
    intMax: 3600,
  )
  result.add ConfigItemDescriptor(
    kind: cvkInt,
    displayName: "interval",
    section: "AutoBackup",
    intGet: proc(c: EditorConfig): int =
      c.autoBackup.interval,
    intSet: proc(c: EditorConfig, v: int) =
      c.autoBackup.interval = v,
    intMin: 1,
    intMax: 3600,
  )

  # Notification section
  result.add ConfigItemDescriptor(
    kind: cvkSection, displayName: "Notification", section: "Notification"
  )
  result.add ConfigItemDescriptor(
    kind: cvkBool,
    displayName: "screenNotifications",
    section: "Notification",
    boolGet: proc(c: EditorConfig): bool =
      c.notification.screenNotifications,
    boolSet: proc(c: EditorConfig, v: bool) =
      c.notification.screenNotifications = v,
  )
  result.add ConfigItemDescriptor(
    kind: cvkBool,
    displayName: "logNotifications",
    section: "Notification",
    boolGet: proc(c: EditorConfig): bool =
      c.notification.logNotifications,
    boolSet: proc(c: EditorConfig, v: bool) =
      c.notification.logNotifications = v,
  )
  result.add ConfigItemDescriptor(
    kind: cvkBool,
    displayName: "autoBackupScreenNotify",
    section: "Notification",
    boolGet: proc(c: EditorConfig): bool =
      c.notification.autoBackupScreenNotify,
    boolSet: proc(c: EditorConfig, v: bool) =
      c.notification.autoBackupScreenNotify = v,
  )
  result.add ConfigItemDescriptor(
    kind: cvkBool,
    displayName: "autoBackupLogNotify",
    section: "Notification",
    boolGet: proc(c: EditorConfig): bool =
      c.notification.autoBackupLogNotify,
    boolSet: proc(c: EditorConfig, v: bool) =
      c.notification.autoBackupLogNotify = v,
  )
  result.add ConfigItemDescriptor(
    kind: cvkBool,
    displayName: "autoSaveScreenNotify",
    section: "Notification",
    boolGet: proc(c: EditorConfig): bool =
      c.notification.autoSaveScreenNotify,
    boolSet: proc(c: EditorConfig, v: bool) =
      c.notification.autoSaveScreenNotify = v,
  )
  result.add ConfigItemDescriptor(
    kind: cvkBool,
    displayName: "autoSaveLogNotify",
    section: "Notification",
    boolGet: proc(c: EditorConfig): bool =
      c.notification.autoSaveLogNotify,
    boolSet: proc(c: EditorConfig, v: bool) =
      c.notification.autoSaveLogNotify = v,
  )
  result.add ConfigItemDescriptor(
    kind: cvkBool,
    displayName: "yankScreenNotify",
    section: "Notification",
    boolGet: proc(c: EditorConfig): bool =
      c.notification.yankScreenNotify,
    boolSet: proc(c: EditorConfig, v: bool) =
      c.notification.yankScreenNotify = v,
  )
  result.add ConfigItemDescriptor(
    kind: cvkBool,
    displayName: "yankLogNotify",
    section: "Notification",
    boolGet: proc(c: EditorConfig): bool =
      c.notification.yankLogNotify,
    boolSet: proc(c: EditorConfig, v: bool) =
      c.notification.yankLogNotify = v,
  )
  result.add ConfigItemDescriptor(
    kind: cvkBool,
    displayName: "deleteScreenNotify",
    section: "Notification",
    boolGet: proc(c: EditorConfig): bool =
      c.notification.deleteScreenNotify,
    boolSet: proc(c: EditorConfig, v: bool) =
      c.notification.deleteScreenNotify = v,
  )
  result.add ConfigItemDescriptor(
    kind: cvkBool,
    displayName: "deleteLogNotify",
    section: "Notification",
    boolGet: proc(c: EditorConfig): bool =
      c.notification.deleteLogNotify,
    boolSet: proc(c: EditorConfig, v: bool) =
      c.notification.deleteLogNotify = v,
  )
  result.add ConfigItemDescriptor(
    kind: cvkBool,
    displayName: "saveScreenNotify",
    section: "Notification",
    boolGet: proc(c: EditorConfig): bool =
      c.notification.saveScreenNotify,
    boolSet: proc(c: EditorConfig, v: bool) =
      c.notification.saveScreenNotify = v,
  )
  result.add ConfigItemDescriptor(
    kind: cvkBool,
    displayName: "saveLogNotify",
    section: "Notification",
    boolGet: proc(c: EditorConfig): bool =
      c.notification.saveLogNotify,
    boolSet: proc(c: EditorConfig, v: bool) =
      c.notification.saveLogNotify = v,
  )
  result.add ConfigItemDescriptor(
    kind: cvkBool,
    displayName: "quickRunScreenNotify",
    section: "Notification",
    boolGet: proc(c: EditorConfig): bool =
      c.notification.quickRunScreenNotify,
    boolSet: proc(c: EditorConfig, v: bool) =
      c.notification.quickRunScreenNotify = v,
  )
  result.add ConfigItemDescriptor(
    kind: cvkBool,
    displayName: "quickRunLogNotify",
    section: "Notification",
    boolGet: proc(c: EditorConfig): bool =
      c.notification.quickRunLogNotify,
    boolSet: proc(c: EditorConfig, v: bool) =
      c.notification.quickRunLogNotify = v,
  )
  result.add ConfigItemDescriptor(
    kind: cvkBool,
    displayName: "buildOnSaveScreenNotify",
    section: "Notification",
    boolGet: proc(c: EditorConfig): bool =
      c.notification.buildOnSaveScreenNotify,
    boolSet: proc(c: EditorConfig, v: bool) =
      c.notification.buildOnSaveScreenNotify = v,
  )
  result.add ConfigItemDescriptor(
    kind: cvkBool,
    displayName: "buildOnSaveLogNotify",
    section: "Notification",
    boolGet: proc(c: EditorConfig): bool =
      c.notification.buildOnSaveLogNotify,
    boolSet: proc(c: EditorConfig, v: bool) =
      c.notification.buildOnSaveLogNotify = v,
  )
  result.add ConfigItemDescriptor(
    kind: cvkBool,
    displayName: "filerScreenNotify",
    section: "Notification",
    boolGet: proc(c: EditorConfig): bool =
      c.notification.filerScreenNotify,
    boolSet: proc(c: EditorConfig, v: bool) =
      c.notification.filerScreenNotify = v,
  )
  result.add ConfigItemDescriptor(
    kind: cvkBool,
    displayName: "filerLogNotify",
    section: "Notification",
    boolGet: proc(c: EditorConfig): bool =
      c.notification.filerLogNotify,
    boolSet: proc(c: EditorConfig, v: bool) =
      c.notification.filerLogNotify = v,
  )
  result.add ConfigItemDescriptor(
    kind: cvkBool,
    displayName: "restoreScreenNotify",
    section: "Notification",
    boolGet: proc(c: EditorConfig): bool =
      c.notification.restoreScreenNotify,
    boolSet: proc(c: EditorConfig, v: bool) =
      c.notification.restoreScreenNotify = v,
  )
  result.add ConfigItemDescriptor(
    kind: cvkBool,
    displayName: "restoreLogNotify",
    section: "Notification",
    boolGet: proc(c: EditorConfig): bool =
      c.notification.restoreLogNotify,
    boolSet: proc(c: EditorConfig, v: bool) =
      c.notification.restoreLogNotify = v,
  )
  result.add ConfigItemDescriptor(
    kind: cvkBool,
    displayName: "lspScreenNotify",
    section: "Notification",
    boolGet: proc(c: EditorConfig): bool =
      c.notification.lspScreenNotify,
    boolSet: proc(c: EditorConfig, v: bool) =
      c.notification.lspScreenNotify = v,
  )
  result.add ConfigItemDescriptor(
    kind: cvkBool,
    displayName: "lspLogNotify",
    section: "Notification",
    boolGet: proc(c: EditorConfig): bool =
      c.notification.lspLogNotify,
    boolSet: proc(c: EditorConfig, v: bool) =
      c.notification.lspLogNotify = v,
  )

  # Filer section
  result.add ConfigItemDescriptor(
    kind: cvkSection, displayName: "Filer", section: "Filer"
  )
  result.add ConfigItemDescriptor(
    kind: cvkBool,
    displayName: "showIcons",
    section: "Filer",
    boolGet: proc(c: EditorConfig): bool =
      c.filer.showIcons,
    boolSet: proc(c: EditorConfig, v: bool) =
      c.filer.showIcons = v,
  )

  # Autocomplete section
  result.add ConfigItemDescriptor(
    kind: cvkSection, displayName: "Autocomplete", section: "Autocomplete"
  )
  result.add ConfigItemDescriptor(
    kind: cvkBool,
    displayName: "enable",
    section: "Autocomplete",
    boolGet: proc(c: EditorConfig): bool =
      c.autocomplete.enable,
    boolSet: proc(c: EditorConfig, v: bool) =
      c.autocomplete.enable = v,
  )
  result.add ConfigItemDescriptor(
    kind: cvkBool,
    displayName: "windowBorder",
    section: "Autocomplete",
    boolGet: proc(c: EditorConfig): bool =
      c.autocomplete.windowBorder,
    boolSet: proc(c: EditorConfig, v: bool) =
      c.autocomplete.windowBorder = v,
  )

  # AutoSave section
  result.add ConfigItemDescriptor(
    kind: cvkSection, displayName: "AutoSave", section: "AutoSave"
  )
  result.add ConfigItemDescriptor(
    kind: cvkBool,
    displayName: "enable",
    section: "AutoSave",
    boolGet: proc(c: EditorConfig): bool =
      c.autoSave.enable,
    boolSet: proc(c: EditorConfig, v: bool) =
      c.autoSave.enable = v,
  )
  result.add ConfigItemDescriptor(
    kind: cvkInt,
    displayName: "interval",
    section: "AutoSave",
    intGet: proc(c: EditorConfig): int =
      c.autoSave.interval,
    intSet: proc(c: EditorConfig, v: int) =
      c.autoSave.interval = v,
    intMin: 1,
    intMax: 3600,
  )

  # Git section
  result.add ConfigItemDescriptor(kind: cvkSection, displayName: "Git", section: "Git")
  result.add ConfigItemDescriptor(
    kind: cvkBool,
    displayName: "showChangedLine",
    section: "Git",
    boolGet: proc(c: EditorConfig): bool =
      c.git.showChangedLine,
    boolSet: proc(c: EditorConfig, v: bool) =
      c.git.showChangedLine = v,
  )
  result.add ConfigItemDescriptor(
    kind: cvkInt,
    displayName: "updateInterval",
    section: "Git",
    intGet: proc(c: EditorConfig): int =
      c.git.updateInterval,
    intSet: proc(c: EditorConfig, v: int) =
      c.git.updateInterval = v,
    intMin: 100,
    intMax: 60000,
  )

  # SyntaxChecker section
  result.add ConfigItemDescriptor(
    kind: cvkSection, displayName: "SyntaxChecker", section: "SyntaxChecker"
  )
  result.add ConfigItemDescriptor(
    kind: cvkBool,
    displayName: "enable",
    section: "SyntaxChecker",
    boolGet: proc(c: EditorConfig): bool =
      c.syntaxChecker.enable,
    boolSet: proc(c: EditorConfig, v: bool) =
      c.syntaxChecker.enable = v,
  )

  # SmoothScroll section
  result.add ConfigItemDescriptor(
    kind: cvkSection, displayName: "SmoothScroll", section: "SmoothScroll"
  )
  result.add ConfigItemDescriptor(
    kind: cvkBool,
    displayName: "enable",
    section: "SmoothScroll",
    boolGet: proc(c: EditorConfig): bool =
      c.smoothScroll.enable,
    boolSet: proc(c: EditorConfig, v: bool) =
      c.smoothScroll.enable = v,
  )
  result.add ConfigItemDescriptor(
    kind: cvkFloat,
    displayName: "friction",
    section: "SmoothScroll",
    floatGet: proc(c: EditorConfig): float =
      c.smoothScroll.friction,
    floatSet: proc(c: EditorConfig, v: float) =
      c.smoothScroll.friction = v,
    floatMin: 0.0,
    floatMax: 500.0,
    floatStep: 10.0,
  )
  result.add ConfigItemDescriptor(
    kind: cvkFloat,
    displayName: "airDrag",
    section: "SmoothScroll",
    floatGet: proc(c: EditorConfig): float =
      c.smoothScroll.airDrag,
    floatSet: proc(c: EditorConfig, v: float) =
      c.smoothScroll.airDrag = v,
    floatMin: 0.0,
    floatMax: 20.0,
    floatStep: 0.5,
  )

  # Theme section
  result.add ConfigItemDescriptor(
    kind: cvkSection, displayName: "Theme", section: "Theme"
  )
  result.add ConfigItemDescriptor(
    kind: cvkEnum,
    displayName: "kind",
    section: "Theme",
    enumGet: proc(c: EditorConfig): string =
      $c.theme.kind,
    enumSet: proc(c: EditorConfig, v: string) =
      c.theme.kind = parseEnum[ThemeKind](v),
    enumOptions: @["default", "config", "vscode"],
  )
  result.add ConfigItemDescriptor(
    kind: cvkString,
    displayName: "path",
    section: "Theme",
    visibleWhen: proc(c: EditorConfig): bool =
      c.theme.kind == tkConfig,
    stringGet: proc(c: EditorConfig): string =
      c.theme.path,
    stringSetter: proc(c: EditorConfig, v: string) =
      c.theme.path = v,
  )

  # LSP section
  result.add ConfigItemDescriptor(kind: cvkSection, displayName: "Lsp", section: "Lsp")
  result.add ConfigItemDescriptor(
    kind: cvkBool,
    displayName: "enable",
    section: "Lsp",
    boolGet: proc(c: EditorConfig): bool =
      c.lsp.enable,
    boolSet: proc(c: EditorConfig, v: bool) =
      c.lsp.enable = v,
  )
  result.add ConfigItemDescriptor(
    kind: cvkInt,
    displayName: "timeout",
    section: "Lsp",
    intGet: proc(c: EditorConfig): int =
      c.lsp.timeout,
    intSet: proc(c: EditorConfig, v: int) =
      c.lsp.timeout = v,
    intMin: 1000,
    intMax: 60000,
  )

# Global descriptor table (built once)
let configDescriptors* = makeDescriptors()

# Item building and value application

proc buildItemList*(state: ConfigModeState) =
  ## Build the flat list of config items from EditorConfig using descriptors
  state.items = @[]
  let cfg = state.config

  for i, desc in configDescriptors:
    if desc.visibleWhen != nil and not desc.visibleWhen(cfg):
      continue
    case desc.kind
    of cvkSection:
      state.items.add ConfigItem(
        kind: cvkSection,
        displayName: desc.displayName,
        section: desc.section,
        depth: 0,
        descriptorIndex: -1,
      )
    of cvkBool:
      state.items.add ConfigItem(
        kind: cvkBool,
        displayName: desc.displayName,
        section: desc.section,
        depth: 1,
        descriptorIndex: i,
        boolValue: desc.boolGet(cfg),
      )
    of cvkInt:
      state.items.add ConfigItem(
        kind: cvkInt,
        displayName: desc.displayName,
        section: desc.section,
        depth: 1,
        descriptorIndex: i,
        intValue: desc.intGet(cfg),
        intMin: desc.intMin,
        intMax: desc.intMax,
      )
    of cvkFloat:
      state.items.add ConfigItem(
        kind: cvkFloat,
        displayName: desc.displayName,
        section: desc.section,
        depth: 1,
        descriptorIndex: i,
        floatValue: desc.floatGet(cfg),
        floatMin: desc.floatMin,
        floatMax: desc.floatMax,
        floatStep: desc.floatStep,
      )
    of cvkEnum:
      state.items.add ConfigItem(
        kind: cvkEnum,
        displayName: desc.displayName,
        section: desc.section,
        depth: 1,
        descriptorIndex: i,
        enumValue: desc.enumGet(cfg),
        enumOptions: desc.enumOptions,
      )
    of cvkString:
      state.items.add ConfigItem(
        kind: cvkString,
        displayName: desc.displayName,
        section: desc.section,
        depth: 1,
        descriptorIndex: i,
        stringValue: desc.stringGet(cfg),
      )

proc applyChange*(state: ConfigModeState, itemIndex: int) =
  ## Apply a change to the actual config using descriptors
  if itemIndex < 0 or itemIndex >= state.items.len:
    return

  let item = state.items[itemIndex]
  if item.descriptorIndex < 0:
    return # Section headers have no descriptor

  let desc = configDescriptors[item.descriptorIndex]
  let cfg = state.config

  case item.kind
  of cvkBool:
    desc.boolSet(cfg, item.boolValue)
  of cvkInt:
    desc.intSet(cfg, item.intValue)
  of cvkFloat:
    desc.floatSet(cfg, item.floatValue)
  of cvkEnum:
    desc.enumSet(cfg, item.enumValue)
  of cvkString:
    desc.stringSetter(cfg, item.stringValue)
  else:
    discard

  # Rebuild to update conditional visibility
  let savedDescIdx = item.descriptorIndex
  state.buildItemList()
  for i, newItem in state.items:
    if newItem.descriptorIndex == savedDescIdx:
      state.selectedIndex = i
      break
  if state.selectedIndex >= state.items.len:
    state.selectedIndex = max(0, state.items.len - 1)

# State management

proc newConfigModeState*(config: EditorConfig): ConfigModeState =
  ## Create a new Configuration mode state
  result = ConfigModeState(
    items: @[],
    selectedIndex: 0,
    topLine: 0,
    editMode: false,
    editBuffer: "",
    editCursor: 0,
    enumPopupOpen: false,
    enumPopupIndex: 0,
    config: config,
  )
  result.buildItemList()

proc getSelectedItem*(state: ConfigModeState): Option[ConfigItem] =
  ## Get the currently selected item
  if state.selectedIndex >= 0 and state.selectedIndex < state.items.len:
    some(state.items[state.selectedIndex])
  else:
    none(ConfigItem)

proc getSelectedItemIndex*(state: ConfigModeState): int =
  ## Get the index of currently selected item
  if state.selectedIndex >= 0 and state.selectedIndex < state.items.len:
    state.selectedIndex
  else:
    -1

proc moveUp*(state: ConfigModeState) =
  ## Move selection up
  if state.selectedIndex > 0:
    state.selectedIndex.dec
    if state.selectedIndex < state.topLine:
      state.topLine = state.selectedIndex

proc moveDown*(state: ConfigModeState) =
  ## Move selection down
  if state.selectedIndex < state.items.len - 1:
    state.selectedIndex.inc

proc ensureSelectedVisible*(state: ConfigModeState, viewportHeight: int) =
  ## Ensure the selected item is visible in the viewport
  if state.selectedIndex < state.topLine:
    state.topLine = state.selectedIndex
  elif state.selectedIndex >= state.topLine + viewportHeight:
    state.topLine = state.selectedIndex - viewportHeight + 1

proc moveToFirst*(state: ConfigModeState) =
  ## Move to first item
  state.selectedIndex = 0
  state.topLine = 0

proc moveToLast*(state: ConfigModeState) =
  ## Move to last item
  state.selectedIndex = max(0, state.items.len - 1)

# Value manipulation

proc toggleBoolValue*(state: ConfigModeState) =
  ## Toggle a boolean value
  let itemIndex = state.getSelectedItemIndex()
  if itemIndex >= 0 and state.items[itemIndex].kind == cvkBool:
    state.items[itemIndex].boolValue = not state.items[itemIndex].boolValue
    state.applyChange(itemIndex)

proc cycleEnumValue*(state: ConfigModeState, forward: bool = true) =
  ## Cycle through enum options
  let itemIndex = state.getSelectedItemIndex()
  if itemIndex < 0:
    return

  let item = state.items[itemIndex]
  if item.kind == cvkEnum and item.enumOptions.len > 0:
    var currentIdx = item.enumOptions.find(item.enumValue)
    if currentIdx < 0:
      currentIdx = 0
    if forward:
      currentIdx = (currentIdx + 1) mod item.enumOptions.len
    else:
      currentIdx = (currentIdx - 1 + item.enumOptions.len) mod item.enumOptions.len
    state.items[itemIndex].enumValue = item.enumOptions[currentIdx]
    state.applyChange(itemIndex)

proc incrementIntValue*(state: ConfigModeState) =
  ## Increment integer value
  let itemIndex = state.getSelectedItemIndex()
  if itemIndex >= 0 and state.items[itemIndex].kind == cvkInt:
    let item = state.items[itemIndex]
    if item.intValue < item.intMax:
      state.items[itemIndex].intValue = item.intValue + 1
      state.applyChange(itemIndex)

proc decrementIntValue*(state: ConfigModeState) =
  ## Decrement integer value
  let itemIndex = state.getSelectedItemIndex()
  if itemIndex >= 0 and state.items[itemIndex].kind == cvkInt:
    let item = state.items[itemIndex]
    if item.intValue > item.intMin:
      state.items[itemIndex].intValue = item.intValue - 1
      state.applyChange(itemIndex)

proc incrementFloatValue*(state: ConfigModeState) =
  ## Increment float value by step
  let itemIndex = state.getSelectedItemIndex()
  if itemIndex >= 0 and state.items[itemIndex].kind == cvkFloat:
    let item = state.items[itemIndex]
    let newValue = item.floatValue + item.floatStep
    if newValue <= item.floatMax:
      state.items[itemIndex].floatValue = newValue
      state.applyChange(itemIndex)

proc decrementFloatValue*(state: ConfigModeState) =
  ## Decrement float value by step
  let itemIndex = state.getSelectedItemIndex()
  if itemIndex >= 0 and state.items[itemIndex].kind == cvkFloat:
    let item = state.items[itemIndex]
    let newValue = item.floatValue - item.floatStep
    if newValue >= item.floatMin:
      state.items[itemIndex].floatValue = newValue
      state.applyChange(itemIndex)

# Display formatting

proc formatItemForDisplay*(item: ConfigItem, maxNameWidth: int): string =
  ## Format a config item for display
  let indent = "  ".repeat(item.depth)
  let name = item.displayName.alignLeft(maxNameWidth - item.depth * 2)

  case item.kind
  of cvkSection:
    return "[" & item.displayName & "]"
  of cvkBool:
    return indent & name & " : " & (if item.boolValue: "true" else: "false")
  of cvkInt:
    return indent & name & " : " & $item.intValue
  of cvkFloat:
    return indent & name & " : " & $item.floatValue
  of cvkString:
    return indent & name & " : " & item.stringValue
  of cvkEnum:
    return indent & name & " : " & item.enumValue

# Edit mode (Int/String editing)

proc startEdit*(state: ConfigModeState) =
  ## Start editing the current value
  let itemIndex = state.getSelectedItemIndex()
  if itemIndex < 0:
    return

  let item = state.items[itemIndex]
  case item.kind
  of cvkInt:
    state.editMode = true
    state.editBuffer = $item.intValue
    state.editCursor = state.editBuffer.len
  of cvkFloat:
    state.editMode = true
    state.editBuffer = $item.floatValue
    state.editCursor = state.editBuffer.len
  of cvkString:
    state.editMode = true
    state.editBuffer = item.stringValue
    state.editCursor = state.editBuffer.len
  else:
    discard

proc cancelEdit*(state: ConfigModeState) =
  ## Cancel editing and discard changes
  state.editMode = false
  state.editBuffer = ""
  state.editCursor = 0

proc confirmEdit*(state: ConfigModeState): bool =
  ## Confirm the edit and apply the value
  ## Returns true if successful
  let itemIndex = state.getSelectedItemIndex()
  if itemIndex < 0:
    state.cancelEdit()
    return false

  let item = state.items[itemIndex]
  case item.kind
  of cvkInt:
    try:
      let newValue = parseInt(state.editBuffer)
      if newValue >= item.intMin and newValue <= item.intMax:
        state.items[itemIndex].intValue = newValue
        state.applyChange(itemIndex)
        state.cancelEdit()
        return true
      else:
        return false # Value out of range
    except ValueError:
      return false # Invalid number
  of cvkFloat:
    try:
      let newValue = parseFloat(state.editBuffer)
      if newValue >= item.floatMin and newValue <= item.floatMax:
        state.items[itemIndex].floatValue = newValue
        state.applyChange(itemIndex)
        state.cancelEdit()
        return true
      else:
        return false # Value out of range
    except ValueError:
      return false # Invalid number
  of cvkString:
    state.items[itemIndex].stringValue = state.editBuffer
    state.applyChange(itemIndex)
    state.cancelEdit()
    return true
  else:
    state.cancelEdit()
    return false

proc editInsertChar*(state: ConfigModeState, c: string) =
  ## Insert a character at cursor position in edit buffer
  if not state.editMode:
    return
  state.editBuffer.insert(c, state.editCursor)
  state.editCursor.inc

proc editBackspace*(state: ConfigModeState) =
  ## Delete character before cursor
  if not state.editMode or state.editCursor <= 0:
    return
  state.editBuffer.delete(state.editCursor - 1 ..< state.editCursor)
  state.editCursor.dec

proc editDelete*(state: ConfigModeState) =
  ## Delete character at cursor
  if not state.editMode or state.editCursor >= state.editBuffer.len:
    return
  state.editBuffer.delete(state.editCursor ..< state.editCursor + 1)

proc editMoveCursorLeft*(state: ConfigModeState) =
  ## Move cursor left in edit buffer
  if state.editMode and state.editCursor > 0:
    state.editCursor.dec

proc editMoveCursorRight*(state: ConfigModeState) =
  ## Move cursor right in edit buffer
  if state.editMode and state.editCursor < state.editBuffer.len:
    state.editCursor.inc

proc editMoveCursorHome*(state: ConfigModeState) =
  ## Move cursor to beginning of edit buffer
  if state.editMode:
    state.editCursor = 0

proc editMoveCursorEnd*(state: ConfigModeState) =
  ## Move cursor to end of edit buffer
  if state.editMode:
    state.editCursor = state.editBuffer.len

proc isEditing*(state: ConfigModeState): bool =
  ## Check if currently in edit mode
  state.editMode

proc getEditInfo*(state: ConfigModeState): tuple[buffer: string, cursor: int] =
  ## Get edit buffer and cursor position
  (state.editBuffer, state.editCursor)

# Enum popup

proc isEnumPopupOpen*(state: ConfigModeState): bool =
  ## Check if enum selection popup is open
  state.enumPopupOpen

proc openEnumPopup*(state: ConfigModeState) =
  ## Open the enum selection popup for the current item
  let itemIndex = state.getSelectedItemIndex()
  if itemIndex < 0:
    return

  let item = state.items[itemIndex]
  if item.kind != cvkEnum:
    return

  state.enumPopupOpen = true
  state.enumPopupIndex = item.enumOptions.find(item.enumValue)
  if state.enumPopupIndex < 0:
    state.enumPopupIndex = 0

proc closeEnumPopup*(state: ConfigModeState) =
  ## Close the enum selection popup without applying
  state.enumPopupOpen = false
  state.enumPopupIndex = 0

proc enumPopupMoveUp*(state: ConfigModeState) =
  ## Move selection up in enum popup (wraps to last item at top)
  if not state.enumPopupOpen:
    return

  let itemIndex = state.getSelectedItemIndex()
  if itemIndex < 0:
    return

  let item = state.items[itemIndex]
  if item.kind == cvkEnum:
    if state.enumPopupIndex > 0:
      state.enumPopupIndex.dec
    else:
      state.enumPopupIndex = item.enumOptions.len - 1

proc enumPopupMoveDown*(state: ConfigModeState) =
  ## Move selection down in enum popup (wraps to first item at bottom)
  if not state.enumPopupOpen:
    return

  let itemIndex = state.getSelectedItemIndex()
  if itemIndex < 0:
    return

  let item = state.items[itemIndex]
  if item.kind == cvkEnum:
    if state.enumPopupIndex < item.enumOptions.len - 1:
      state.enumPopupIndex.inc
    else:
      state.enumPopupIndex = 0

proc enumPopupConfirm*(state: ConfigModeState) =
  ## Confirm selection in enum popup
  if not state.enumPopupOpen:
    return

  let itemIndex = state.getSelectedItemIndex()
  if itemIndex < 0:
    state.closeEnumPopup()
    return

  let item = state.items[itemIndex]
  if item.kind == cvkEnum and state.enumPopupIndex < item.enumOptions.len:
    state.items[itemIndex].enumValue = item.enumOptions[state.enumPopupIndex]
    state.applyChange(itemIndex)

  state.closeEnumPopup()

proc getEnumPopupInfo*(
    state: ConfigModeState
): tuple[options: seq[string], selectedIndex: int] =
  ## Get enum popup options and selected index
  let itemIndex = state.getSelectedItemIndex()
  if itemIndex < 0:
    return (@[], 0)

  let item = state.items[itemIndex]
  if item.kind == cvkEnum:
    return (item.enumOptions, state.enumPopupIndex)
  else:
    return (@[], 0)
