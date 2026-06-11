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

type
  ColorModeKind* = enum
    ## Color mode for terminal output
    cmk8color ## 8 basic ANSI colors (0-7)
    cmk16color ## 16 ANSI colors (0-15, includes bright)
    cmk256color ## 256-color palette
    cmk24bit ## True color (24-bit RGB)
    cmkNone ## No colors (terminal defaults only)

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
    sidebarSessionModifiedSign
    sidebarSessionInsertedSign

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

    # Status line - Command mode
    statusLineExMode
    statusLineExModeLabel
    statusLineExModeInactive

    # Status line - QuickRun mode
    statusLineQuickRunMode
    statusLineQuickRunModeLabel
    statusLineQuickRunModeInactive

    # Status line - Log viewer mode
    statusLineLogViewerMode
    statusLineLogViewerModeLabel
    statusLineLogViewerModeInactive

    # Status line - Help mode
    statusLineHelpMode
    statusLineHelpModeLabel
    statusLineHelpModeInactive

    # Status line - Buffer manager mode
    statusLineBufferManagerMode
    statusLineBufferManagerModeLabel
    statusLineBufferManagerModeInactive

    # Status line - Bookmark manager mode
    statusLineBookmarkManagerMode
    statusLineBookmarkManagerModeLabel
    statusLineBookmarkManagerModeInactive

    # Status line - Backup manager mode
    statusLineBackupManagerMode
    statusLineBackupManagerModeLabel
    statusLineBackupManagerModeInactive

    # Status line - Diff viewer mode
    statusLineDiffViewerMode
    statusLineDiffViewerModeLabel
    statusLineDiffViewerModeInactive

    # Status line - Recent file mode
    statusLineRecentFileMode
    statusLineRecentFileModeLabel
    statusLineRecentFileModeInactive

    # Status line - Debug mode
    statusLineDebugMode
    statusLineDebugModeLabel
    statusLineDebugModeInactive

    # Status line - Configuration mode
    statusLineConfigMode
    statusLineConfigModeLabel
    statusLineConfigModeInactive

    # Status line - References mode
    statusLineReferencesMode
    statusLineReferencesModeLabel
    statusLineReferencesModeInactive

    # Status line - Document symbol mode
    statusLineDocumentSymbolMode
    statusLineDocumentSymbolModeLabel
    statusLineDocumentSymbolModeInactive

    # Status line - Call hierarchy mode
    statusLineCallHierarchyMode
    statusLineCallHierarchyModeLabel
    statusLineCallHierarchyModeInactive

    # Status line - Terminal mode
    statusLineTerminalMode
    statusLineTerminalModeLabel
    statusLineTerminalModeInactive

    # Status line - File tree mode
    statusLineFileTreeMode
    statusLineFileTreeModeLabel
    statusLineFileTreeModeInactive

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
    # Find character match highlight (f/F/t/T)
    findCharMatch

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
    docComment
    docLongComment
    whitespace
    preprocessor
    pragma
    identifier
    table
    date
    logError
    logWarning
    logInfo
    logUuid
    operator
    property

    # Syntax highlighting - Markdown
    markdownCodeBlock

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
    codeLens

    # Filer mode
    currentFile
    file
    dir
    pcLink

    # Popup window
    popupWindow
    popupWinCurrentLine
    popupWindowBorder
    popupWindowDetail
    popupWindowScrollBar
    popupWindowActiveParameter

    # Notification popup
    notificationPopupInfo
    notificationPopupInfoBorder
    notificationPopupWarning
    notificationPopupWarningBorder
    notificationPopupError
    notificationPopupErrorBorder

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
    gitConflictMarker
    gitConflictOurs
    gitConflictBase
    gitConflictTheirs

    # Backup manager
    backupManagerCurrentLine

    # Diff viewer
    diffViewerAddedLine
    diffViewerDeletedLine

    # Configuration mode
    configModeCurrentLine

    # Current line background
    currentLineBg
    # Current column background
    currentColumnBg
    foldingLine

    # Side bar
    sidebarGitAddedSign
    sidebarGitDeletedSign
    sidebarGitChangedSign
    sidebarGitConflictSign
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
    filerExecutable

    # Buffer manager specific
    bufferManagerActive
    bufferManagerModified

    # Configuration mode specific
    configModeSection
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

    # Indentation guide
    indentationLine

    # Scroll bar
    scrollBarThumb
    scrollBarTrack

    # LSP document highlight (textDocument/documentHighlight)
    documentHighlightText
    documentHighlightRead
    documentHighlightWrite

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
  EditorColorPairDocDescription*: array[EditorColorPairIndex, string] = [
    ## Human-readable description for each color pair, used by
    ## `tools/gen_config_docs.nim` to render the Color table in
    ## `documents/configfile.md`. Every enum member must have an entry —
    ## adding a new variant without a description triggers a compile error
    ## here, so undocumented theme colors cannot ship silently.
    EditorColorPairIndex.default: "Editor default text and background colors",
    EditorColorPairIndex.lineNum: "Line number gutter",
    EditorColorPairIndex.currentLineNum: "Current line number highlight",
    EditorColorPairIndex.sidebarSessionModifiedSign: "Sidebar: modified line sign",
    EditorColorPairIndex.sidebarSessionInsertedSign: "Sidebar: inserted line sign",
    EditorColorPairIndex.statusLineNormalMode: "Status line in Normal mode (active)",
    EditorColorPairIndex.statusLineNormalModeLabel:
      "Status line mode label in Normal mode",
    EditorColorPairIndex.statusLineNormalModeInactive:
      "Status line in Normal mode (inactive)",
    EditorColorPairIndex.statusLineInsertMode: "Status line in Insert mode (active)",
    EditorColorPairIndex.statusLineInsertModeLabel:
      "Status line mode label in Insert mode",
    EditorColorPairIndex.statusLineInsertModeInactive:
      "Status line in Insert mode (inactive)",
    EditorColorPairIndex.statusLineVisualMode: "Status line in Visual mode (active)",
    EditorColorPairIndex.statusLineVisualModeLabel:
      "Status line mode label in Visual mode",
    EditorColorPairIndex.statusLineVisualModeInactive:
      "Status line in Visual mode (inactive)",
    EditorColorPairIndex.statusLineReplaceMode: "Status line in Replace mode (active)",
    EditorColorPairIndex.statusLineReplaceModeLabel:
      "Status line mode label in Replace mode",
    EditorColorPairIndex.statusLineReplaceModeInactive:
      "Status line in Replace mode (inactive)",
    EditorColorPairIndex.statusLineFilerMode: "Status line in Filer mode (active)",
    EditorColorPairIndex.statusLineFilerModeLabel:
      "Status line mode label in Filer mode",
    EditorColorPairIndex.statusLineFilerModeInactive:
      "Status line in Filer mode (inactive)",
    EditorColorPairIndex.statusLineExMode: "Status line in Command mode (active)",
    EditorColorPairIndex.statusLineExModeLabel: "Status line mode label in Command mode",
    EditorColorPairIndex.statusLineExModeInactive:
      "Status line in Command mode (inactive)",
    EditorColorPairIndex.statusLineQuickRunMode: "Status line in QuickRun mode (active)",
    EditorColorPairIndex.statusLineQuickRunModeLabel:
      "Status line mode label in QuickRun mode",
    EditorColorPairIndex.statusLineQuickRunModeInactive:
      "Status line in QuickRun mode (inactive)",
    EditorColorPairIndex.statusLineLogViewerMode:
      "Status line in Log viewer mode (active)",
    EditorColorPairIndex.statusLineLogViewerModeLabel:
      "Status line mode label in Log viewer mode",
    EditorColorPairIndex.statusLineLogViewerModeInactive:
      "Status line in Log viewer mode (inactive)",
    EditorColorPairIndex.statusLineHelpMode: "Status line in Help mode (active)",
    EditorColorPairIndex.statusLineHelpModeLabel: "Status line mode label in Help mode",
    EditorColorPairIndex.statusLineHelpModeInactive:
      "Status line in Help mode (inactive)",
    EditorColorPairIndex.statusLineBufferManagerMode:
      "Status line in Buffer manager mode (active)",
    EditorColorPairIndex.statusLineBufferManagerModeLabel:
      "Status line mode label in Buffer manager mode",
    EditorColorPairIndex.statusLineBufferManagerModeInactive:
      "Status line in Buffer manager mode (inactive)",
    EditorColorPairIndex.statusLineBookmarkManagerMode:
      "Status line in Bookmark manager mode (active)",
    EditorColorPairIndex.statusLineBookmarkManagerModeLabel:
      "Status line mode label in Bookmark manager mode",
    EditorColorPairIndex.statusLineBookmarkManagerModeInactive:
      "Status line in Bookmark manager mode (inactive)",
    EditorColorPairIndex.statusLineBackupManagerMode:
      "Status line in Backup manager mode (active)",
    EditorColorPairIndex.statusLineBackupManagerModeLabel:
      "Status line mode label in Backup manager mode",
    EditorColorPairIndex.statusLineBackupManagerModeInactive:
      "Status line in Backup manager mode (inactive)",
    EditorColorPairIndex.statusLineDiffViewerMode:
      "Status line in Diff viewer mode (active)",
    EditorColorPairIndex.statusLineDiffViewerModeLabel:
      "Status line mode label in Diff viewer mode",
    EditorColorPairIndex.statusLineDiffViewerModeInactive:
      "Status line in Diff viewer mode (inactive)",
    EditorColorPairIndex.statusLineRecentFileMode:
      "Status line in Recent file mode (active)",
    EditorColorPairIndex.statusLineRecentFileModeLabel:
      "Status line mode label in Recent file mode",
    EditorColorPairIndex.statusLineRecentFileModeInactive:
      "Status line in Recent file mode (inactive)",
    EditorColorPairIndex.statusLineDebugMode: "Status line in Debug mode (active)",
    EditorColorPairIndex.statusLineDebugModeLabel:
      "Status line mode label in Debug mode",
    EditorColorPairIndex.statusLineDebugModeInactive:
      "Status line in Debug mode (inactive)",
    EditorColorPairIndex.statusLineConfigMode:
      "Status line in Configuration mode (active)",
    EditorColorPairIndex.statusLineConfigModeLabel:
      "Status line mode label in Configuration mode",
    EditorColorPairIndex.statusLineConfigModeInactive:
      "Status line in Configuration mode (inactive)",
    EditorColorPairIndex.statusLineReferencesMode:
      "Status line in References mode (active)",
    EditorColorPairIndex.statusLineReferencesModeLabel:
      "Status line mode label in References mode",
    EditorColorPairIndex.statusLineReferencesModeInactive:
      "Status line in References mode (inactive)",
    EditorColorPairIndex.statusLineDocumentSymbolMode:
      "Status line in Document symbol mode (active)",
    EditorColorPairIndex.statusLineDocumentSymbolModeLabel:
      "Status line mode label in Document symbol mode",
    EditorColorPairIndex.statusLineDocumentSymbolModeInactive:
      "Status line in Document symbol mode (inactive)",
    EditorColorPairIndex.statusLineCallHierarchyMode:
      "Status line in Call hierarchy mode (active)",
    EditorColorPairIndex.statusLineCallHierarchyModeLabel:
      "Status line mode label in Call hierarchy mode",
    EditorColorPairIndex.statusLineCallHierarchyModeInactive:
      "Status line in Call hierarchy mode (inactive)",
    EditorColorPairIndex.statusLineTerminalMode: "Status line in Terminal mode (active)",
    EditorColorPairIndex.statusLineTerminalModeLabel:
      "Status line mode label in Terminal mode",
    EditorColorPairIndex.statusLineTerminalModeInactive:
      "Status line in Terminal mode (inactive)",
    EditorColorPairIndex.statusLineFileTreeMode:
      "Status line in File tree mode (active)",
    EditorColorPairIndex.statusLineFileTreeModeLabel:
      "Status line mode label in File tree mode",
    EditorColorPairIndex.statusLineFileTreeModeInactive:
      "Status line in File tree mode (inactive)",
    EditorColorPairIndex.statusLineGitChangedLines:
      "Status line git changed-lines counter",
    EditorColorPairIndex.statusLineGitBranch: "Status line git branch name",
    EditorColorPairIndex.tab: "Tab title in the tab line",
    EditorColorPairIndex.currentTab: "Current tab title in the tab line",
    EditorColorPairIndex.commandLine: "Command line",
    EditorColorPairIndex.errorMessage: "Error message",
    EditorColorPairIndex.warnMessage: "Warning message",
    EditorColorPairIndex.searchResult: "Search result highlight",
    EditorColorPairIndex.findCharMatch: "f/F/t/T character match highlight",
    EditorColorPairIndex.selectArea: "Visual mode selection",
    EditorColorPairIndex.keyword: "Syntax: keyword",
    EditorColorPairIndex.functionName: "Syntax: function name",
    EditorColorPairIndex.typeName: "Syntax: type name",
    EditorColorPairIndex.boolean: "Syntax: boolean literal",
    EditorColorPairIndex.specialVar: "Syntax: special variable",
    EditorColorPairIndex.builtin: "Syntax: builtin",
    EditorColorPairIndex.charLit: "Syntax: character literal",
    EditorColorPairIndex.stringLit: "Syntax: string literal",
    EditorColorPairIndex.binNumber: "Syntax: binary number literal",
    EditorColorPairIndex.decNumber: "Syntax: decimal number literal",
    EditorColorPairIndex.floatNumber: "Syntax: floating-point number literal",
    EditorColorPairIndex.hexNumber: "Syntax: hexadecimal number literal",
    EditorColorPairIndex.octNumber: "Syntax: octal number literal",
    EditorColorPairIndex.comment: "Syntax: line comment",
    EditorColorPairIndex.longComment: "Syntax: block/long comment",
    EditorColorPairIndex.docComment: "Syntax: documentation comment",
    EditorColorPairIndex.docLongComment: "Syntax: long documentation comment",
    EditorColorPairIndex.whitespace: "Syntax: whitespace indicator",
    EditorColorPairIndex.preprocessor: "Syntax: preprocessor directive",
    EditorColorPairIndex.pragma: "Syntax: pragma",
    EditorColorPairIndex.identifier: "Syntax: identifier",
    EditorColorPairIndex.table: "Syntax: TOML table header",
    EditorColorPairIndex.date: "Syntax: date literal",
    EditorColorPairIndex.logError: "Log file error level",
    EditorColorPairIndex.logWarning: "Log file warning level",
    EditorColorPairIndex.logInfo: "Log file info/debug level",
    EditorColorPairIndex.logUuid: "Log file UUID",
    EditorColorPairIndex.operator: "Syntax: operator",
    EditorColorPairIndex.property: "Syntax: property",
    EditorColorPairIndex.markdownCodeBlock: "Markdown code block",
    EditorColorPairIndex.namespace: "LSP semantic token: namespace",
    EditorColorPairIndex.className: "LSP semantic token: class name",
    EditorColorPairIndex.enumName: "LSP semantic token: enum name",
    EditorColorPairIndex.enumMember: "LSP semantic token: enum member",
    EditorColorPairIndex.interfaceName: "LSP semantic token: interface name",
    EditorColorPairIndex.typeParameter: "LSP semantic token: type parameter",
    EditorColorPairIndex.parameter: "LSP semantic token: parameter",
    EditorColorPairIndex.variable: "LSP semantic token: variable",
    EditorColorPairIndex.lspString: "LSP semantic token: string",
    EditorColorPairIndex.event: "LSP semantic token: event",
    EditorColorPairIndex.function: "LSP semantic token: function",
    EditorColorPairIndex.`method`: "LSP semantic token: method",
    EditorColorPairIndex.`macro`: "LSP semantic token: macro",
    EditorColorPairIndex.regexp: "LSP semantic token: regular expression",
    EditorColorPairIndex.decorator: "LSP semantic token: decorator",
    EditorColorPairIndex.angle: "LSP semantic token: angle bracket",
    EditorColorPairIndex.arithmetic: "LSP semantic token: arithmetic operator",
    EditorColorPairIndex.attribute: "LSP semantic token: attribute",
    EditorColorPairIndex.attributeBracket: "LSP semantic token: attribute bracket",
    EditorColorPairIndex.bitwise: "LSP semantic token: bitwise operator",
    EditorColorPairIndex.brace: "LSP semantic token: brace",
    EditorColorPairIndex.bracket: "LSP semantic token: bracket",
    EditorColorPairIndex.builtinAttribute: "LSP semantic token: builtin attribute",
    EditorColorPairIndex.builtinType: "LSP semantic token: builtin type",
    EditorColorPairIndex.colon: "LSP semantic token: colon",
    EditorColorPairIndex.comma: "LSP semantic token: comma",
    EditorColorPairIndex.comparison: "LSP semantic token: comparison operator",
    EditorColorPairIndex.constParameter: "LSP semantic token: const parameter",
    EditorColorPairIndex.derive: "LSP semantic token: derive",
    EditorColorPairIndex.deriveHelper: "LSP semantic token: derive helper",
    EditorColorPairIndex.dot: "LSP semantic token: dot",
    EditorColorPairIndex.escapeSequence: "LSP semantic token: escape sequence",
    EditorColorPairIndex.invalidEscapeSequence:
      "LSP semantic token: invalid escape sequence",
    EditorColorPairIndex.formatSpecifier: "LSP semantic token: format specifier",
    EditorColorPairIndex.generic: "LSP semantic token: generic",
    EditorColorPairIndex.label: "LSP semantic token: label",
    EditorColorPairIndex.lifetime: "LSP semantic token: lifetime",
    EditorColorPairIndex.logical: "LSP semantic token: logical operator",
    EditorColorPairIndex.macroBang: "LSP semantic token: macro bang (`!`)",
    EditorColorPairIndex.parenthesis: "LSP semantic token: parenthesis",
    EditorColorPairIndex.punctuation: "Syntax: punctuation",
    EditorColorPairIndex.selfKeyword: "LSP semantic token: `self` keyword",
    EditorColorPairIndex.selfTypeKeyword: "LSP semantic token: `Self` type keyword",
    EditorColorPairIndex.semicolon: "LSP semantic token: semicolon",
    EditorColorPairIndex.typeAlias: "LSP semantic token: type alias",
    EditorColorPairIndex.toolModule: "LSP semantic token: tool module",
    EditorColorPairIndex.union: "LSP semantic token: union",
    EditorColorPairIndex.unresolvedReference: "LSP semantic token: unresolved reference",
    EditorColorPairIndex.inlayHint: "LSP inlay hint",
    EditorColorPairIndex.codeLens: "LSP code lens",
    EditorColorPairIndex.currentFile: "Filer: current file name",
    EditorColorPairIndex.file: "Filer: file name",
    EditorColorPairIndex.dir: "Filer: directory name",
    EditorColorPairIndex.pcLink: "Filer: symbolic link",
    EditorColorPairIndex.popupWindow: "Pop-up window",
    EditorColorPairIndex.popupWinCurrentLine: "Pop-up window current line",
    EditorColorPairIndex.popupWindowBorder: "Pop-up window border",
    EditorColorPairIndex.popupWindowDetail: "Pop-up window detail text",
    EditorColorPairIndex.popupWindowScrollBar: "Pop-up window scroll indicator",
    EditorColorPairIndex.popupWindowActiveParameter:
      "Pop-up window active parameter (signature help)",
    EditorColorPairIndex.notificationPopupInfo: "Notification popup: info body",
    EditorColorPairIndex.notificationPopupInfoBorder: "Notification popup: info border",
    EditorColorPairIndex.notificationPopupWarning: "Notification popup: warning body",
    EditorColorPairIndex.notificationPopupWarningBorder:
      "Notification popup: warning border",
    EditorColorPairIndex.notificationPopupError: "Notification popup: error body",
    EditorColorPairIndex.notificationPopupErrorBorder:
      "Notification popup: error border",
    EditorColorPairIndex.replaceText: "Replace command replacement text",
    EditorColorPairIndex.parenPair: "Matching bracket pair highlight",
    EditorColorPairIndex.currentWord: "Other occurrences of the word under cursor",
    EditorColorPairIndex.highlightFullWidthSpace: "Full-width space highlight",
    EditorColorPairIndex.highlightTrailingSpaces: "Trailing whitespace highlight",
    EditorColorPairIndex.reservedWord: "Reserved word highlight",
    EditorColorPairIndex.syntaxCheckInfo: "Syntax checker: info diagnostic",
    EditorColorPairIndex.syntaxCheckHint: "Syntax checker: hint diagnostic",
    EditorColorPairIndex.syntaxCheckWarn: "Syntax checker: warning diagnostic",
    EditorColorPairIndex.syntaxCheckErr: "Syntax checker: error diagnostic",
    EditorColorPairIndex.gitConflict:
      "Git conflict block (single-color fallback when gitConflictTwoColor = false)",
    EditorColorPairIndex.gitConflictMarker:
      "Git conflict marker lines (`<<<<<<<`, `|||||||`, `=======`, `>>>>>>>`)",
    EditorColorPairIndex.gitConflictOurs: "Git conflict: \"ours\" side",
    EditorColorPairIndex.gitConflictBase: "Git conflict: diff3 \"base\" side",
    EditorColorPairIndex.gitConflictTheirs: "Git conflict: \"theirs\" side",
    EditorColorPairIndex.backupManagerCurrentLine: "Backup manager: current line",
    EditorColorPairIndex.diffViewerAddedLine: "Diff viewer: added line",
    EditorColorPairIndex.diffViewerDeletedLine: "Diff viewer: deleted line",
    EditorColorPairIndex.configModeCurrentLine: "Configuration mode: current line",
    EditorColorPairIndex.currentLineBg: "Editor current line background (bg-only)",
    EditorColorPairIndex.currentColumnBg: "Editor current column background (bg-only)",
    EditorColorPairIndex.foldingLine: "Folded-region indicator line",
    EditorColorPairIndex.sidebarGitAddedSign: "Sidebar: git added sign",
    EditorColorPairIndex.sidebarGitDeletedSign: "Sidebar: git deleted sign",
    EditorColorPairIndex.sidebarGitChangedSign: "Sidebar: git changed sign",
    EditorColorPairIndex.sidebarGitConflictSign: "Sidebar: git conflict sign",
    EditorColorPairIndex.sidebarSyntaxCheckInfoSign: "Sidebar: syntax checker info sign",
    EditorColorPairIndex.sidebarSyntaxCheckHintSign: "Sidebar: syntax checker hint sign",
    EditorColorPairIndex.sidebarSyntaxCheckWarnSign:
      "Sidebar: syntax checker warning sign",
    EditorColorPairIndex.sidebarSyntaxCheckErrSign: "Sidebar: syntax checker error sign",
    EditorColorPairIndex.viewerHeader: "Viewer common: header",
    EditorColorPairIndex.viewerSelectedLine: "Viewer common: selected line",
    EditorColorPairIndex.viewerEmptyMessage: "Viewer common: empty-state message",
    EditorColorPairIndex.filerDirectory: "Filer: directory entry",
    EditorColorPairIndex.filerSymlink: "Filer: symbolic link entry",
    EditorColorPairIndex.filerSymlinkDir: "Filer: symbolic link to directory",
    EditorColorPairIndex.filerHiddenFile: "Filer: hidden file entry",
    EditorColorPairIndex.filerExecutable: "Filer: executable file entry",
    EditorColorPairIndex.bufferManagerActive: "Buffer manager: active buffer",
    EditorColorPairIndex.bufferManagerModified: "Buffer manager: modified buffer",
    EditorColorPairIndex.configModeSection: "Configuration mode: section header",
    EditorColorPairIndex.configModeEditMode: "Configuration mode: edit mode indicator",
    EditorColorPairIndex.configModePopupBg: "Configuration mode: popup body and border",
    EditorColorPairIndex.configModePopupSelected:
      "Configuration mode: popup selected entry",
    EditorColorPairIndex.diffViewerHeader: "Diff viewer: header",
    EditorColorPairIndex.diffViewerMeta: "Diff viewer: metadata line",
    EditorColorPairIndex.recentFileMissing: "Recent file mode: missing file entry",
    EditorColorPairIndex.debugViewerSectionHeader: "Debug viewer: section header",
    EditorColorPairIndex.referencesViewerHeader: "References viewer: header",
    EditorColorPairIndex.documentSymbolViewerHeader: "Document symbol viewer: header",
    EditorColorPairIndex.callHierarchyViewerHeader: "Call hierarchy viewer: header",
    EditorColorPairIndex.helpViewerSectionHeader: "Help viewer: section header",
    EditorColorPairIndex.indentationLine: "Indentation guide line",
    EditorColorPairIndex.scrollBarThumb: "Scroll bar thumb (handle)",
    EditorColorPairIndex.scrollBarTrack: "Scroll bar track (background)",
    EditorColorPairIndex.documentHighlightText:
      "LSP document highlight: text occurrence",
    EditorColorPairIndex.documentHighlightRead: "LSP document highlight: read access",
    EditorColorPairIndex.documentHighlightWrite: "LSP document highlight: write access",
  ]

  ## Terminal default RGB (-1 indicates use terminal default)
  TerminalDefaultRgb* = Rgb(red: -1, green: -1, blue: -1)

  ## Default terminal colors
  DefaultForegroundColor* = ThemeColor(rgb: TerminalDefaultRgb)
  DefaultBackgroundColor* = ThemeColor(rgb: TerminalDefaultRgb)

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

proc toTomlColorKey*(index: EditorColorPairIndex): string =
  ## Convert EditorColorPairIndex to its TOML key in the theme file.
  ## Names generally match the enum, with three "Bg"-stripped exceptions
  ## whose enum identifiers predate the inline-table TOML format
  ## (`currentLineBg`, `currentColumnBg`, `configModePopupBg`), plus
  ## `lspString` which is keyed as `string` to avoid the enum-keyword clash.
  case index
  of EditorColorPairIndex.lspString:
    "string"
  of EditorColorPairIndex.currentLineBg:
    "currentLine"
  of EditorColorPairIndex.currentColumnBg:
    "currentColumn"
  of EditorColorPairIndex.configModePopupBg:
    "configModePopup"
  else:
    $index

proc isTermDefaultColor*(rgb: Rgb): bool {.inline.} =
  ## Check if this RGB represents the terminal default color
  rgb == TerminalDefaultRgb

proc hexToRgb*(s: string): Result[Rgb, string] =
  ## Parse a hex color string to RGB.
  ## Examples: "#000000", "ff0000"

  if not ((s.len == 6 and not s.startsWith('#')) or (s.len == 7 and s.startsWith('#'))):
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
