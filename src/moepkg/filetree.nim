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

## File tree (NerdTree-style) state management
##
## This module provides tree-based file browsing with expandable directories.

import std/[os, options, algorithm, sets, strutils, tables, times, unicode]

import pkg/celina

import buffer, highlight, color, filer, logger, unicode_utils

import types/filetree_types
export filetree_types

const DefaultFileTreeWidth* = 30

proc scanDirectory(
    path: string, depth: int, showHidden: bool, error: var string
): seq[FileTreeNode] =
  ## Scan a directory and return sorted child nodes.
  ## Sets `error` if a directory-level OSError occurs.
  var dirs: seq[FileTreeNode] = @[]
  var files: seq[FileTreeNode] = @[]

  try:
    for kind, childPath in walkDir(path):
      try:
        let name = extractFilename(childPath)
        let isHid = name.len > 0 and name[0] == '.'

        if not showHidden and isHid:
          continue

        var nodeKind: FileEntryKind
        var tgtKind: FileEntryKind = fekFile
        var isExec = false

        case kind
        of pcDir:
          nodeKind = fekDirectory
          tgtKind = fekDirectory
        of pcLinkToDir:
          nodeKind = fekSymlink
          tgtKind = fekDirectory
        of pcLinkToFile:
          nodeKind = fekSymlink
          tgtKind = fekFile
        of pcFile:
          nodeKind = fekFile
          tgtKind = fekFile
          try:
            let info = getFileInfo(childPath, followSymlink = false)
            isExec = fpUserExec in info.permissions or fpGroupExec in info.permissions
          except OSError:
            discard

        let node = FileTreeNode(
          name: name,
          path: normalizedPath(childPath),
          kind: nodeKind,
          depth: depth,
          isHidden: isHid,
          isExecutable: isExec,
          targetKind: tgtKind,
        )

        if nodeKind == fekDirectory or
            (nodeKind == fekSymlink and tgtKind == fekDirectory):
          dirs.add(node)
        else:
          files.add(node)
      except OSError as e:
        logWarn("filetree", "Cannot access: " & childPath & " (" & e.msg & ")")
  except OSError as e:
    let msg = "Cannot scan directory: " & path & " (" & e.msg & ")"
    logWarn("filetree", msg)
    error = msg

  # Sort: directories first, then files, both alphabetically
  dirs.sort(
    proc(a, b: FileTreeNode): int =
      cmpIgnoreCase(a.name, b.name)
  )
  files.sort(
    proc(a, b: FileTreeNode): int =
      cmpIgnoreCase(a.name, b.name)
  )

  result = dirs & files

proc isDirectory*(node: FileTreeNode): bool =
  node.kind == fekDirectory or
    (node.kind == fekSymlink and node.targetKind == fekDirectory)

proc isFile*(node: FileTreeNode): bool =
  node.kind == fekFile or (node.kind == fekSymlink and node.targetKind == fekFile)

proc getChildren(state: FileTreeState, path: string, depth: int): seq[FileTreeNode] =
  if path in state.childrenCache:
    result = newSeq[FileTreeNode](state.childrenCache[path].len)
    for i in 0 ..< result.len:
      result[i] = state.childrenCache[path][i]
      result[i].depth = depth
    return
  var err = ""
  let children = scanDirectory(path, depth, state.showHidden, err)
  if err.len > 0:
    state.lastError = err
  # Cache stores nodes with depth=0; getChildren overwrites depth on retrieval.
  var cached = children
  for i in 0 ..< cached.len:
    cached[i].depth = 0
  state.childrenCache[path] = cached
  return children

proc updateSearchMatches*(state: FileTreeState) =
  ## Update searchMatches based on searchText and current flatList.
  state.searchMatches = @[]
  if state.searchText.len == 0:
    state.searchMatchIndex = -1
    return
  let query = state.searchText.toLower()
  for i, node in state.flatList:
    if query in node.name.toLower():
      state.searchMatches.add(i)
  # Restore searchMatchIndex to the match closest to current selection
  state.searchMatchIndex = -1
  if state.searchMatches.len > 0:
    for j, matchIdx in state.searchMatches:
      if matchIdx >= state.selectedIndex:
        state.searchMatchIndex = j
        break
    if state.searchMatchIndex < 0:
      state.searchMatchIndex = state.searchMatches.high

proc buildFlatList*(state: FileTreeState) =
  ## Build flattened list of visible nodes from the tree, respecting expanded state.
  state.flatList = @[]
  var visited: HashSet[string]

  proc flatten(nodes: seq[FileTreeNode], state: FileTreeState) =
    for node in nodes:
      state.flatList.add(node)
      if node.isDirectory and node.path in state.expandedDirs:
        if node.path in visited:
          continue # Cyclic symlink — skip
        visited.incl(node.path)
        let children = state.getChildren(node.path, node.depth + 1)
        flatten(children, state)

  flatten(state.rootNodes, state)
  if state.searchText.len > 0:
    state.updateSearchMatches()

proc refreshTree*(state: FileTreeState) =
  ## Rescan the root directory and rebuild the flat list
  state.childrenCache.clear()
  var err = ""
  state.rootNodes = scanDirectory(state.rootPath, 0, state.showHidden, err)
  if err.len > 0:
    state.lastError = err
  state.buildFlatList()
  if state.selectedIndex >= state.flatList.len:
    state.selectedIndex = max(0, state.flatList.len - 1)
  state.needsBufferRefresh = true

proc newFileTreeState*(
    rootPath: string, width: int = DefaultFileTreeWidth
): FileTreeState =
  ## Create a new FileTreeState for the given directory
  let normalizedRootPath = normalizedPath(absolutePath(expandTilde(rootPath)))
  result = FileTreeState(
    rootPath: normalizedRootPath,
    rootNodes: @[],
    flatList: @[],
    selectedIndex: 0,
    topLine: 0,
    showHidden: false,
    expandedDirs: initHashSet[string](),
    needsBufferRefresh: true,
    width: width,
    childrenCache: initTable[string, seq[FileTreeNode]](),
  )
  result.refreshTree()

proc toggleExpand*(state: FileTreeState) =
  ## Toggle expand/collapse of the selected directory
  if state.selectedIndex >= 0 and state.selectedIndex < state.flatList.len:
    let node = state.flatList[state.selectedIndex]
    if node.isDirectory:
      if node.path in state.expandedDirs:
        state.expandedDirs.excl(node.path)
      else:
        state.expandedDirs.incl(node.path)
      state.buildFlatList()
      state.needsBufferRefresh = true

proc expandSelected*(state: FileTreeState) =
  ## Expand the selected directory (no-op if already expanded or is a file)
  if state.selectedIndex >= 0 and state.selectedIndex < state.flatList.len:
    let node = state.flatList[state.selectedIndex]
    if node.isDirectory and node.path notin state.expandedDirs:
      state.expandedDirs.incl(node.path)
      state.buildFlatList()
      state.needsBufferRefresh = true

proc collapseSelected*(state: FileTreeState) =
  ## Collapse the selected directory, or move to parent if file/already collapsed
  if state.selectedIndex >= 0 and state.selectedIndex < state.flatList.len:
    let node = state.flatList[state.selectedIndex]
    if node.isDirectory and node.path in state.expandedDirs:
      state.expandedDirs.excl(node.path)
      state.buildFlatList()
      state.needsBufferRefresh = true
    else:
      # Move to parent directory node
      let parentPath = parentDir(node.path)
      for i, n in state.flatList:
        if n.path == parentPath:
          state.selectedIndex = i
          state.needsBufferRefresh = true
          break

proc moveUp*(state: FileTreeState) =
  if state.flatList.len > 0 and state.selectedIndex > 0:
    dec state.selectedIndex

proc moveDown*(state: FileTreeState) =
  if state.flatList.len > 0 and state.selectedIndex < state.flatList.len - 1:
    inc state.selectedIndex

proc moveToFirst*(state: FileTreeState) =
  if state.flatList.len > 0:
    state.selectedIndex = 0
    state.topLine = 0

proc moveToLast*(state: FileTreeState) =
  if state.flatList.len > 0:
    state.selectedIndex = state.flatList.len - 1

proc moveToParent*(state: FileTreeState): bool =
  ## Jump to the parent directory node of the currently selected item.
  ## Returns true if the parent was found and cursor moved.
  if state.selectedIndex >= 0 and state.selectedIndex < state.flatList.len:
    let node = state.flatList[state.selectedIndex]
    let parentPath = parentDir(node.path)
    for i, n in state.flatList:
      if n.path == parentPath:
        state.selectedIndex = i
        return true
  return false

proc ensureSelectedVisible*(state: FileTreeState, viewportHeight: int) =
  let availableHeight = max(1, viewportHeight - 1)
  if state.selectedIndex < state.topLine:
    state.topLine = state.selectedIndex
  elif state.selectedIndex >= state.topLine + availableHeight:
    state.topLine = state.selectedIndex - availableHeight + 1

proc jumpToNextMatch*(state: FileTreeState, viewportHeight: int) =
  ## Jump to the next search match, wrapping around.
  if state.searchMatches.len == 0:
    return
  if state.searchMatchIndex < 0:
    state.searchMatchIndex = 0
  else:
    state.searchMatchIndex = (state.searchMatchIndex + 1) mod state.searchMatches.len
  state.selectedIndex = state.searchMatches[state.searchMatchIndex]
  state.ensureSelectedVisible(viewportHeight)
  state.needsBufferRefresh = true

proc jumpToPrevMatch*(state: FileTreeState, viewportHeight: int) =
  ## Jump to the previous search match, wrapping around.
  if state.searchMatches.len == 0:
    return
  if state.searchMatchIndex < 0:
    state.searchMatchIndex = state.searchMatches.len - 1
  else:
    state.searchMatchIndex =
      (state.searchMatchIndex - 1 + state.searchMatches.len) mod state.searchMatches.len
  state.selectedIndex = state.searchMatches[state.searchMatchIndex]
  state.ensureSelectedVisible(viewportHeight)
  state.needsBufferRefresh = true

proc jumpToFirstMatch*(state: FileTreeState, viewportHeight: int) =
  ## Jump to the first search match.
  if state.searchMatches.len == 0:
    return
  state.searchMatchIndex = 0
  state.selectedIndex = state.searchMatches[0]
  state.ensureSelectedVisible(viewportHeight)
  state.needsBufferRefresh = true

proc clearSearch*(state: FileTreeState) =
  ## Reset all search state.
  state.searchText = ""
  state.searchMatches = @[]
  state.searchMatchIndex = -1
  state.needsBufferRefresh = true

proc changeRoot*(state: FileTreeState) =
  ## Set the selected directory as the new root
  if state.selectedIndex >= 0 and state.selectedIndex < state.flatList.len:
    let node = state.flatList[state.selectedIndex]
    if node.isDirectory:
      state.rootPath = node.path
      state.expandedDirs.clear()
      state.selectedIndex = 0
      state.topLine = 0
      state.refreshTree()

proc moveRootUp*(state: FileTreeState) =
  ## Move root one directory up
  let parent = parentDir(state.rootPath)
  if parent.len > 0 and parent != state.rootPath:
    state.rootPath = parent
    state.expandedDirs.clear()
    state.selectedIndex = 0
    state.topLine = 0
    state.refreshTree()

proc toggleHidden*(state: FileTreeState) =
  state.showHidden = not state.showHidden
  state.refreshTree()

proc getSelectedPath*(state: FileTreeState): Option[string] =
  if state.selectedIndex >= 0 and state.selectedIndex < state.flatList.len:
    some(state.flatList[state.selectedIndex].path)
  else:
    none(string)

proc getSelectedNode*(state: FileTreeState): Option[FileTreeNode] =
  if state.selectedIndex >= 0 and state.selectedIndex < state.flatList.len:
    some(state.flatList[state.selectedIndex])
  else:
    none(FileTreeNode)

proc revealPath*(state: FileTreeState, filePath: string) =
  ## Expand ancestors and select the given file path in the tree
  let normPath = normalizedPath(absolutePath(filePath))

  # Only reveal paths within the root tree
  if not isRelativeTo(normPath, state.rootPath):
    return

  # Expand all ancestor directories
  var current = parentDir(normPath)
  while current.len > 0 and current != state.rootPath:
    state.expandedDirs.incl(current)
    current = parentDir(current)

  state.buildFlatList()

  # Select the target node
  for i, node in state.flatList:
    if node.path == normPath:
      state.selectedIndex = i
      break

  state.needsBufferRefresh = true

proc nodeToFileEntry(node: FileTreeNode): FileEntry =
  ## Convert a FileTreeNode to a FileEntry for pathToIcon reuse
  FileEntry(
    name: node.name,
    kind: node.kind,
    size: 0,
    modified: default(times.Time),
    isHidden: node.isHidden,
    isExecutable: node.isExecutable,
    targetKind: node.targetKind,
  )

proc truncateToWidth(text: string, maxWidth: int): string =
  ## Truncate a string to fit within maxWidth display columns.
  ## Adds "~" suffix if truncated.
  if maxWidth <= 0:
    return ""
  if displayWidth(text) <= maxWidth:
    return text
  var currentWidth = 0
  for r in text.runes:
    let w = runeWidth(r)
    if currentWidth + w >= maxWidth:
      result.add("~")
      return
    currentWidth += w
    result.add($r)

proc createFileTreeTextBuffer*(state: FileTreeState, showIcons: bool): TextBuffer =
  ## Create a TextBuffer from the flat list for rendering via normal view path.
  var content = ""
  var lines: seq[string] = @[]

  for i, node in state.flatList:
    let indent = repeat("  ", node.depth)

    let marker =
      if node.isDirectory:
        if node.path in state.expandedDirs: "▾ " else: "▸ "
      else:
        "  "

    let icon =
      if showIcons:
        pathToIcon(nodeToFileEntry(node))
      else:
        ""

    let name =
      if node.isDirectory:
        node.name & "/"
      else:
        node.name

    var line = indent & marker & icon & name
    if state.width > 0 and displayWidth(line) > state.width:
      line = truncateToWidth(line, state.width)
    lines.add(line)
    if i > 0:
      content.add('\n')
    content.add(line)

  if lines.len == 0:
    content = "(empty)"
    lines.add("(empty)")

  result = newTextBuffer(content)
  result.readOnly = true
  result.isUtilityBuffer = true
  result.highlightNeedsUpdate = false
  result.language = langNone
  result.filePath = some(state.rootPath)

  # Build custom highlight ColorSegments for entry-type coloring
  var segments: seq[ColorSegment] = @[]

  for i, node in state.flatList:
    let row = i
    let lineLen = max(0, lines[row].toRunes().high)
    let (colorIdx, style) =
      if node.kind == fekDirectory or
          (node.kind == fekSymlink and node.targetKind == fekDirectory):
        (
          EditorColorPairIndex.filerDirectory,
          getThemeStyle(EditorColorPairIndex.filerDirectory, {StyleModifier.Bold}),
        )
      elif node.kind == fekSymlink:
        (
          EditorColorPairIndex.filerSymlink,
          getThemeStyle(EditorColorPairIndex.filerSymlink),
        )
      elif node.isHidden:
        (
          EditorColorPairIndex.filerHiddenFile,
          getThemeStyle(EditorColorPairIndex.filerHiddenFile),
        )
      elif node.isExecutable:
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

  # Overwrite search result highlight on top of entry-type coloring
  if state.searchText.len > 0 and state.searchMatches.len > 0:
    let query = state.searchText.toLower()
    for matchIdx in state.searchMatches:
      let row = matchIdx
      let line = lines[row]
      let displayName =
        if state.flatList[matchIdx].isDirectory:
          state.flatList[matchIdx].name & "/"
        else:
          state.flatList[matchIdx].name
      let nameStartRune = line.runeLen - displayName.runeLen
      if nameStartRune < 0:
        # Line was truncated into the name — skip highlight
        continue
      let lineRuneHigh = line.runeLen - 1
      let nameStr = state.flatList[matchIdx].name.toLower()
      let matchRuneLen = query.runeLen
      var pos = nameStr.find(query)
      while pos >= 0:
        let runeOffset = nameStr[0 ..< pos].runeLen
        let firstCol = nameStartRune + runeOffset
        let lastCol = firstCol + matchRuneLen - 1
        if lastCol > lineRuneHigh:
          break # Match extends beyond visible (truncated) portion
        result.highlight.overwrite(
          ColorSegment(
            firstRow: row,
            firstColumn: firstCol,
            lastRow: row,
            lastColumn: lastCol,
            color: EditorColorPairIndex.searchResult,
            style: getThemeStyle(EditorColorPairIndex.searchResult),
          )
        )
        let nextStart = pos + query.len
        if nextStart >= nameStr.len:
          break
        let nextPos = nameStr.find(query, nextStart)
        if nextPos < 0:
          break
        pos = nextPos
