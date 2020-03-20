import heapqueue
import ui, editorview, gapbuffer

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
    node = WindowNode(child: @[], splitType: SplitType.vertical, window: win, h: 1, w: 1)
    root = WindowNode(child: @[node], splitType: SplitType.vertical, y: 0, x: 0, h: 1, w: 1)
  node.parent = root

  node.window.setTimeout()
  return root

proc newWindow(): Window =
  result = initWindow(1, 1, 0, 0, EditorColorPair.defaultChar)
  result.setTimeout()

proc verticalSplit*(n: var WindowNode, buffer: GapBuffer): WindowNode =
  var parent = n.parent
  
  if parent.splitType == SplitType.vertical:
    var
      view = initEditorView(buffer, 1, 1)
      win = newWindow()
      node = WindowNode(parent: n.parent, child: @[], splitType: SplitType.vertical, window: win, view: view, bufferIndex: n.bufferIndex, h: 1, w: 1)
    parent.child.add(node)
    return n
  else:
    var
      view1 = initEditorView(buffer, 1, 1)
      view2 = initEditorView(buffer, 1, 1)
      win1 = newWindow()
      win2 = newWindow()
      node1 = WindowNode(parent: n, child: @[], splitType: SplitType.vertical, window: win1, view: view1, bufferIndex: n.bufferIndex)
      node2 = WindowNode(parent: n, child: @[], splitType: SplitType.vertical, window: win2, view: view2, bufferIndex: n.bufferIndex)
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
      node = WindowNode(parent: parent, child: @[], splitType: SplitType.horaizontal, window: win, view: view, bufferIndex: n.bufferIndex)
    parent.child.add(node)
    return n
  # if parent is root and one window
  elif parent.parent == nil and parent.child.len == 1:
    var
      view = initEditorView(buffer, 1, 1)
      win = newWindow()
      node = WindowNode(parent: n.parent, child: @[], splitType: SplitType.vertical, window: win, view: view, bufferIndex: n.bufferIndex)
    n.parent.splitType = SplitType.horaizontal
    n.parent.child.insert(node, n.index + 1)
    return n
  else:
    var
      view1 = initEditorView(buffer, 1, 1)
      view2 = initEditorView(buffer, 1, 1)
      win1 = newWindow()
      win2 = newWindow()
      node1 = WindowNode(parent: n, child: @[], splitType: SplitType.vertical, window: win1, view: view1, bufferIndex: n.bufferIndex)
      node2 = WindowNode(parent: n, child: @[], splitType: SplitType.vertical, window: win2, view: view2, bufferIndex: n.bufferIndex)
    n.splitType = SplitType.horaizontal
    n.windowIndex = -1
    n.child.add(node1)
    n.child.add(node2)
    n.window = nil
    return node1

# Resize all window and reset index, windowIndex
proc resize*(root: WindowNode, y, x, height, width: int) =
  var qeue = initHeapQueue[WindowNode]()
  var windowIndex = 0

  if root.splitType == SplitType.vertical:
    for index, node in root.child:
      ## Calc window width
      if width mod root.child.len != 0 and index == 0: node.w = int(width / root.child.len) + width mod root.child.len
      else: node.w = int(width / root.child.len)

      ## Calc window x
      if index == 0: node.x = x
      else: node.x = root.child[index - 1].x + root.child[index - 1].w

      const commandWindowLine = 1
      node.h = height - commandWindowLine
      node.y = y

      if node.window != nil:
        ## Resize curses window
        node.window.resize(node.h, node.w, node.y, node.x)
        ## Set windowIndex
        node.windowIndex = windowIndex
        inc(windowIndex)

      ## Set index
      node.index = index

      if node.child.len > 0:
        for child in node.child: qeue.push(child)
  else:
    ## Horaizontal split
    for index, node in root.child:
      ## Calc window height
      let numOfStatusBarLine = root.child.len
      if (height - numOfStatusBarLine) mod root.child.len != 0 and index == 0:
        node.h = int((height - numOfStatusBarLine) / root.child.len) + (height - numOfStatusBarLine) mod root.child.len
      else: node.h = int((height - numOfStatusBarLine) / root.child.len)

      ## Calc window y
      if index == 0: node.y = y
      else:
        const blankLine = 1
        node.y = root.child[index - 1].y + root.child[index - 1].h + blankLine

      node.w = width
      node.x = x

      if node.window != nil:
        ## Resize curses window
        node.window.resize(node.h, node.w, node.y, node.x)
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
        ## Calc window width
        if parent.w mod parent.child.len != 0 and i == 0: child.w = int(parent.w / parent.child.len) + width mod parent.child.len
        else: child.w = int(parent.w / parent.child.len)

        ## Calc window x
        if i == 0: child.x = parent.x
        else: child.x = parent.child[i - 1].x + parent.child[i - 1].w

        child.h = parent.h
        child.y = parent.y
      else:
        ## Horaizontal split

        ## Calc window height
        let numOfStatusBarLine = parent.child.len
        ## +1 is blank line space
        let height = parent.h + 1
        if (height - numOfStatusBarLine) mod parent.child.len != 0 and i == 0:
          child.h = int((height - numOfStatusBarLine) / parent.child.len) + (height - numOfStatusBarLine) mod parent.child.len
        else: child.h = int((height - numOfStatusBarLine) / parent.child.len)

        ## Calc window y
        if i == 0: child.y = parent.y
        else:
          const blankLine = 1
          child.y = parent.child[i - 1].y + parent.child[i - 1].h + blankLine

        child.w = parent.w
        child.x = parent.x

      if child.window != nil:
        # Resize curses window
        child.window.resize(child.h, child.w, child.y, child.x)
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
