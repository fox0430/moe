import unittest
import moepkg/filermode, moepkg/editorstatus

test "Update directory list":
  var status = initEditorStatus()
  status.addNewBuffer("")
  var filerStatus = initFilerStatus()
  filerStatus = filerStatus.updateDirList
  status.tupdateFilerView(filerStatus)
