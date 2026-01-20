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
  EditorMode* = enum
    Normal
    Insert
    Command
    Visual
    VisualBlock
    VisualLine
    Replace
    Search
    Filer
    QuickRun
    LogViewer
    Help
    BufferManager
    BackupManager
    DiffViewer
    RecentFile
    Debug
    Config
    References
    DocumentSymbol

  ModeTransition* = object
    newMode*: Option[EditorMode]
    handled*: bool

proc modeLabel*(m: EditorMode): string =
  case m
  of EditorMode.Normal: "NORMAL"
  of EditorMode.Insert: "INSERT"
  of EditorMode.Command: "COMMAND"
  of EditorMode.Visual: "VISUAL"
  of EditorMode.VisualBlock: "VISUAL BLOCK"
  of EditorMode.VisualLine: "VISUAL LINE"
  of EditorMode.Replace: "REPLACE"
  of EditorMode.Search: "SEARCH"
  of EditorMode.Filer: "FILER"
  of EditorMode.QuickRun: "QUICKRUN"
  of EditorMode.LogViewer: "LOG"
  of EditorMode.Help: "HELP"
  of EditorMode.BufferManager: "BUFFERS"
  of EditorMode.BackupManager: "BACKUPS"
  of EditorMode.DiffViewer: "DIFF"
  of EditorMode.RecentFile: "RECENT"
  of EditorMode.Debug: "DEBUG"
  of EditorMode.Config: "CONFIG"
  of EditorMode.References: "REFERENCES"
  of EditorMode.DocumentSymbol: "SYMBOLS"
