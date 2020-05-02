import unittest
import moepkg/[editorstatus]

test "Work space: Create work space":
  var status = initEditorStatus()
  status.addNewBuffer("")

  status.resize(100, 100)
  status.update

  status.createWrokSpace

  check(status.workspace.len == 2)

test "Work space: Change current work space":
  var status = initEditorStatus()
  status.addNewBuffer("")

  status.resize(100, 100)
  status.update

  status.createWrokSpace

  ## Work space index is status.currentWorkSpaceIndex + 1
  status.changeCurrentWorkSpace(1)
  check(status.currentWorkSpaceIndex == 0)

  status.changeCurrentWorkSpace(2)
  check(status.currentWorkSpaceIndex == 1)

test "Work space: Delete current work space":
  var status = initEditorStatus()
  status.addNewBuffer("")

  status.resize(100, 100)
  status.update

  status.createWrokSpace

  status.deleteWorkSpace(1)

  check(status.workspace.len == 1)
  check(status.currentWorkSpaceIndex == 0)
