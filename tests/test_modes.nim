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

import std/unittest

import ../src/moepkg/modes

suite "Modes - overlayLabel":
  test "okCommand returns COMMAND":
    check overlayLabel(okCommand) == "COMMAND"

  test "okSearch returns SEARCH":
    check overlayLabel(okSearch) == "SEARCH"

  test "okRename returns RENAME":
    check overlayLabel(okRename) == "RENAME"

suite "Modes - modeLabel":
  test "Normal mode":
    check modeLabel(EditorMode.Normal) == "NORMAL"

  test "Insert mode":
    check modeLabel(EditorMode.Insert) == "INSERT"

  test "Visual mode":
    check modeLabel(EditorMode.Visual) == "VISUAL"

  test "VisualBlock mode":
    check modeLabel(EditorMode.VisualBlock) == "VISUAL BLOCK"

  test "VisualLine mode":
    check modeLabel(EditorMode.VisualLine) == "VISUAL LINE"

  test "Replace mode":
    check modeLabel(EditorMode.Replace) == "REPLACE"

  test "Filer mode":
    check modeLabel(EditorMode.Filer) == "FILER"

  test "LogViewer mode":
    check modeLabel(EditorMode.LogViewer) == "LOG"

  test "Help mode":
    check modeLabel(EditorMode.Help) == "HELP"

  test "BufferManager mode":
    check modeLabel(EditorMode.BufferManager) == "BUFFERS"

  test "BackupManager mode":
    check modeLabel(EditorMode.BackupManager) == "BACKUPS"

  test "DiffViewer mode":
    check modeLabel(EditorMode.DiffViewer) == "DIFF"

  test "RecentFile mode":
    check modeLabel(EditorMode.RecentFile) == "RECENT"

  test "Debug mode":
    check modeLabel(EditorMode.Debug) == "DEBUG"

  test "Config mode":
    check modeLabel(EditorMode.Config) == "CONFIG"

  test "References mode":
    check modeLabel(EditorMode.References) == "REFERENCES"

  test "DocumentSymbol mode":
    check modeLabel(EditorMode.DocumentSymbol) == "SYMBOLS"

  test "CallHierarchy mode":
    check modeLabel(EditorMode.CallHierarchy) == "CALL HIERARCHY"

  test "Normal mode with insertNormal":
    check modeLabel(EditorMode.Normal, true) == "(insert) NORMAL"

  test "Normal mode with insertNormal=false":
    check modeLabel(EditorMode.Normal, false) == "NORMAL"

  test "Insert mode ignores insertNormal":
    check modeLabel(EditorMode.Insert, true) == "INSERT"

suite "Modes - isFileEditMode":
  test "Normal is file edit mode":
    check isFileEditMode(EditorMode.Normal) == true

  test "Insert is file edit mode":
    check isFileEditMode(EditorMode.Insert) == true

  test "Visual is file edit mode":
    check isFileEditMode(EditorMode.Visual) == true

  test "VisualBlock is file edit mode":
    check isFileEditMode(EditorMode.VisualBlock) == true

  test "VisualLine is file edit mode":
    check isFileEditMode(EditorMode.VisualLine) == true

  test "Replace is file edit mode":
    check isFileEditMode(EditorMode.Replace) == true

  test "Filer is not file edit mode":
    check isFileEditMode(EditorMode.Filer) == false

  test "LogViewer is not file edit mode":
    check isFileEditMode(EditorMode.LogViewer) == false

  test "Help is not file edit mode":
    check isFileEditMode(EditorMode.Help) == false

  test "BufferManager is not file edit mode":
    check isFileEditMode(EditorMode.BufferManager) == false

  test "BackupManager is not file edit mode":
    check isFileEditMode(EditorMode.BackupManager) == false

  test "DiffViewer is not file edit mode":
    check isFileEditMode(EditorMode.DiffViewer) == false

  test "RecentFile is not file edit mode":
    check isFileEditMode(EditorMode.RecentFile) == false

  test "Debug is not file edit mode":
    check isFileEditMode(EditorMode.Debug) == false

  test "Config is not file edit mode":
    check isFileEditMode(EditorMode.Config) == false

  test "References is not file edit mode":
    check isFileEditMode(EditorMode.References) == false

  test "DocumentSymbol is not file edit mode":
    check isFileEditMode(EditorMode.DocumentSymbol) == false

  test "CallHierarchy is not file edit mode":
    check isFileEditMode(EditorMode.CallHierarchy) == false

suite "Modes - OverlayKind enumeration":
  test "All overlay kinds are defined":
    # Verify all overlay kinds exist
    check okCommand in {okCommand, okSearch, okRename}
    check okSearch in {okCommand, okSearch, okRename}
    check okRename in {okCommand, okSearch, okRename}
