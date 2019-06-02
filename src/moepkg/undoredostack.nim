import sequtils, strformat

type
  CommandKind = enum
    insert,
    delete,
    assign
  
  Command*[T] = ref CommandObj[T]
  CommandObj*[T] = object
    case kind*: CommandKind
    of insert:
      insertElement*: T
      insertPosition*: int
    of delete:
      deleteElement*: T
      deletePosition*: int
    of assign:
      oldElement, newElement*: T
      assignPosition*: int

proc newInsertCommand*[T](element: T, position: int): Command[T] =
  new(result)
  result.kind = insert
  result.insertElement = element
  result.insertPosition = position

proc newDeleteCommand*[T](element: T, position: int): Command[T] =
  new(result)
  result.kind = delete
  result.deleteElement = element
  result.deletePosition = position

proc newAssignCommand*[T](oldElement, newElement: T, position: int): Command[T] =
  new(result)
  result.kind = assign
  result.oldElement = oldElement
  result.newElement = newElement
  result.assignPosition = position

proc doInsert[T, U](command: Command[T], buffer: var U, pushToStack: bool = true) =
  doAssert(command.kind == CommandKind.insert)
  buffer.insert(command.insertElement, command.insertPosition, pushToStack)

proc doDelete[T, U](command: Command[T], buffer: var U, pushToStack: bool = true) =
  doAssert(command.kind == CommandKind.delete)
  buffer.delete(command.deletePosition, pushToStack)

proc doAssign[T, U](command: Command[T], buffer: var U, pushToStack: bool = true) =
  doAssert(command.kind == CommandKind.assign)
  buffer.assign(command.newElement, command.assignPosition, pushToStack)

proc doCommand[T, U](command: Command[T], buffer: var U, pushToStack: bool = true) =
  case command.kind:
  of insert: doInsert(command, buffer, pushToStack)
  of delete: doDelete(command, buffer, pushToStack)
  of assign: doAssign(command, buffer, pushToStack)

proc inverseOfInsert[T](command: Command[T]): Command[T] =
  doAssert(command.kind == CommandKind.insert)
  return newDeleteCommand[T](command.insertElement, command.insertPosition)

proc inverseOfDelete[T](command: Command[T]): Command[T] =
  doAssert(command.kind == CommandKind.delete)
  return newInsertCommand[T](command.deleteElement, command.deletePosition)

proc inverseOfAssign[T](command: Command[T]): Command[T] =
  doAssert(command.kind == CommandKind.assign)
  return newAssignCommand[T](command.newElement, command.oldElement, command.assignPosition)

proc inverseCommand[T](command: Command[T]): Command[T] =
  case command.kind:
  of delete: inverseOfDelete(command)
  of insert: inverseOfInsert(command)
  of assign: inverseOfAssign(command)

type UndoRedoStack*[T] = object
  nextCommandIndex: int
  commands: seq[Command[T]]

proc initUndoRedoStack*[T](): UndoRedoStack[T] =
  result.nextCommandIndex = -1

proc push*[T](undoRedoStack: var UndoRedoStack[T], command: Command[T]) =
  if undoRedoStack.commands.len > 0: undoRedoStack.commands.delete(undoRedoStack.nextCommandIndex, undoRedoStack.commands.high)
  undoRedoStack.commands.add(command)
  undoRedoStack.nextCommandIndex = undoRedoStack.commands.len
  write(stderr, $command.kind)
  write(stderr, $undoRedoStack.nextCommandIndex)

proc undo*[T, U](undoRedoStack: var UndoRedoStack[T], buffer: var U) =
  doAssert(undoRedoStack.nextCommandIndex > 0)
  dec(undoRedoStack.nextCommandIndex)
  doCommand[T,U](inverseCommand[T](undoRedoStack.commands[undoRedoStack.nextCommandIndex]), buffer, false)

proc redo*[T, U](undoRedoStack: var UndoRedoStack[T], buffer: var U) =
  doAssert(undoRedoStack.nextCommandIndex < undoRedoStack.commands.len)
  doCommand[T, U](undoRedoStack.commands[undoRedoStack.nextCommandIndex], buffer, false)
  inc(undoRedoStack.nextCommandIndex)

proc canUndo*[T](undoRedoStack: UndoRedoStack[T]): bool = undoRedoStack.nextCommandIndex > 0

proc canRedo*[T](undoRedoStack: UndoRedoStack[T]): bool = 0 <= undoRedoStack.nextCommandIndex-1 and undoRedoStack.nextCommandIndex < undoRedoStack.commands.len