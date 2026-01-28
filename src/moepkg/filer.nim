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

import std/[os, options, algorithm, times, strutils]

type
  FileEntryKind* = enum
    fekFile
    fekDirectory
    fekSymlink

  FileEntry* = object
    name*: string
    kind*: FileEntryKind
    size*: int64
    modified*: Time
    isHidden*: bool
    isExecutable*: bool # Whether the file has execute permission
    targetKind*: FileEntryKind # For symlinks: the kind of the target (fekFile if broken)

  FilerState* = ref object
    currentPath*: string # Current directory path
    entries*: seq[FileEntry] # File/directory entries
    selectedIndex*: int # Currently selected entry index
    showHidden*: bool # Whether to show hidden files
    topLine*: int # Scroll position (first visible line)
    previousPath*: Option[string] # Path to return to when closing filer

proc isHiddenFile(name: string): bool =
  ## Check if a file is hidden (starts with .)
  name.len > 0 and name[0] == '.'

proc isDirectory*(entry: FileEntry): bool =
  ## Check if entry is effectively a directory (including symlinks to directories)
  entry.kind == fekDirectory or
    (entry.kind == fekSymlink and entry.targetKind == fekDirectory)

proc isFile*(entry: FileEntry): bool =
  ## Check if entry is effectively a file (including symlinks to files)
  entry.kind == fekFile or (entry.kind == fekSymlink and entry.targetKind == fekFile)

proc newFileEntry(path: string, info: FileInfo): FileEntry =
  ## Create a FileEntry from a path and FileInfo
  let name = extractFilename(path)
  var kind: FileEntryKind
  var targetKind: FileEntryKind = fekFile # Default for non-symlinks
  var isExec = false

  case info.kind
  of pcDir:
    kind = fekDirectory
    targetKind = fekDirectory
  of pcLinkToDir:
    kind = fekSymlink
    targetKind = fekDirectory
  of pcLinkToFile:
    kind = fekSymlink
    targetKind = fekFile
  of pcFile:
    kind = fekFile
    targetKind = fekFile
    # Check if file is executable
    isExec = fpUserExec in info.permissions or fpGroupExec in info.permissions

  FileEntry(
    name: name,
    kind: kind,
    size: info.size,
    modified: info.lastWriteTime,
    isHidden: isHiddenFile(name),
    isExecutable: isExec,
    targetKind: targetKind,
  )

proc compareEntries(a, b: FileEntry): int =
  ## Compare entries for sorting: directories first, then alphabetically
  if a.kind == fekDirectory and b.kind != fekDirectory:
    return -1
  elif a.kind != fekDirectory and b.kind == fekDirectory:
    return 1
  else:
    return cmpIgnoreCase(a.name, b.name)

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

  # Read directory contents
  try:
    for kind, path in walkDir(state.currentPath):
      try:
        let info = getFileInfo(path, followSymlink = false)
        let entry = newFileEntry(path, info)

        # Filter hidden files if showHidden is false
        if state.showHidden or not entry.isHidden:
          state.entries.add(entry)
      except OSError:
        # Skip files we can't access
        discard
  except OSError:
    # Directory not accessible
    discard

  # Sort entries (directories first, then alphabetically)
  # Keep ".." at the top
  if state.entries.len > 1:
    var entriesToSort = state.entries[1 ..^ 1]
    entriesToSort.sort(compareEntries)
    state.entries = @[state.entries[0]] & entriesToSort

  # Ensure selectedIndex is valid
  if state.selectedIndex >= state.entries.len:
    state.selectedIndex = max(0, state.entries.len - 1)

proc newFilerState*(
    path: string, previousPath: Option[string] = none(string)
): FilerState =
  ## Create a new FilerState for the given directory
  let normalizedPath = absolutePath(expandTilde(path))
  result = FilerState(
    currentPath: normalizedPath,
    entries: @[],
    selectedIndex: 0,
    showHidden: false,
    topLine: 0,
    previousPath: previousPath,
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
  state.topLine = 0

proc moveToLast*(state: FilerState) =
  ## Move selection to the last entry
  state.selectedIndex = max(0, state.entries.len - 1)

proc toggleHidden*(state: FilerState) =
  ## Toggle display of hidden files
  state.showHidden = not state.showHidden
  state.refresh()

proc enterDirectory*(state: FilerState, path: string): bool =
  ## Enter a directory, returns true if successful
  let normalizedPath = absolutePath(path)
  if dirExists(normalizedPath):
    state.currentPath = normalizedPath
    state.selectedIndex = 0
    state.topLine = 0
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
    state.topLine = 0
    state.refresh()

    # Try to select the directory we came from
    for i, entry in state.entries:
      if entry.name == oldDir:
        state.selectedIndex = i
        break

    true
  else:
    false

proc visibleEntries*(state: FilerState, height: int): seq[FileEntry] =
  ## Get the visible entries based on current scroll position
  let startIdx = state.topLine
  let endIdx = min(state.topLine + height, state.entries.len)
  if startIdx < state.entries.len:
    state.entries[startIdx ..< endIdx]
  else:
    @[]

proc ensureSelectedVisible*(
    state: FilerState, viewportHeight: int, reservedLines: int = 3
) =
  ## Ensure the selected entry is visible in the viewport
  ## reservedLines: total lines reserved (header + status line + command line)
  let availableHeight = max(1, viewportHeight - reservedLines)

  if state.selectedIndex < state.topLine:
    state.topLine = state.selectedIndex
  elif state.selectedIndex >= state.topLine + availableHeight:
    state.topLine = state.selectedIndex - availableHeight + 1

proc halfPageDown*(state: FilerState, viewportHeight: int, reservedLines: int = 3) =
  ## Move half a page down
  let availableHeight = max(1, viewportHeight - reservedLines)
  let halfPage = max(1, availableHeight div 2)
  state.selectedIndex = min(state.entries.len - 1, state.selectedIndex + halfPage)
  state.ensureSelectedVisible(viewportHeight, reservedLines)

proc halfPageUp*(state: FilerState, viewportHeight: int, reservedLines: int = 3) =
  ## Move half a page up
  let availableHeight = max(1, viewportHeight - reservedLines)
  let halfPage = max(1, availableHeight div 2)
  state.selectedIndex = max(0, state.selectedIndex - halfPage)
  state.ensureSelectedVisible(viewportHeight, reservedLines)

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
