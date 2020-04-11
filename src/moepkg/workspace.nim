import window

type WorkSpace* = object
  mainWindowNode*: WindowNode
  currentMainWindowNode*: WindowNode
  numOfMainWindow*: int

proc initWorkSpace*(): WorkSpace =
  var rootNode = initWindowNode()
  result.mainWindowNode = rootNode
  result.currentMainWindowNode = rootNode.child[0]
  result.numOfMainWindow = 1

