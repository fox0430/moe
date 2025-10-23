import std/[unittest, os, strutils]
import pkg/results
import ../src/moepkg/[buffer, cursor]

suite "Buffer - Trailing Empty Lines":
  test "Insert text with trailing empty lines preserves them":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "Hello\n\n")

    check buf.len == 3
    check buf[0] == "Hello"
    check buf[1] == ""
    check buf[2] == ""

    let text = buf.getTextString()
    check text == "Hello\n\n\n" # Last empty line outputs as newline

  test "Manual line splits create empty lines":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "Hello")
    discard buf.splitLine(BufferPosition(line: 0, column: 5)) # Enter after Hello
    discard buf.splitLine(BufferPosition(line: 1, column: 0)) # Enter on empty line

    check buf.len == 3
    check buf[0] == "Hello"
    check buf[1] == ""
    check buf[2] == ""

  test "Save and load preserves trailing empty lines":
    let testFile = "/tmp/moe_test_trailing.txt"

    # Create buffer with trailing empty lines
    let buf1 = newTextBuffer()
    discard buf1.insertText(BufferPosition(line: 0, column: 0), "Hello\n\n")

    # Save
    let saveResult = buf1.saveFile(testFile)
    check saveResult.get() == ()

    # Check file content
    let savedContent = readFile(testFile)
    check savedContent == "Hello\n\n\n" # Trailing empty lines preserved + endOfLine

    # Load back
    let buf2 = newTextBuffer()
    let loadResult = buf2.loadFile(testFile)
    check loadResult.get() == ()

    # Verify empty lines are preserved
    check buf2.len == 3
    check buf2[0] == "Hello"
    check buf2[1] == ""
    check buf2[2] == ""

    removeFile(testFile)

  test "endOfLine flag controls trailing newline on save":
    let testFile = "/tmp/moe_test_endofline.txt"

    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "Hello\n\n")

    # With endOfLine=true (default)
    check buf.endOfLine == true
    discard buf.saveFile(testFile)
    var content = readFile(testFile)
    check content.endsWith("\n")

    # With endOfLine=false - removes ONE trailing newline
    buf.endOfLine = false
    discard buf.saveFile(testFile)
    content = readFile(testFile)
    # getTextString() gives "Hello\n\n\n", removing one \n gives "Hello\n\n"
    # which still ends with \n (from the second empty line)
    check content == "Hello\n\n"
    check content.endsWith("\n") # Still ends with \n from empty line

    removeFile(testFile)
