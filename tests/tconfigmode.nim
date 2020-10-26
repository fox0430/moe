import unittest
import moepkg/[editorstatus, gapbuffer, bufferstatus, unicodetext]

include moepkg/configmode

suite "Config mode: Start configuration mode":
  test "Init configuration mode buffer":
    var status = initEditorStatus()
    status.addNewBuffer(Mode.config)

    status.bufStatus[0].buffer = initConfigModeBuffer(status.settings)
    let buffer = status.bufStatus[0].buffer
