import sequtils, strformat

type
  CommandKind = enum
    add,
    insert,
    delete,
    assign
  
  Command*[T] = ref CommandObj[T]
  CommandObj*[T] = object
    case kind*: CommandKind
    of add:
      addElement*: T
    of insert:
      insertElement*: T
      insertPosition*: int
    of delete:
      first*, last*: int
    of assign:
      oldElement, newElement*: T
      assignPosition*: int

proc newAddCommand*[T](element: T): Command[T] =
  new(result)
  result.kind = add
  result.addElement = element

proc newInsertCommand*[T](element: T, position: int): Command[T] =
  new(result)
  result.kind = insert
  result.insertElement = element
  result.insertPosition = position

proc newDeleteCommand*[T](first, last: int): Command[T] =
  new(result)
  result.kind = delete
  result.first = first
  result.last = last

proc newAssignCommand*[T](oldElement, newElement: T, position: int): Command[T] =
  new(result)
  result.kind = assign
  result.oldElement = oldElement
  result.newElement = newElement
  result.assignPosition = position

proc doAdd[T, U](command: Command[T], buffer: var U) =
  doAssert(command.kind == CommandKind.add)
  buffer.add(command.addElement)

proc doInsert[T, U](command: Command[T], buffer: var U) =
  doAssert(command.kind == CommandKind.insert)
  buffer.insert(command.insertElement, command.insertPosition)

proc doDelete[T, U](command: Command[T], buffer: var U) =
  doAssert(command.kind == CommandKind.delete)
  buffer.delete(command.first, command.last)

proc doAssign[T, U](command: Command[T], buffer: var U) =
  doAssert(command.kind == CommandKind.assign)
  buffer.assign(command.newElement, command.assignPosition)

proc doCommand[T, U](command: Command[T], buffer: var U) =
  case command.kind:
  of add: doAdd(command, buffer)
  of insert: doInsert(command, buffer)
  of delete: doDelete(command, buffer)
  of assign: doAssign(command, buffer)

proc inverseOfAdd[T](command: Command[T]): Command[T] =
  doAssert(command.kind == CommandKind.add)
  assert(false, "Not implemented")

proc inverseOfInsert[T](command: Command[T]): Command[T] =
  doAssert(command.kind == CommandKind.insert)
  return newDeleteCommand[T](command.insertPosition, command.insertPosition)

proc inverseOfDelete[T](command: Command[T]): Command[T] =
  doAssert(command.kind == CommandKind.delete)
  assert(false, "Not implemented")

proc inverseOfAssign[T](command: Command[T]): Command[T] =
  doAssert(command.kind == CommandKind.assign)
  return newAssignCommand[T](command.newElement, command.oldElement, command.assignPosition)

proc inverseCommand[T](command: Command[T]): Command[T] =
  case command.kind:
  of add: inverseOfAdd(command)
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

proc undo*[T, U](undoRedoStack: var UndoRedoStack[T], buffer: var U) =
  doAssert(undoRedoStack.nextCommandIndex > 0)
  dec(undoRedoStack.nextCommandIndex)
  doCommand[T,U](inverseCommand[T](undoRedoStack.commands[undoRedoStack.nextCommandIndex]), buffer)

proc redo*[T, U](undoRedoStack: var UndoRedoStack[T], buffer: var U) =
  doAssert(undoRedoStack.nextCommandIndex < undoRedoStack.commands.len)
  doCommand[T, U](undoRedoStack.commands[undoRedoStack.nextCommandIndex], buffer)
  inc(undoRedoStack.nextCommandIndex)

proc canUndo*[T](undoRedoStack: UndoRedoStack[T]): bool = undoRedoStack.nextCommandIndex > 0

proc canRedo*[T](undoRedoStack: UndoRedoStack[T]): bool = undoRedoStack.nextCommandIndex < undoRedoStack.commands.len