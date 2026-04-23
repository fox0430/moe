import std/[os, osproc, strutils]
import moepkg/buffer

let testDir = getTempDir() / "moe_debug_git_diff"
if dirExists(testDir):
  removeDir(testDir)
createDir(testDir)

discard execCmdEx("git init", workingDir = testDir)
discard execCmdEx("git config user.email 'test@test.com'", workingDir = testDir)
discard execCmdEx("git config user.name 'Test'", workingDir = testDir)

let testFile = testDir / "test.txt"
writeFile(testFile, "line 1\nline 2\nline 3")
discard execCmdEx("git add test.txt", workingDir = testDir)
discard execCmdEx("git commit -m 'Initial commit'", workingDir = testDir)

let buf = newTextBuffer()
discard buf.loadFile(testFile)

let content = buf.getFileContent()
echo "=== buffer getFileContent: ==="
echo "len=", content.len
echo "hex: ", content.toHex()
echo "endOfLine=", buf.endOfLine
echo "lineEnding=", buf.lineEnding

let (headContent, _) = execCmdEx("git show HEAD:test.txt", workingDir = testDir)
echo "=== HEAD content: ==="
echo "len=", headContent.len
echo "hex: ", headContent.toHex()

writeFile(testDir / "bufdump.txt", content)
writeFile(testDir / "headdump.txt", headContent)
echo "=== git diff output: ==="
let (diffOut, _) = execCmdEx(
  "git diff --no-index --unified=0 " & testDir / "headdump.txt" & " " &
    testDir / "bufdump.txt"
)
echo diffOut
