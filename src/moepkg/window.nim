import heapqueue, terminal
import ui

type SplitType = enum
  vertical = 0
  horaizontal = 1

type MainWindowInfo* = ref object
  window*: Window
  bufferIndex*: int

type WindowNode* = ref object
  parent*: WindowNode
  child*: seq[WindowNode]
  splitType: SplitType
  mainWindowInfo*: MainWindowInfo
  windowIndex*: int
  y*: int
  x*: int
  h*: int
  w*: int

proc initWindowNode*(): WindowNode =
  var
    win = MainWindowInfo(window: initWindow(terminalHeight(), terminalWidth(), 0, 0, EditorColorPair.defaultChar), bufferIndex: 0)
    node = WindowNode(child: @[], splitType: SplitType.vertical, mainWindowInfo: win, h: terminalHeight(), w: terminalWidth())
    root = WindowNode(child: @[node], splitType: SplitType.vertical)
  node.parent = root

  node.mainWindowInfo.window.setTimeout()
  return root

proc verticalSplit*(n: var WindowNode) =
  var parent = n.parent
  
  if parent.splitType == SplitType.vertical:
    var
      win = MainWindowInfo(window: initWindow(terminalHeight(), terminalWidth(), 0, 0, EditorColorPair.defaultChar), bufferIndex: n.mainWindowInfo.bufferIndex)
      child = WindowNode(parent: parent, child: @[], splitType: SplitType.vertical, mainWindowInfo: win, h: terminalHeight(), w: terminalWidth())
    parent.child.add(child)
    #n = child
  else:
    var child = WindowNode(parent: n, child: @[], splitType: SplitType.vertical, h: terminalHeight(), w: terminalWidth())
    n.splitType = SplitType.vertical
    n.child.add(child)
    n.child.add(child)
    #n = child

proc horizeontlSplit*(n: var WindowNode) =
  var parent = n.parent

  if parent.splitType == SplitType.horaizontal:
    var child = WindowNode(parent: parent, child: @[], splitType: SplitType.horaizontal, h: terminalHeight(), w: terminalWidth())
    parent.child.add(child)
    n = child
  else:
    var child = WindowNode(parent: n, child: @[], splitType: SplitType.horaizontal, h: terminalHeight(), w: terminalWidth())
    n.splitType = SplitType.horaizontal
    n.child.add(child)
    n.child.add(child)
    n = child

proc resize*(root: WindowNode, height, width: int) =
  var qeue = initHeapQueue[WindowNode]()
  for index, node in root.child:
    if root.splitType == SplitType.vertical:
      node.w = int(width / root.child.len)
      node.x = node.w * index
    else:
      node.h = int(height / root.child.len)
      node.y = node.h * index
    qeue.push(node)

  while qeue.len > 0:
    for i in  0 ..< qeue.len:
      let
        child = qeue.pop
        parent = child.parent
      if parent.splitType == SplitType.vertical:
        child.w = int(width / parent.child.len)
        # Need fix
        child.x = parent.child[0].w * i
        child.y = parent.y
      else:
        child.h = int(height / child.parent.child.len)
        # Need fix
        child.y = parent.child[0].h * i
        child.x = parent.x

      if child.child.len > 0:
        for node in child.child: qeue.push(node)
    echo ""

proc searchByIndex*(root: WindowNode, index: int): WindowNode =
  var qeue = initHeapQueue[WindowNode]()
  for node in root.child: qeue.push(node)

  while qeue.len > 0:
    for i in  0 ..< qeue.len:
      let node = qeue.pop
      if node.windowIndex == index: return node

      if node.child.len > 0:
        for node in node.child: qeue.push(node)

proc getAllWindowInfo*(root: WindowNode): seq[MainWindowInfo] =
  var qeue = initHeapQueue[WindowNode]()
  for node in root.child: qeue.push(node)

  while qeue.len > 0:
    for i in  0 ..< qeue.len:
      let node = qeue.pop
      if node.mainWindowInfo != nil: result.add(node.mainWindowInfo)

      if node.child.len > 0:
        for node in node.child: qeue.push(node)
