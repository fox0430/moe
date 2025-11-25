#[###################### GNU General Public License 3.0 ######################]#
#                                                                              #
#  Copyright (C) 2017─2025 Shuhei Nogawa                                       #
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

import std/[heapqueue, options, strformat, strutils, tables]

import pkg/results

import
  ui, editorview, gapbuffer, color, cursor, highlight, unicodeext, independentutils,
  settings, undoredostack, folding, jumplist

type
  SplitType* = enum
    ## vertical is default
    vertical = 0
    horizontal = 1

  WindowNode* = ref object ## WindowNode is N-Ary tree
    parent*: WindowNode
    child*: seq[WindowNode]
    window*: Option[Window] # Only root node
    splitType*: SplitType
    view*: EditorView
    cursor*: CursorPosition
    jumpList*: JumpList
    currentLine*, currentColumn*, expandedColumn*: int
    bufferIndex*: int
    windowIndex*: int
    index*: int # Index as seen by parent node
    y*, x*, h*, w*: int

  MainWindow* = object
    root*, currentMainWindowNode*: WindowNode
    numOfMainWindow*: int

proc newWindow(): Result[Window, string] {.inline.} =
  return initWindow(1, 1, 0, 0, EditorColorPairIndex.default.ord)

proc initWindowNode*(): Result[WindowNode, string] =
  var win = newWindow()
  if win.isErr:
    return Result[WindowNode, string].err win.error

  var
    node = WindowNode(
      child: @[], splitType: SplitType.vertical, jumpList: initJumpList(), h: 1, w: 1
    )
    root = WindowNode(
      child: @[node],
      splitType: SplitType.vertical,
      window: some(win.get),
      jumpList: initJumpList(),
      y: 0,
      x: 0,
      h: 1,
      w: 1,
    )
  node.parent = root

  return Result[WindowNode, string].ok root

proc initMainWindow*(): Result[MainWindow, string] =
  var root = initWindowNode()
  if root.isErr:
    return Result[MainWindow, string].err root.error

  var mainWin = MainWindow()
  mainWin.root = root.get
  mainWin.currentMainWindowNode = root.get.child[0]
  mainWin.numOfMainWindow = 1

  return Result[MainWindow, string].ok mainWin

proc verticalSplit*[T](n: var WindowNode, buffer: T): WindowNode =
  var parent = n.parent

  if parent.splitType == SplitType.vertical:
    var node = WindowNode(
      parent: n.parent,
      child: @[],
      splitType: SplitType.vertical,
      view: initEditorView(buffer, 1, 1),
      jumpList: initJumpList(),
      bufferIndex: n.bufferIndex,
      h: 1,
      w: 1,
    )

    if n.view.foldingRanges.len > 0:
      node.view.foldingRanges = n.view.foldingRanges

    if parent.child[^1].view.sidebar.isSome:
      node.view.initSidebar

    parent.child.insert(node, n.index + 1)

    return n
  else:
    var
      node1 = WindowNode(
        parent: n,
        child: @[],
        splitType: SplitType.vertical,
        view: initEditorView(buffer, 1, 1),
        jumpList: initJumpList(),
        bufferIndex: n.bufferIndex,
      )
      node2 = WindowNode(
        parent: n,
        child: @[],
        splitType: SplitType.vertical,
        view: initEditorView(buffer, 1, 1),
        jumpList: initJumpList(),
        bufferIndex: n.bufferIndex,
      )

    if n.view.foldingRanges.len > 0:
      node1.view.foldingRanges = n.view.foldingRanges
      node2.view.foldingRanges = n.view.foldingRanges

    if parent.view.sidebar.isSome:
      node1.view.initSidebar
      node2.view.initSidebar

    n.splitType = SplitType.vertical
    n.windowIndex = -1
    n.child.add(node1)
    n.child.add(node2)
    n.window = none(Window)
    n.jumpList = initJumpList()

    return node1

proc horizontalSplit*[T](n: var WindowNode, buffer: T): WindowNode =
  var parent = n.parent

  if parent.splitType == SplitType.horizontal:
    var node = WindowNode(
      parent: parent,
      child: @[],
      splitType: SplitType.horizontal,
      view: initEditorView(buffer, 1, 1),
      jumpList: initJumpList(),
      bufferIndex: n.bufferIndex,
    )

    if n.view.foldingRanges.len > 0:
      node.view.foldingRanges = n.view.foldingRanges

    if parent.child[^1].view.sidebar.isSome:
      node.view.initSidebar

    parent.child.add(node)

    return n
  elif parent.parent == nil and parent.child.len == 1:
    # If parent is root and one window
    var node = WindowNode(
      parent: n.parent,
      child: @[],
      splitType: SplitType.vertical,
      view: initEditorView(buffer, 1, 1),
      jumpList: initJumpList(),
      bufferIndex: n.bufferIndex,
    )

    if n.view.foldingRanges.len > 0:
      node.view.foldingRanges = n.view.foldingRanges

    if parent.child[^1].view.sidebar.isSome:
      node.view.initSidebar

    n.parent.splitType = SplitType.horizontal
    n.parent.child.insert(node, n.index + 1)

    return n
  else:
    var
      node1 = WindowNode(
        parent: n,
        child: @[],
        splitType: SplitType.vertical,
        view: initEditorView(buffer, 1, 1),
        jumpList: initJumpList(),
        bufferIndex: n.bufferIndex,
      )
      node2 = WindowNode(
        parent: n,
        child: @[],
        splitType: SplitType.vertical,
        view: initEditorView(buffer, 1, 1),
        jumpList: initJumpList(),
        bufferIndex: n.bufferIndex,
      )

    if n.view.foldingRanges.len > 0:
      node1.view.foldingRanges = n.view.foldingRanges
      node2.view.foldingRanges = n.view.foldingRanges

    if parent.view.sidebar.isSome:
      node1.view.initSidebar
      node2.view.initSidebar

    n.splitType = SplitType.horizontal
    n.windowIndex = -1
    n.child.add(node1)
    n.child.add(node2)
    n.window = none(Window)
    n.jumpList = initJumpList()

    return node1

proc deleteWindowNode*(root: var WindowNode, windowIndex: int) =
  var qeue = initHeapQueue[WindowNode]()
  for node in root.child:
    qeue.push(node)

  var depth = 0
  while qeue.len > 0:
    depth.inc
    for i in 0 ..< qeue.len:
      let node = qeue.pop
      if node.windowIndex == windowIndex:
        var parent = node.parent
        let deleteIndex = node.index
        parent.child.delete(deleteIndex)

        if parent.child.len == 1 and depth > 1:
          let parentIndex = parent.index
          node.parent = parent.parent
          parent.parent.child[parentIndex] = node

        return

      if node.child.len > 0:
        for node in node.child:
          qeue.push(node)

template isActualWin*(n: WindowNode): bool =
  n.child.len == 0

proc getRootWindowNode*(n: WindowNode): WindowNode =
  result = n
  while not result.parent.isNil:
    result = result.parent

proc resize*(root: var WindowNode, position: Position, size: Size) =
  root.y = position.y
  root.x = position.x
  root.w = size.w
  root.h = size.h

  # Resize curses window
  root.window.get.resize(root.h, root.w, root.y, root.x)

  var
    qeue = initHeapQueue[WindowNode]()
    windowIndex = 0

  for index, node in root.child:
    if root.splitType == SplitType.vertical:
      # Vertical split

      # Calc window width
      if root.w mod root.child.len != 0 and index == 0:
        node.w = int(root.w / root.child.len) + (root.w mod root.child.len)
      else:
        node.w = int(root.w / root.child.len)

      # Calc window x
      if root.w mod root.child.len != 0 and index > 0:
        node.x = root.x + (node.w * index) + (root.w mod root.child.len)
      else:
        node.x = root.x + (node.w * index)

      node.h = root.h
    else:
      # Horizontal split

      # Calc window height
      if root.h mod root.child.len != 0 and index == 0:
        node.h = int(root.h / root.child.len) + (root.h mod root.child.len)
      else:
        node.h = int(root.h / root.child.len)

      # Calc window y
      if root.h mod root.child.len != 0 and index > 0:
        node.y = (node.h * index) + (root.h mod root.child.len)
      else:
        node.y = node.h * index

      node.w = root.w
      node.x = root.x

    if node.isActualWin:
      # Set windowIndex
      node.windowIndex = windowIndex
      inc(windowIndex)

    ## Set index
    node.index = index

    if node.child.len > 0:
      for child in node.child:
        qeue.push(child)

  while qeue.len > 0:
    for i in 0 ..< qeue.len:
      let
        child = qeue.pop
        parent = child.parent
      if parent.splitType == SplitType.vertical:
        # Vertical split

        # Calc window width
        if parent.w mod parent.child.len != 0 and i == 0:
          child.w = int(parent.w / parent.child.len) + 1
        else:
          child.w = int(parent.w / parent.child.len)

        # Calc window x
        if parent.w mod parent.child.len != 0 and i > 0:
          child.x = parent.x + (child.w * i) + 1
        else:
          child.x = parent.x + (child.w * i)

        child.h = parent.h
        child.y = parent.y
      else:
        # Horizontal split

        # Calc window height
        if parent.h mod parent.child.len != 0 and i == 0:
          child.h = int(parent.h / parent.child.len) + 1
        else:
          child.h = int(parent.h / parent.child.len)

        # Calc window y
        if parent.h mod parent.child.len != 0 and i > 0:
          child.y = parent.y + (child.h * i) + 1
        else:
          child.y = parent.y + (child.h * i)

        child.w = parent.w
        child.x = parent.x

      if child.child.len == 0:
        # Set windowIndex
        child.windowIndex = windowIndex
        inc(windowIndex)

      # Set index
      for i, n in child.child:
        n.index = i

      if child.child.len > 0:
        for node in child.child:
          qeue.push(node)

proc searchByWindowIndex*(root: WindowNode, index: int): WindowNode =
  var qeue = initHeapQueue[WindowNode]()
  for node in root.child:
    qeue.push(node)

  while qeue.len > 0:
    for i in 0 ..< qeue.len:
      let node = qeue.pop
      if node.windowIndex == index:
        return node

      if node.child.len > 0:
        for node in node.child:
          qeue.push(node)

proc searchByBufferIndex*(root: WindowNode, index: int): seq[WindowNode] =
  var qeue = initHeapQueue[WindowNode]()
  for node in root.child:
    qeue.push(node)

  while qeue.len > 0:
    for i in 0 ..< qeue.len:
      let node = qeue.pop
      if node.bufferIndex == index:
        result.add node

      if node.child.len > 0:
        for node in node.child:
          qeue.push(node)

proc getAllWindowNode*(root: WindowNode): seq[WindowNode] =
  var qeue = initHeapQueue[WindowNode]()
  for node in root.child:
    qeue.push(node)

  while qeue.len > 0:
    for i in 0 ..< qeue.len:
      let node = qeue.pop
      if node.isActualWin:
        result.add(node)

      if node.child.len > 0:
        for node in node.child:
          qeue.push(node)

proc findWindowByPosition*(root: WindowNode, y, x: int): Option[WindowNode] =
  ## Find the window node that contains the given screen coordinates.
  ## Returns none if no window contains the position.
  for node in root.getAllWindowNode:
    if y >= node.y and y < node.y + node.h and x >= node.x and x < node.x + node.w:
      return some(node)

  return none(WindowNode)

proc getAllBufferIndex*(root: WindowNode): seq[int] =
  var qeue = initHeapQueue[WindowNode]()
  for node in root.child:
    qeue.push(node)

  while qeue.len > 0:
    for i in 0 ..< qeue.len:
      let node = qeue.pop
      if node.isActualWin:
        var exist = false
        for index in result:
          if index == node.bufferIndex:
            exist = true
            break
        if exist == false:
          result.add(node.bufferIndex)

      if node.child.len > 0:
        for node in node.child:
          qeue.push(node)

proc getMainWindowHeight*(settings: EditorSettings): int =
  let
    h = getTerminalHeight()
    tabHeight = if settings.tabLine.enable: 1 else: 0
    statusHeight = if settings.statusLine.enable: 1 else: 0
    commandHeight = if settings.statusLine.merge: 1 else: 0

  return h - tabHeight - statusHeight - commandHeight

proc countReferencedWindow*(root: WindowNode, bufferIndex: int): int =
  var qeue = initHeapQueue[WindowNode]()
  for node in root.child:
    qeue.push(node)

  while qeue.len > 0:
    for i in 0 ..< qeue.len:
      let node = qeue.pop
      if node.isActualWin and bufferIndex == node.bufferIndex:
        inc(result)

      if node.child.len > 0:
        for node in node.child:
          qeue.push(node)

proc absolutePosition*(windowNode: WindowNode, line, column: int): tuple[y, x: int] =
  ## Calculates the absolute cursor position from line and column.

  let
    relativePosition = windowNode.view.findCursorPosition(line, column)
    root = windowNode.getRootWindowNode

    y = root.y + windowNode.y + relativePosition.y
    x =
      windowNode.x + relativePosition.x + windowNode.view.widthOfLineNum +
      windowNode.view.sidebarWidth

  return (y, x)

proc absolutePosition*(node: WindowNode): tuple[y, x: int] {.inline.} =
  ## Calculates the absolute position of the current position.

  node.absolutePosition(node.currentLine, node.currentColumn)

proc rect*(node: WindowNode): WindowRect {.inline.} =
  Rect(y: node.y, x: node.x, w: node.w, h: node.h)

proc moveCursor*(node: var WindowNode, y, x: int) =
  if node.isActualWin:
    node.cursor.y = y
    node.cursor.x = x

    var root = node.getRootWindowNode
    let
      cursorY =
        if node.y > 1:
          node.y + y
        else:
          y
      cursorX =
        if node.x > 0:
          node.x + x
        else:
          x
    root.window.get.moveCursor(cursorY, cursorX)
    root.window.get.noutrefresh

proc moveCursor*(node: var WindowNode, position: BufferPosition) {.inline.} =
  node.moveCursor(position.line, position.column)

proc moveCursor*(node: var WindowNode) =
  if node.isActualWin:
    node.moveCursor(node.y, node.x)

proc noutrefresh*(node: var WindowNode) =
  var root = node
  while not root.parent.isNil:
    root = root.parent

  root.window.get.noutrefresh

proc refresh*(node: var WindowNode) =
  var root = node
  while not root.parent.isNil:
    root = root.parent

  root.window.get.refresh

proc getKey*(node: var WindowNode): Option[Rune] {.inline.} =
  ## Non-blocking read.

  node.refresh
  return getKey()

proc getKey*(node: var WindowNode, timeout: int): Option[Rune] {.inline.} =
  ## Non-blocking read.
  ## `timeout` is milliSeconds.

  node.refresh
  return getKey(timeout)

proc getKeyBlocking*(node: var WindowNode): Rune {.inline.} =
  ## Blocking read.

  node.refresh
  return getKeyBlocking()

proc eraseWindow*(node: var WindowNode) {.inline.} =
  ## Erase ncurses window

  let
    nodeY = if node.y > 1: node.y else: 0
    nodeX = if node.x > 0: node.x else: 0

    # Node size without status line
    nodeSize = Size(h: node.view.height - 1, w: node.w)

  var root = node
  while not root.parent.isNil:
    root = root.parent

  for y in nodeY .. nodeY + nodeSize.h:
    root.window.get.write(
      y,
      nodeX,
      " ".repeat(nodeSize.w),
      EditorColorPairIndex.default.int16,
      Attribute.normal,
      false,
    )

proc getHeight*(node: var WindowNode): int {.inline.} =
  node.h

proc getWidth*(node: var WindowNode): int {.inline.} =
  node.w

proc bufferPosition*(windowNode: WindowNode): BufferPosition {.inline.} =
  ## Return the current position.

  BufferPosition(line: windowNode.currentLine, column: windowNode.currentColumn)

proc reloadEditorView*[T](node: var WindowNode, buffer: T) {.inline.} =
  node.view.reload(buffer, min(node.view.originalLine[0], buffer.high))

proc seekCursor*[T](node: var WindowNode, buffer: T) {.inline.} =
  node.view.seekCursor(buffer, node.currentLine, node.currentColumn)

proc revertPosition*(
    windowNode: var WindowNode, positionRecord: PositionRecord, id: int
) =
  let mess =
    fmt"The id not recorded was requested. [positionRecord = {positionRecord}, id = {id}]"
  doAssert(positionRecord.contains(id), mess)

  windowNode.currentLine = positionRecord[id].line
  windowNode.currentColumn = positionRecord[id].column
  windowNode.expandedColumn = positionRecord[id].expandedColumn

proc findFoldingRange*(n: WindowNode): Option[FoldingRange] {.inline.} =
  n.view.findFoldingRange(n.currentLine)

proc isFoldingStartLine*(n: WindowNode, line: int): bool {.inline.} =
  n.view.foldingRanges.isStartLine(line)

proc addFoldingRange*(n: var WindowNode, range: FoldingRange) {.inline.} =
  n.view.addFoldingRange(range)

proc addFoldingRange*(n: var WindowNode, firstLine, lastLine: int) {.inline.} =
  n.view.addFoldingRange(firstLine, lastLine)

proc removeFoldingRange*(n: var WindowNode) =
  let foldingRange = n.findFoldingRange
  if foldingRange.isSome:
    n.view.removeFoldingRange(foldingRange.get)

proc removeFoldingRange*(n: var WindowNode, line: int) =
  let foldingRange = n.view.findFoldingRange(line)
  if foldingRange.isSome:
    n.view.removeFoldingRange(foldingRange.get)

proc removeAllFoldingRange*(n: var WindowNode, line: int) =
  let foldingRange = n.view.findFoldingRange(line)
  if foldingRange.isSome:
    n.view.removeAllFoldingRange(foldingRange.get)

proc removeAllFoldingRange*(n: var WindowNode, range: FoldingRange) {.inline.} =
  n.view.removeAllFoldingRange(range)

proc removeAllFoldingRange*(n: var WindowNode, first, last: int) {.inline.} =
  n.view.removeAllFoldingRange(first, last)

proc clearFoldingRange*(n: var WindowNode) {.inline.} =
  n.view.clearFoldingRange

proc recordJump*(n: WindowNode, bufferId: int, path: Runes) {.inline.} =
  ## Add the current position to jumpList.

  n.jumpList.add(bufferId, path, n.bufferPosition)

proc jumpBack*(n: WindowNode): Option[JumpInfo] =
  ## Return the jumpInfo of the current history position.

  return n.jumpList.jumpBack

proc jumpFoward*(n: WindowNode): Option[JumpInfo] =
  ## Return the jumpInfo of the current history position.

  return n.jumpList.jumpFoward
