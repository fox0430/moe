import heapqueue, terminal
import ui, editorview, gapbuffer

# vertical is default
type SplitType* = enum
  vertical = 0
  horaizontal = 1

type WindowNode* = ref object
  parent*: WindowNode
  child*: seq[WindowNode]
  splitType*: SplitType
  window*: Window
  view*: EditorView
  bufferIndex*: int
  windowIndex*: int
  index*: int
  y*: int
  x*: int
  h*: int
  w*: int

proc initWindowNode*(): WindowNode =
  var
    win = initWindow(terminalHeight(), terminalWidth(), 0, 0, EditorColorPair.defaultChar)
    node = WindowNode(child: @[], splitType: SplitType.vertical, window: win, bufferIndex: 0, h: terminalHeight(), w: terminalWidth())
    root = WindowNode(child: @[node], splitType: SplitType.vertical, y: 0, x: 0, h: terminalHeight(), w: terminalWidth())
  node.parent = root

  node.window.setTimeout()
  return root

proc newWindow(): Window =
  result = initWindow(terminalHeight(), terminalWidth(), 0, 0, EditorColorPair.defaultChar)
  result.setTimeout()

proc verticalSplit*(n: var WindowNode, buffer: GapBuffer, numOfWindow: int): WindowNode =
  var parent = n.parent
  
  if parent.splitType == SplitType.vertical:
    var
      view = initEditorView(buffer, terminalHeight(), terminalWidth())
      win = newWindow()
      node = WindowNode(parent: n.parent, child: @[], splitType: SplitType.vertical, window: win, view: view, bufferIndex: n.bufferIndex, windowIndex: numOfWindow, h: terminalHeight(), w: terminalWidth())
    parent.child.add(node)
    return n
  else:
    var
      view1 = initEditorView(buffer, terminalHeight(), terminalWidth())
      view2 = initEditorView(buffer, terminalHeight(), terminalWidth())
      win1 = newWindow()
      win2 = newWindow()
      node1 = WindowNode(parent: n, child: @[], splitType: SplitType.vertical, h: terminalHeight(), window: win1, view: view1, bufferIndex: n.bufferIndex, windowIndex: numOfWindow, w: terminalWidth())
      node2 = WindowNode(parent: n, child: @[], splitType: SplitType.vertical, h: terminalHeight(), window: win2, view: view2, bufferIndex: n.bufferIndex, windowIndex: numOfWindow + 1, w: terminalWidth())
    n.splitType = SplitType.vertical
    n.windowIndex = -1
    n.child.add(node1)
    n.child.add(node2)
    n.window = nil
    return node1

proc horizontalSplit*(n: var WindowNode, buffer: GapBuffer, numOfWindow: int): WindowNode =
  var parent = n.parent

  if parent.splitType == SplitType.horaizontal:
    var
      view = initEditorView(buffer, terminalHeight(), terminalWidth())
      win = newWindow()
      node = WindowNode(parent: parent, child: @[], splitType: SplitType.horaizontal, window: win, view: view, bufferIndex: n.bufferIndex, windowIndex: numOfWindow, h: 0, w: 0)
    parent.child.add(node)
    return n
  # if parent is root and one window
  elif parent.parent == nil and parent.child.len == 1:
    var
      view = initEditorView(buffer, terminalHeight(), terminalWidth())
      win = newWindow()
      node = WindowNode(parent: n, child: @[], splitType: SplitType.vertical, h: terminalHeight(), window: win, view: view, bufferIndex: n.bufferIndex, windowIndex: numOfWindow, w: terminalWidth())
    n.parent.splitType = SplitType.horaizontal
    n.parent.child.insert(node, n.index + 1)
    return n
  else:
    var
      view1 = initEditorView(buffer, terminalHeight(), terminalWidth())
      view2 = initEditorView(buffer, terminalHeight(), terminalWidth())
      win1 = newWindow()
      win2 = newWindow()
      node1 = WindowNode(parent: n, child: @[], splitType: SplitType.vertical, h: terminalHeight(), window: win1, view: view1, bufferIndex: n.bufferIndex, windowIndex: numOfWindow, w: terminalWidth())
      node2 = WindowNode(parent: n, child: @[], splitType: SplitType.vertical, h: terminalHeight(), window: win2, view: view2, bufferIndex: n.bufferIndex, windowIndex: numOfWindow, w: terminalWidth())
    n.splitType = SplitType.horaizontal
    n.windowIndex = -1
    n.child.add(node1)
    n.child.add(node2)
    n.window = nil
    return node1

# TODO: Add arg y and x
proc resize*(root: WindowNode, height, width: int) =
  var qeue = initHeapQueue[WindowNode]()
  for index, node in root.child:
    if root.splitType == SplitType.vertical:
      if width mod root.child.len != 0 and index == 0: node.w = int(width / root.child.len) + 1
      else: node.w = int(width / root.child.len)

      if width mod root.child.len != 0 and index > 0: node.x = (node.w * index) + 1
      else: node.x = node.w * index

      node.h = height
    else:
      if height mod root.child.len != 0 and index == 0: node.h = int(height / root.child.len) + 1
      else: node.h = int(height / root.child.len)

      if height mod root.child.len != 0 and index > 0: node.y = (node.h * index) + 1
      else: node.y = node.h * index

      node.w = width
    if node.child.len > 0:
      for child in node.child: qeue.push(child)

  while qeue.len > 0:
    for i in 0 ..< qeue.len:
      let
        child = qeue.pop
        parent = child.parent
      if parent.splitType == SplitType.vertical:
        if parent.w mod parent.child.len != 0 and i == 0: child.w = int(parent.w / parent.child.len) + 1
        else: child.w = int(parent.w / parent.child.len)

        if parent.w mod parent.child.len != 0 and i > 0: child.x = parent.x + (child.w * i) + 1
        else: child.x = parent.x + (child.w * i)

        child.h = parent.h
        child.y = parent.y
      else:
        if parent.h mod parent.child.len != 0 and i == 0: child.h = int(parent.h / parent.child.len) + 1
        else: child.h = int(parent.h / parent.child.len)

        if parent.h mod parent.child.len != 0 and i > 0: child.y = parent.y + (child.h * i) + 1
        else: child.y = parent.y + (child.h * i)

        child.w = parent.w
        child.x = parent.x

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

proc getAllBufferIndex*(root: WindowNode): seq[int]  =
  var qeue = initHeapQueue[WindowNode]()
  for node in root.child: qeue.push(node)

  while qeue.len > 0:
    for i in 0 ..< qeue.len:
      let node = qeue.pop
      if node.window != nil: result.add(node.bufferIndex)

      if node.child.len > 0:
        for node in node.child: qeue.push(node)

proc resetIndex*(root: WindowNode) =
  var qeue = initHeapQueue[WindowNode]()
  for node in root.child: qeue.push(node)

  while qeue.len > 0:
    for i in 0 ..< qeue.len:
      let node = qeue.pop
      for index, child in node.child: child.index = index

      if node.child.len > 0:
        for node in node.child: qeue.push(node)

proc resetWindowIndex*(root: WindowNode) =
  var qeue = initHeapQueue[WindowNode]()
  for node in root.child: qeue.push(node)

  var index = 0
  while qeue.len > 0:
    for i in  0 ..< qeue.len:
      let node = qeue.pop
      if node.window != nil:
        node.windowIndex = index
        inc(index)

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

proc getAllWindowNode*(root: WindowNode) =
  var qeue = initHeapQueue[WindowNode]()
  for node in root.child: qeue.push(node)

  exitUi()
  echo "start get window node"
  while qeue.len > 0:
    for i in 0 ..< qeue.len:
      let node = qeue.pop
      echo node.splitType
      echo node.child.len
      if node.window == nil: echo "nil" else: echo "active"
      echo ""

      if node.child.len > 0:
        for node in node.child: qeue.push(node)
