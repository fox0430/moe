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

import std/options

type
  OverlayKind* {.pure.} = enum
    ## Overlay types for transient modes that sit on top of base modes
    ## These modes don't change the underlying mode - they just add an input overlay
    okCommand ## Command mode overlay (ex-mode, :)
    okSearch ## Search mode overlay (/, ?)
    okRename ## LSP rename mode overlay

  EditorMode* {.pure.} = enum
    Normal
    Insert
    Visual
    VisualBlock
    VisualLine
    Replace
    Command
    Filer
    QuickRun
    LogViewer
    Help
    BufferManager
    BookmarkManager
    BackupManager
    DiffViewer
    RecentFile
    Debug
    Config
    References
    DocumentSymbol
    CallHierarchy
    Terminal
    FileTree

  ModeTransition* = object
    newMode*: Option[EditorMode]
    handled*: bool

proc isFileEditMode*(m: EditorMode): bool =
  ## Returns true if the mode is a file editing mode where syntax highlighting applies
  ## Special modes (Filer, Help, Config, QuickRun, etc.) return false
  ## - QuickRun shows execution output, not editable source
  m in {
    EditorMode.Normal, EditorMode.Insert, EditorMode.Visual, EditorMode.VisualBlock,
    EditorMode.VisualLine, EditorMode.Replace,
  }

proc modeLabel*(m: EditorMode, insertNormal: bool = false): string =
  case m
  of EditorMode.Normal:
    if insertNormal: "(insert) NORMAL" else: "NORMAL"
  of EditorMode.Insert:
    "INSERT"
  of EditorMode.Visual:
    "VISUAL"
  of EditorMode.VisualBlock:
    "VISUAL BLOCK"
  of EditorMode.VisualLine:
    "VISUAL LINE"
  of EditorMode.Replace:
    "REPLACE"
  of EditorMode.Command:
    "COMMAND"
  of EditorMode.Filer:
    "FILER"
  of EditorMode.QuickRun:
    "QUICKRUN"
  of EditorMode.LogViewer:
    "LOG"
  of EditorMode.Help:
    "HELP"
  of EditorMode.BufferManager:
    "BUFFERS"
  of EditorMode.BookmarkManager:
    "BOOKMARKS"
  of EditorMode.BackupManager:
    "BACKUPS"
  of EditorMode.DiffViewer:
    "DIFF"
  of EditorMode.RecentFile:
    "RECENT"
  of EditorMode.Debug:
    "DEBUG"
  of EditorMode.Config:
    "CONFIG"
  of EditorMode.References:
    "REFERENCES"
  of EditorMode.DocumentSymbol:
    "SYMBOLS"
  of EditorMode.CallHierarchy:
    "CALL HIERARCHY"
  of EditorMode.Terminal:
    "TERMINAL"
  of EditorMode.FileTree:
    "FILETREE"

proc isVisualAllMode*(mode: EditorMode): bool =
  ## Check if the mode is any visual mode variant
  mode in {EditorMode.Visual, EditorMode.VisualBlock, EditorMode.VisualLine}

proc overlayLabel*(o: OverlayKind): string =
  case o
  of okCommand: "COMMAND"
  of okSearch: "SEARCH"
  of okRename: "RENAME"
