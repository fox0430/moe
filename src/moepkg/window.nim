import heapqueue
import ui, editorview, gapbuffer, color, cursor, highlight

# vertical is default
type SplitType* = enum
  vertical = 0
  horaizontal = 1

## WindowNode is N-Ary tree
type WindowNode* = ref object
  parent*: WindowNode
  child*: seq[WindowNode]
  splitType*: SplitType
  window*: Window
  view*: EditorView
  highlight*: Highlight
  cursor*: CursorPosition
  currentLine*: int
  currentColumn*: int
  expandedColumn*: int
  bufferIndex*: int
  windowIndex*: int
  index*: int   ## Index as seen by parent node
  y*: int
  x*: int
  h*: int
  w*: int

proc initWindowNode*(): WindowNode =
  var
    win = initWindow(1, 1, 0, 0, EditorColorPair.defaultChar)
    node = WindowNode(child: @[],
                      splitType: SplitType.vertical,
                      window: win,
                      h: 1,
                      w: 1)
    root = WindowNode(child: @[node],
                      splitType: SplitType.vertical,
                      y: 0,
                      x: 0,
                      h: 1,
                      w: 1)
  node.parent = root

  node.window.setTimeout()
  return root

proc newWindow(): Window {.inline.} =
  result = initWindow(1, 1, 0, 0, EditorColorPair.defaultChar)
  result.setTimeout()

proc verticalSplit*(n: var WindowNode, buffer: GapBuffer): WindowNode =
  var parent = n.parent

  if parent.splitType == SplitType.vertical:
    var
      view = initEditorView(buffer, 1, 1)
      win = newWindow()
      node = WindowNode(parent: n.parent,
                        child: @[],
                        splitType: SplitType.vertical,
                        window: win,
                        view: view,
                        highlight: n.highlight,
                        bufferIndex: n.bufferIndex,
                        h: 1,
                        w: 1)
    parent.child.insert(node, n.index + 1)
    return n
  else:
    var
      view1 = initEditorView(buffer, 1, 1)
      view2 = initEditorView(buffer, 1, 1)
      win1 = newWindow()
      win2 = newWindow()
      node1 = WindowNode(parent: n,
                         child: @[],
                         splitType: SplitType.vertical,
                         window: win1,
                         view: view1,
                         highlight: n.highlight,
                         bufferIndex: n.bufferIndex)
      node2 = WindowNode(parent: n,
                         child: @[],
                         splitType: SplitType.vertical,
                         window: win2,
                         view: view2,
                         highlight: n.highlight,
                         bufferIndex: n.bufferIndex)
    n.splitType = SplitType.vertical
    n.windowIndex = -1
    n.child.add(node1)
    n.child.add(node2)
    n.window = nil
    return node1

proc horizontalSplit*(n: var WindowNode, buffer: GapBuffer): WindowNode =
  var parent = n.parent

  if parent.splitType == SplitType.horaizontal:
    var
      view = initEditorView(buffer, 1, 1)
      win = newWindow()
      node = WindowNode(parent: parent,
                        child: @[],
                        splitType: SplitType.horaizontal,
                        window: win,
                        view: view,
                        highlight: n.highlight,
                        bufferIndex: n.bufferIndex)
    parent.child.add(node)
    return n
  # if parent is root and one window
  elif parent.parent == nil and parent.child.len == 1:
    var
      view = initEditorView(buffer, 1, 1)
      win = newWindow()
      node = WindowNode(parent: n.parent,
                        child: @[],
                        splitType: SplitType.vertical,
                        window: win,
                        view: view,
                        highlight: n.highlight,
                        bufferIndex: n.bufferIndex)
    n.parent.splitType = SplitType.horaizontal
    n.parent.child.insert(node, n.index + 1)
    return n
  else:
    var
      view1 = initEditorView(buffer, 1, 1)
      view2 = initEditorView(buffer, 1, 1)
      win1 = newWindow()
      win2 = newWindow()
      node1 = WindowNode(
                         parent: n,
                         child: @[],
                         splitType: SplitType.vertical,
                         window: win1,
                         view: view1,
                         highlight: n.highlight,
                         bufferIndex: n.bufferIndex)
      node2 = WindowNode(parent: n,
                         child: @[],
                         splitType: SplitType.vertical,
                         window: win2,
                         view: view2,
                         highlight: n.highlight,
                         bufferIndex: n.bufferIndex)
    n.splitType = SplitType.horaizontal
    n.windowIndex = -1
    n.child.add(node1)
    n.child.add(node2)
    n.window = nil
    return node1

proc resize*(root: WindowNode, y, x, height, width: int) =
  var
    qeue = initHeapQueue[WindowNode]()
    windowIndex = 0
  const statusBarLineHeight = 1

  for index, node in root.child:
    if root.splitType == SplitType.vertical:
      ## Vertical split

      ## Calc window width
      if width mod root.child.len != 0 and index == 0:
        node.w = int(width / root.child.len) + (width mod root.child.len)
      else: node.w = int(width / root.child.len)

      ## Calc window x
      if width mod root.child.len != 0 and index > 0:
        node.x = (node.w * index) + (width mod root.child.len)
      else: node.x = node.w * index

      node.h = height
      node.y = y
    else:
      ## Horaizontal split

      ## Calc window height
      if height mod root.child.len != 0 and index == 0:
        node.h = int(height / root.child.len) + (height mod root.child.len)
      else: node.h = int(height / root.child.len)

      ## Calc window y
      if height mod root.child.len != 0 and index > 0:
        node.y = (node.h * index) + (height mod root.child.len) + y
      else: node.y = node.h * index + y

      node.w = width
      node.x = x

    if node.window != nil:
      ## Resize curses window
      node.window.resize(node.h - statusBarLineHeight, node.w, node.y, node.x)
      ## Set windowIndex
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
        ## Vertical split

        ## Calc window width
        if parent.w mod parent.child.len != 0 and i == 0:
          child.w = int(parent.w / parent.child.len) + 1
        else: child.w = int(parent.w / parent.child.len)

        ## Calc window x
        if parent.w mod parent.child.len != 0 and i > 0:
          child.x = parent.x + (child.w * i) + 1
        else: child.x = parent.x + (child.w * i)

        child.h = parent.h
        child.y = parent.y
      else:
        ## Horaizontal split

        ## Calc window height
        if parent.h mod parent.child.len != 0 and i == 0:
          child.h = int(parent.h / parent.child.len) + 1
        else: child.h = int(parent.h / parent.child.len)

        ## Calc window y
        if parent.h mod parent.child.len != 0 and i > 0:
          child.y = parent.y + (child.h * i) + 1
        else: child.y = parent.y + (child.h * i)

        child.w = parent.w
        child.x = parent.x

      if child.window != nil:
        # Resize curses window
        child.window.resize(
          child.h - statusBarLineHeight,
          child.w,
          child.y,
          child.x)
        # Set windowIndex
        child.windowIndex = windowIndex
        inc(windowIndex)

      ## Set index
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
      if node.window != nil: result.add(node)

      if node.child.len > 0:
        for node in node.child: qeue.push(node)

proc getAllBufferIndex*(root: WindowNode): seq[int]  =
  var qeue = initHeapQueue[WindowNode]()
  for node in root.child: qeue.push(node)

  while qeue.len > 0:
    for i in 0 ..< qeue.len:
      let node = qeue.pop
      if node.window != nil:
        var exist = false
        for index in result:
          if index == node.bufferIndex:
            exist = true
            break
        if exist == false: result.add(node.bufferIndex)

      if node.child.len > 0:
        for node in node.child: qeue.push(node)

proc countReferencedWindow*(root: WindowNode, bufferIndex: int): int =
  var qeue = initHeapQueue[WindowNode]()
  for node in root.child: qeue.push(node)

  while qeue.len > 0:
    for i in 0 ..< qeue.len:
      let node = qeue.pop
      if node.window != nil and bufferIndex == node.bufferIndex: inc(result)

      if node.child.len > 0:
        for node in node.child: qeue.push(node)

proc absolutePosition*(windowNode: WindowNode,
                       line, column: int): tuple[y, x: int] =

  ## Calculates the absolute position of (`line`, `column`).
  let (_, relativeY, relativeX) = windowNode.view.findCursorPosition(line, column)
  return (windowNode.y + relativeY, windowNode.x + relativeX + windowNode.view.widthOfLineNum)
