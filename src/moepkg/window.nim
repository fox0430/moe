import heapqueue, terminal
import ui

type SplitType = enum
  vertical = 0
  horaizontal = 1

type WindowNode* = ref object
  parent*: WindowNode
  child*: seq[WindowNode]
  splitType: SplitType
  window*: Window
  bufferIndex*: int
  windowIndex*: int
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

proc verticalSplit*(n: var WindowNode): WindowNode =
  var parent = n.parent
  
  var win = initWindow(terminalHeight(), terminalWidth(), 0, 0, EditorColorPair.defaultChar)
  win.setTimeout()
  if parent.splitType == SplitType.vertical:
    var child = WindowNode(parent: parent, child: @[], splitType: SplitType.vertical, window: win, bufferIndex: n.bufferIndex, h: terminalHeight(), w: terminalWidth())
    parent.child.add(child)
    return child
  else:
    var
      win1 = initWindow(terminalHeight(), terminalWidth(), 0, 0, EditorColorPair.defaultChar)
      win2 = initWindow(terminalHeight(), terminalWidth(), 0, 0, EditorColorPair.defaultChar)
      newNode1 = WindowNode(parent: n, child: @[], splitType: SplitType.vertical, h: terminalHeight(), window: win1, bufferIndex: n.bufferIndex, w: terminalWidth())
      newNode2 = WindowNode(parent: n, child: @[], splitType: SplitType.vertical, h: terminalHeight(), window: win2, bufferIndex: n.bufferIndex, w: terminalWidth())
    win1.setTimeout()
    win2.setTimeout()
    n.splitType = SplitType.vertical
    n.child.add(newNode1)
    n.child.add(newNode2)
    n.window = nil
    return newNode1

proc horizontalSplit*(n: var WindowNode): WindowNode =
  var parent = n.parent

  var win = initWindow(terminalHeight(), terminalWidth(), 0, 0, EditorColorPair.defaultChar)
  win.setTimeout()

  if parent.splitType == SplitType.horaizontal:
    var child = WindowNode(parent: parent, child: @[], splitType: SplitType.horaizontal, window: win, bufferIndex: n.bufferIndex, h: 0, w: 0)
    parent.child.add(child)
    return child
  else:
    var
      win1 = initWindow(terminalHeight(), terminalWidth(), 0, 0, EditorColorPair.defaultChar)
      win2 = initWindow(terminalHeight(), terminalWidth(), 0, 0, EditorColorPair.defaultChar)
      newNode1 = WindowNode(parent: n, child: @[], splitType: SplitType.vertical, h: terminalHeight(), window: win1, bufferIndex: n.bufferIndex, w: terminalWidth())
      newNode2 = WindowNode(parent: n, child: @[], splitType: SplitType.vertical, h: terminalHeight(), window: win2, bufferIndex: n.bufferIndex, w: terminalWidth())
    win1.setTimeout()
    win2.setTimeout()
    n.splitType = SplitType.horaizontal
    n.child.add(newNode1)
    n.child.add(newNode2)
    n.window = nil
    return newNode1

proc resize*(root: WindowNode, height, width: int) =
  var qeue = initHeapQueue[WindowNode]()
  for index, node in root.child:
    if root.splitType == SplitType.vertical:
      node.h = terminalHeight()
      node.w = int(width / root.child.len)
      node.x = node.w * index
    else:
      node.h = int(height / root.child.len)
      node.w = terminalWidth()
      node.y = node.h * index
    if node.child.len > 0: qeue.push(node)

  while qeue.len > 0:
    for i in  0 ..< qeue.len:
      let
        child = qeue.pop
        parent = child.parent
      if parent.splitType == SplitType.vertical:
        child.w = int(width / parent.child.len)
        child.h = parent.h
        # Need fix
        child.x = parent.child[0].w * i
        child.y = parent.y
      else:
        child.h = int(height / child.parent.child.len)
        child.w = parent.w
        # Need fix
        child.y = parent.child[0].h * i
        child.x = parent.x

      if child.child.len > 0:
        for node in child.child: qeue.push(node)

proc searchByIndex*(root: WindowNode, index: int): WindowNode =
  var qeue = initHeapQueue[WindowNode]()
  for node in root.child: qeue.push(node)

  while qeue.len > 0:
    for i in  0 ..< qeue.len:
      let node = qeue.pop
      if node.windowIndex == index: return node

      if node.child.len > 0:
        for node in node.child: qeue.push(node)

proc getAllBufferIndex*(root: WindowNode): seq[int]  =
  var qeue = initHeapQueue[WindowNode]()
  for node in root.child: qeue.push(node)

  while qeue.len > 0:
    for i in  0 ..< qeue.len:
      let node = qeue.pop
      if node.window != nil: result.add(node.bufferIndex)

      if node.child.len > 0:
        for node in node.child: qeue.push(node)
