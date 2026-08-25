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

## File explorer (filer) state management
##
## This module provides the data structures and operations for the file explorer mode.

import std/[os, options, times, strutils, unicode]

import pkg/celina

import buffer/core, highlight, color, dir_scan
import syntax/tokenizer

import types/filer_types
export filer_types

proc isDirectory*(entry: FileEntry): bool =
  ## Check if entry is effectively a directory (including symlinks to directories)
  isDirectoryLike(entry.kind, entry.targetKind)

proc isFile*(entry: FileEntry): bool =
  ## Check if entry is effectively a file (including symlinks to files)
  entry.kind == fekFile or (entry.kind == fekSymlink and entry.targetKind == fekFile)

proc refresh*(state: FilerState) =
  ## Refresh the file list from the current directory
  state.entries = @[]

  # Always add parent directory entry (except for root)
  if state.currentPath != "/":
    state.entries.add(
      FileEntry(
        name: "..",
        kind: fekDirectory,
        size: 0,
        modified: Time(),
        isHidden: false,
        isExecutable: false,
        targetKind: fekDirectory,
      )
    )

  state.entries.add(
    scanDirectory(state.currentPath, state.showHidden, skipOnStatError = true)
  )

  # Ensure selectedIndex is valid
  if state.selectedIndex >= state.entries.len:
    state.selectedIndex = max(0, state.entries.len - 1)

  state.needsBufferRefresh = true

proc newFilerState*(path: string): FilerState =
  ## Create a new FilerState for the given directory
  let normalizedPath = normalizedPath(absolutePath(expandTilde(path)))
  result = FilerState(
    currentPath: normalizedPath, entries: @[], selectedIndex: 0, showHidden: true
  )
  result.refresh()

proc getSelectedEntry*(state: FilerState): Option[FileEntry] =
  ## Get the currently selected entry
  if state.selectedIndex >= 0 and state.selectedIndex < state.entries.len:
    some(state.entries[state.selectedIndex])
  else:
    none(FileEntry)

proc getSelectedPath*(state: FilerState): Option[string] =
  ## Get the full path of the currently selected entry
  let entry = state.getSelectedEntry()
  if entry.isSome:
    let e = entry.get
    if e.name == "..":
      some(parentDir(state.currentPath))
    else:
      some(state.currentPath / e.name)
  else:
    none(string)

proc moveUp*(state: FilerState) =
  ## Move selection up
  if state.selectedIndex > 0:
    dec state.selectedIndex

proc moveDown*(state: FilerState) =
  ## Move selection down
  if state.selectedIndex < state.entries.len - 1:
    inc state.selectedIndex

proc moveToFirst*(state: FilerState) =
  ## Move selection to the first entry
  state.selectedIndex = 0

proc moveToLast*(state: FilerState) =
  ## Move selection to the last entry
  state.selectedIndex = max(0, state.entries.len - 1)

proc toggleHidden*(state: FilerState) =
  ## Toggle display of hidden files
  state.showHidden = not state.showHidden
  state.refresh()

proc enterDirectory*(state: FilerState, path: string): bool =
  ## Enter a directory, returns true if successful
  let normalizedPath = normalizedPath(absolutePath(path))
  if dirExists(normalizedPath):
    state.currentPath = normalizedPath
    state.selectedIndex = 0
    state.refresh()
    true
  else:
    false

proc goToParent*(state: FilerState): bool =
  ## Go to parent directory, returns true if successful
  if state.currentPath == "/":
    return false
  let parent = parentDir(state.currentPath)
  if parent.len > 0 and parent != state.currentPath:
    let oldDir = extractFilename(state.currentPath)
    state.currentPath = parent
    state.selectedIndex = 0
    state.refresh()

    # Try to select the directory we came from
    for i, entry in state.entries:
      if entry.name == oldDir:
        state.selectedIndex = i
        break

    true
  else:
    false

proc halfPageDown*(state: FilerState, viewportHeight: int, reservedLines: int = 1) =
  ## Move half a page down
  let availableHeight = max(1, viewportHeight - reservedLines)
  let halfPage = max(1, availableHeight div 2)
  state.selectedIndex = min(state.entries.len - 1, state.selectedIndex + halfPage)

proc halfPageUp*(state: FilerState, viewportHeight: int, reservedLines: int = 1) =
  ## Move half a page up
  let availableHeight = max(1, viewportHeight - reservedLines)
  let halfPage = max(1, availableHeight div 2)
  state.selectedIndex = max(0, state.selectedIndex - halfPage)

proc deleteSelected*(
    state: FilerState
): tuple[success: bool, path: string, error: string] =
  ## Delete the currently selected file or directory
  ## Returns success status, the deleted path, and error message if failed
  let entry = state.getSelectedEntry()
  if entry.isNone:
    return (false, "", "No file selected")

  let e = entry.get

  # Don't allow deleting ".."
  if e.name == "..":
    return (false, "", "Cannot delete parent directory reference")

  let path = state.currentPath / e.name

  try:
    if e.kind == fekDirectory:
      # Remove directory recursively
      removeDir(path)
    else:
      # Remove file (or symlink)
      removeFile(path)

    # Refresh the file list after deletion
    state.refresh()

    return (true, path, "")
  except OSError as ex:
    return (false, path, ex.msg)

proc formatFileSize(size: int64): string =
  ## Format file size in human-readable format
  if size < 1024:
    return $size & " B"
  elif size < 1024 * 1024:
    return $(size div 1024) & " KB"
  elif size < 1024 * 1024 * 1024:
    return $(size div (1024 * 1024)) & " MB"
  else:
    return $(size div (1024 * 1024 * 1024)) & " GB"

proc getSelectedInfo*(state: FilerState): string =
  ## Get detailed information about the currently selected file/directory
  ## Returns a formatted string with name, type, size, and modification time
  let entry = state.getSelectedEntry()
  if entry.isNone:
    return "No file selected"

  let e = entry.get

  if e.name == "..":
    return "Parent directory"

  var info = e.name

  # File type
  case e.kind
  of fekFile:
    info.add(" [File]")
  of fekDirectory:
    info.add(" [Dir]")
  of fekSymlink:
    if e.targetKind == fekDirectory:
      info.add(" [Symlink->Dir]")
    else:
      info.add(" [Symlink->File]")

  # Size (only for files)
  if e.kind == fekFile or (e.kind == fekSymlink and e.targetKind == fekFile):
    info.add(" " & formatFileSize(e.size))

  # Executable flag
  if e.isExecutable:
    info.add(" [x]")

  # Modification time
  let timeStr = e.modified.format("yyyy-MM-dd HH:mm:ss")
  info.add(" " & timeStr)

  return info

proc pathToIcon*(entry: FileEntry): string =
  ## Get an emoji icon for a file entry based on its type and extension
  if entry.kind == fekDirectory or entry.targetKind == fekDirectory:
    return "📁 "

  if entry.isExecutable:
    return "🏃 "

  let filename = entry.name
  # Check for Dockerfile
  if filename == "Dockerfile" or filename.startsWith("Dockerfile."):
    return "🐳 "

  # Get extension
  let dotPos = filename.rfind('.')
  if dotPos < 0:
    return "📄 "

  let ext = filename[dotPos + 1 .. ^1].toLower()
  case ext
  of "nim": "👑 "
  of "nimble", "rpm", "deb": "📦 "
  of "py": "🐍 "
  of "ui", "glade": "🏠 "
  of "txt", "md", "rst": "📝 "
  of "cpp", "cxx", "hpp", "cc": "⧺ "
  of "c", "h": "🅒 "
  of "java": "🍵 "
  of "php": "🙈 "
  of "js", "json", "mjs", "cjs": "🙉 "
  of "ts", "tsx": "📘 "
  of "rs": "🦀 "
  of "go": "🐹 "
  of "html", "xhtml", "htm": "🏄 "
  of "css", "scss", "sass": "👚 "
  of "xml": "༕ "
  of "cfg", "ini", "conf": "🍳 "
  of "sh", "bash", "zsh", "fish": "🐚 "
  of "pdf", "doc", "docx", "odf", "ods", "odt": "🍞 "
  of "wav", "mp3", "ogg", "flac", "m4a": "🎼 "
  of "zip", "bz2", "xz", "gz", "tgz", "zst", "tar", "7z", "rar": "🚢 "
  of "exe", "bin", "elf": "🏃 "
  of "mp4", "webm", "avi", "mpeg", "mkv", "mov": "🎞 "
  of "patch", "diff": "💊 "
  of "lock": "🔒 "
  of "pem", "crt", "key": "🔏 "
  of "png", "jpeg", "jpg", "bmp", "gif", "svg", "webp", "ico": "🎨 "
  of "toml", "yaml", "yml": "⚙ "
  of "nix": "❄ "
  of "hs", "lhs": "λ "
  of "lua": "🌙 "
  of "rb": "💎 "
  of "pl", "pm": "🐪 "
  of "sql": "🗃 "
  of "vim": "📗 "
  of "el", "lisp", "scm": "λ "
  else: "📄 "

proc createFilerTextBuffer*(state: FilerState, showIcons: bool): TextBuffer =
  ## Create a TextBuffer from filer entries for rendering via the normal view path.
  ## Sets custom highlight ColorSegments for entry-type coloring.
  var content = ""
  var lines: seq[string]

  for i, entry in state.entries:
    let icon =
      if showIcons:
        pathToIcon(entry)
      else:
        case entry.kind
        of fekDirectory: "▸ "
        of fekSymlink: "@ "
        of fekFile: "  "

    let name =
      if entry.isDirectory:
        entry.name & "/"
      else:
        entry.name

    let line = " " & icon & name
    lines.add(line)
    if i > 0:
      content.add('\n')
    content.add(line)

  result = newTextBuffer(content)
  result.readOnly = true
  result.isUtilityBuffer = true
  result.highlightNeedsUpdate = false
  result.language = langNone
  result.filePath = some(state.currentPath)

  # Build custom highlight ColorSegments for entry-type coloring
  var segments: seq[ColorSegment] = @[]

  # Entry styles
  for i, entry in state.entries:
    let row = i
    let lineLen = max(0, lines[row].toRunes().high)
    let (colorIdx, style) =
      if entry.kind == fekDirectory:
        (
          EditorColorPairIndex.filerDirectory,
          getThemeStyle(EditorColorPairIndex.filerDirectory, {StyleModifier.Bold}),
        )
      elif entry.kind == fekSymlink:
        if entry.targetKind == fekDirectory:
          (
            EditorColorPairIndex.filerSymlinkDir,
            getThemeStyle(EditorColorPairIndex.filerSymlinkDir, {StyleModifier.Bold}),
          )
        else:
          (
            EditorColorPairIndex.filerSymlink,
            getThemeStyle(EditorColorPairIndex.filerSymlink),
          )
      elif entry.isHidden:
        (
          EditorColorPairIndex.filerHiddenFile,
          getThemeStyle(EditorColorPairIndex.filerHiddenFile),
        )
      elif entry.isExecutable:
        (
          EditorColorPairIndex.filerExecutable,
          getThemeStyle(EditorColorPairIndex.filerExecutable, {StyleModifier.Bold}),
        )
      else:
        (EditorColorPairIndex.default, getThemeStyle(EditorColorPairIndex.default))

    segments.add(
      ColorSegment(
        firstRow: row,
        firstColumn: 0,
        lastRow: row,
        lastColumn: lineLen,
        color: colorIdx,
        style: style,
      )
    )

  result.highlight = Highlight(colorSegments: segments)
