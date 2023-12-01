#[###################### GNU General Public License 3.0 ######################]#
#                                                                              #
#  Copyright (C) 2017─2023 Shuhei Nogawa                                       #
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

import std/[heapqueue, options]
import ui, editorview, gapbuffer, color, cursor, highlight, unicodeext,
       independentutils, settings

type
  SplitType* = enum
    ## vertical is default

    vertical = 0
    horizontal = 1

  WindowNode* = ref object
    ## WindowNode is N-Ary tree

    parent*: WindowNode
    child*: seq[WindowNode]
    splitType*: SplitType
    window*: Option[Window]
    view*: EditorView
    highlight*: Highlight
    cursor*: CursorPosition
    currentLine*, currentColumn*, expandedColumn*: int
    bufferIndex*: int
    windowIndex*: int
    index*: int   ## Index as seen by parent node
    y*, x*, h*, w*: int

  MainWindow* = object
    root*, currentMainWindowNode*: WindowNode
    numOfMainWindow*: int

proc newWindow(): Window {.inline.} =
  result = initWindow(1, 1, 0, 0, EditorColorPairIndex.default.ord)

proc initWindowNode*(): WindowNode =
  var
    node = WindowNode(
      child: @[],
      splitType: SplitType.vertical,
      window: some(newWindow()),
      h: 1,
      w: 1)
    root = WindowNode(
      child: @[node],
      splitType: SplitType.vertical,
      y: 0,
      x: 0,
      h: 1,
      w: 1)
  node.parent = root
  return root

proc initMainWindow*(): MainWindow =
  result.root = initWindowNode()
  result.currentMainWindowNode = result.root.child[0]
  result.numOfMainWindow = 1

proc verticalSplit*(n: var WindowNode, buffer: GapBuffer): WindowNode =
  var parent = n.parent

  if parent.splitType == SplitType.vertical:
    var node = WindowNode(
      parent: n.parent,
      child: @[],
      splitType: SplitType.vertical,
      window: some(newWindow()),
      view: initEditorView(buffer, 1, 1),
      highlight: n.highlight,
      bufferIndex: n.bufferIndex,
      h: 1,
      w: 1)

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
        window: some(newWindow()),
        view: initEditorView(buffer, 1, 1),
        highlight: n.highlight,
        bufferIndex: n.bufferIndex)
      node2 = WindowNode(
        parent: n,
        child: @[],
        splitType: SplitType.vertical,
        window: some(newWindow()),
        view: initEditorView(buffer, 1, 1),
        highlight: n.highlight,
        bufferIndex: n.bufferIndex)

    if parent.view.sidebar.isSome:
      node1.view.initSidebar
      node2.view.initSidebar

    n.splitType = SplitType.vertical
    n.windowIndex = -1
    n.child.add(node1)
    n.child.add(node2)
    n.window = none(Window)

    return node1

proc horizontalSplit*(n: var WindowNode, buffer: GapBuffer): WindowNode =
  var parent = n.parent

  if parent.splitType == SplitType.horizontal:
    var node = WindowNode(
      parent: parent,
      child: @[],
      splitType: SplitType.horizontal,
      window: some(newWindow()),
      view: initEditorView(buffer, 1, 1),
      highlight: n.highlight,
      bufferIndex: n.bufferIndex)

    if parent.child[^1].view.sidebar.isSome:
      node.view.initSidebar

    parent.child.add(node)

    return n
  # if parent is root and one window
  elif parent.parent == nil and parent.child.len == 1:
    var node = WindowNode(
      parent: n.parent,
      child: @[],
      splitType: SplitType.vertical,
      window: some(newWindow()),
      view: initEditorView(buffer, 1, 1),
      highlight: n.highlight,
      bufferIndex: n.bufferIndex)

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
        window: some(newWindow()),
        view: initEditorView(buffer, 1, 1),
        highlight: n.highlight,
        bufferIndex: n.bufferIndex)
      node2 = WindowNode(
        parent: n,
        child: @[],
        splitType: SplitType.vertical,
        window: some(newWindow()),
        view: initEditorView(buffer, 1, 1),
        highlight: n.highlight,
        bufferIndex: n.bufferIndex)

    if parent.view.sidebar.isSome:
      node1.view.initSidebar
      node2.view.initSidebar

    n.splitType = SplitType.horizontal
    n.windowIndex = -1
    n.child.add(node1)
    n.child.add(node2)
    n.window = none(Window)

    return node1

proc deleteWindowNode*(root: var WindowNode, windowIndex: int) =
  var qeue = initHeapQueue[WindowNode]()
  for node in root.child: qeue.push(node)

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
        for node in node.child: qeue.push(node)

proc resize*(root: var WindowNode, position: Position, size: Size) =
  root.y = position.y
  root.x = position.x
  root.w = size.w
  root.h = size.h

  var
    qeue = initHeapQueue[WindowNode]()
    windowIndex = 0

  const StatusBarLineHeight = 1

  for index, node in root.child:
    if root.splitType == SplitType.vertical:
      # Vertical split

      # Calc window width
      if root.w mod root.child.len != 0 and index == 0:
        node.w = int(root.w / root.child.len) + (root.w mod root.child.len)
      else: node.w = int(root.w / root.child.len)

      # Calc window x
      if root.w mod root.child.len != 0 and index > 0:
        node.x = root.x + (node.w * index) + (root.w mod root.child.len)
      else: node.x = root.x + (node.w * index)

      node.h = root.h
      node.y = root.y
    else:
      # Horizontal split

      # Calc window height
      if root.h mod root.child.len != 0 and index == 0:
        node.h = int(root.h / root.child.len) + (root.h mod root.child.len)
      else: node.h = int(root.h / root.child.len)

      # Calc window y
      if root.h mod root.child.len != 0 and index > 0:
        node.y = (node.h * index) + (root.h mod root.child.len) + root.y
      else: node.y = node.h * index + root.y

      node.w = root.w
      node.x = root.x

    if node.window.isSome:
      # Resize curses window
      node.window.get.resize(
        node.h - StatusBarLineHeight,
        node.w,
        node.y,
        node.x)

      # Set windowIndex
      node.windowIndex = windowIndex
      inc(windowIndex)

    ## Set index
    node.index = index

    if node.child.len > 0:
      for child in node.child: qeue.push(child)

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
        else: child.w = int(parent.w / parent.child.len)

        # Calc window x
        if parent.w mod parent.child.len != 0 and i > 0:
          child.x = parent.x + (child.w * i) + 1
        else: child.x = parent.x + (child.w * i)

        child.h = parent.h
        child.y = parent.y
      else:
        # Horizontal split

        # Calc window height
        if parent.h mod parent.child.len != 0 and i == 0:
          child.h = int(parent.h / parent.child.len) + 1
        else: child.h = int(parent.h / parent.child.len)

        # Calc window y
        if parent.h mod parent.child.len != 0 and i > 0:
          child.y = parent.y + (child.h * i) + 1
        else: child.y = parent.y + (child.h * i)

        child.w = parent.w
        child.x = parent.x

      if child.window.isSome:
        # Resize curses window
        child.window.get.resize(
          child.h - StatusBarLineHeight,
          child.w,
          child.y,
          child.x)
        # Set windowIndex
        child.windowIndex = windowIndex
        inc(windowIndex)

      # Set index
      for i, n in child.child: n.index = i

      if child.child.len > 0:
        for node in child.child: qeue.push(node)

proc searchByWindowIndex*(root: WindowNode, index: int): WindowNode =
  var qeue = initHeapQueue[WindowNode]()
  for node in root.child: qeue.push(node)

  while qeue.len > 0:
    for i in 0 ..< qeue.len:
      let node = qeue.pop
      if node.windowIndex == index: return node

      if node.child.len > 0:
        for node in node.child: qeue.push(node)

proc getAllWindowNode*(root: WindowNode): seq[WindowNode] =
  var qeue = initHeapQueue[WindowNode]()
  for node in root.child: qeue.push(node)

  while qeue.len > 0:
    for i in 0 ..< qeue.len:
      let node = qeue.pop
      if node.window.isSome: result.add(node)

      if node.child.len > 0:
        for node in node.child: qeue.push(node)

proc getAllBufferIndex*(root: WindowNode): seq[int]  =
  var qeue = initHeapQueue[WindowNode]()
  for node in root.child: qeue.push(node)

  while qeue.len > 0:
    for i in 0 ..< qeue.len:
      let node = qeue.pop
      if node.window.isSome:
        var exist = false
        for index in result:
          if index == node.bufferIndex:
            exist = true
            break
        if exist == false: result.add(node.bufferIndex)

      if node.child.len > 0:
        for node in node.child: qeue.push(node)

proc getMainWindowHeight*(settings: EditorSettings): int =
  let
    h = getTerminalHeight()
    tabHeight = if settings.tabLine.enable: 1 else: 0
    statusHeight = if settings.statusLine.enable: 1 else: 0
    commandHeight = if settings.statusLine.merge: 1 else: 0

  return h - tabHeight - statusHeight - commandHeight

proc countReferencedWindow*(root: WindowNode, bufferIndex: int): int =
  var qeue = initHeapQueue[WindowNode]()
  for node in root.child: qeue.push(node)

  while qeue.len > 0:
    for i in 0 ..< qeue.len:
      let node = qeue.pop
      if node.window.isSome and bufferIndex == node.bufferIndex: inc(result)

      if node.child.len > 0:
        for node in node.child: qeue.push(node)

proc absolutePosition*(
  windowNode: WindowNode,
  line, column: int): tuple[y, x: int] =
    ## Calculates the absolute position of (`line`, `column`).

    let (_, relativeY, relativeX) = windowNode.view.findCursorPosition(
      line,
      column)

    let
      y = windowNode.y + relativeY
      x =
        windowNode.x +
        relativeX +
        windowNode.view.widthOfLineNum +
        windowNode.view.sidebarWidth

    return (y, x)

proc absolutePosition*(node: WindowNode): tuple[y, x: int] {.inline.} =
  ## Calculates the absolute position of the current position.

  node.absolutePosition(node.currentLine, node.currentColumn)

proc rect*(node: WindowNode): WindowRect {.inline.} =
  Rect(y: node.y, x: node.x, w: node.w, h: node.h)

proc moveCursor*(node: var WindowNode, line, column: int) =
  if node.window.isSome:
    node.currentLine = line
    node.currentColumn = column
    node.window.get.move(line, column)
    node.window.get.refresh

proc moveCursor*(node: var WindowNode, position: BufferPosition) {.inline.} =
  node.moveCursor(position.line, position.column)

proc moveCursor*(node: var WindowNode) {.inline.} =
  if node.window.isSome:
    node.window.get.move(node.y, node.x)
    node.window.get.refresh

proc refreshWindow*(node: var WindowNode) {.inline.} =
  if node.window.isSome: node.window.get.refresh

proc getKey*(node: var WindowNode): Option[Rune] {.inline.} =
  ## Non-blocking read.

  if node.window.isSome:
    node.refreshWindow
    return getKey()

proc getKey*(node: var WindowNode, timeout: int): Option[Rune] {.inline.} =
  ## Non-blocking read.
  ## `timeout` is milliSeconds.

  if node.window.isSome:
    node.refreshWindow
    return getKey(timeout)

proc getKeyBlocking*(node: var WindowNode): Rune {.inline.} =
  ## Blocking read.

  if node.window.isSome:
    node.refreshWindow
    return getKeyBlocking()

proc eraseWindow*(node: var WindowNode) {.inline.} =
  if node.window.isSome: node.window.get.erase

proc getHeight*(node: var WindowNode): int {.inline.} = node.window.get.height

proc getWidth*(node: var WindowNode): int {.inline.} = node.window.get.width

proc bufferPosition*(windowNode: WindowNode): BufferPosition {.inline.} =
  ## Return the current position.

  BufferPosition(line: windowNode.currentLine, column: windowNode.currentColumn)
