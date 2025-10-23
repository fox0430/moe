#[###################### GNU General Public License 3.0 ######################]#
#                                                                              #
#  Copyright (C) 2017─2025 Shuhei Nogawa                                       #
#                                                                              #
#  This program is free software: you can redistribute it and/or modify        #
#  it under the terms of the GNU General Public License as published by        #
#  the Free Software Foundation, either version 3 of the License, or           #
#  (at your option) any later version.                                         #
#                                                                              #
#  This program is distributed in the hope that it will be useful,             #
#  but WITHOUT ANY WARRANTY; without even the implied warranty of              #
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the               #
#  GNU General Public License for more details.                                #
#                                                                              #
#  You should have received a copy of the GNU General Public License           #
#  along with this program.  If not, see <https://www.gnu.org/licenses/>.      #
#                                                                              #
#[############################################################################]#

## Performance benchmark for search functionality
## Tests search performance at various buffer sizes

import std/[times, strformat, options, strutils]
import ../src/moepkg/buffer {.all.}
import ../src/moepkg/cursor {.all.}

proc generateTestBuffer(lineCount: int, charsPerLine: int = 80): TextBuffer =
  ## Generate a test buffer with specified number of lines
  ## Each line contains some "foo" keywords for searching
  var content = ""
  for i in 0 ..< lineCount:
    # Add "foo" keyword at the beginning, middle, and end of some lines
    if i mod 10 == 0:
      content.add("foo ")
    content.add("line ")
    content.add($i)
    content.add(" some text content here")
    if i mod 7 == 0:
      content.add(" foo")
    if i mod 13 == 0:
      content.add(" middle foo text")
    # Pad to roughly charsPerLine
    while content.len < (i + 1) * charsPerLine:
      content.add(" padding")
    content.add("\n")
  return newTextBuffer(content)

proc benchmarkSearch(
    lineCount: int, iterations: int = 100
): tuple[firstSearch: float, avgNext: float, avgPrev: float] =
  ## Benchmark search operations on a buffer with given line count
  let buf = generateTestBuffer(lineCount)
  var totalFirstSearch = 0.0
  var totalNext = 0.0
  var totalPrev = 0.0

  # Benchmark: First search (from beginning)
  for i in 0 ..< iterations:
    let start = cpuTime()
    discard buf.findNext("foo", BufferPosition(line: 0, column: 0))
    totalFirstSearch += (cpuTime() - start)

  # Benchmark: Next search (n command - sequential)
  var pos = BufferPosition(line: 0, column: 0)
  let startPos = buf.findNext("foo", pos)
  if startPos.isSome:
    pos = startPos.get
    for i in 0 ..< iterations:
      let start = cpuTime()
      let nextResult = buf.findNext("foo", pos)
      totalNext += (cpuTime() - start)
      if nextResult.isSome:
        pos = nextResult.get

  # Benchmark: Previous search (N command - sequential)
  pos = BufferPosition(line: lineCount div 2, column: 0)
  let midPos = buf.findPrev("foo", pos)
  if midPos.isSome:
    pos = midPos.get
    for i in 0 ..< iterations:
      let start = cpuTime()
      let prevResult = buf.findPrev("foo", pos)
      totalPrev += (cpuTime() - start)
      if prevResult.isSome:
        pos = prevResult.get

  return (
    firstSearch: (totalFirstSearch / iterations.float) * 1000.0,
      # Convert to milliseconds
    avgNext: (totalNext / iterations.float) * 1000.0,
    avgPrev: (totalPrev / iterations.float) * 1000.0,
  )

proc benchmarkUnicodeSearch(lineCount: int, iterations: int = 100): float =
  ## Benchmark search with Unicode characters
  var content = ""
  for i in 0 ..< lineCount:
    if i mod 10 == 0:
      content.add("日本語 ")
    content.add("テキスト行 ")
    content.add($i)
    if i mod 7 == 0:
      content.add(" 日本語")
    content.add("\n")

  let buf = newTextBuffer(content)
  var totalTime = 0.0

  for i in 0 ..< iterations:
    let start = cpuTime()
    discard buf.findNext("日本語", BufferPosition(line: 0, column: 0))
    totalTime += (cpuTime() - start)

  return (totalTime / iterations.float) * 1000.0

proc benchmarkWorstCase(
    lineCount: int, iterations: int = 50
): tuple[notFound: float, lastLine: float] =
  ## Benchmark worst-case scenarios
  let buf = generateTestBuffer(lineCount)
  var totalNotFound = 0.0
  var totalLastLine = 0.0

  # Worst case 1: Pattern not found (full buffer scan)
  for i in 0 ..< iterations:
    let start = cpuTime()
    discard buf.findNext("NOTEXIST", BufferPosition(line: 0, column: 0))
    totalNotFound += (cpuTime() - start)

  # Worst case 2: Pattern only on last line (almost full scan)
  # Create buffer with pattern only at the end
  var content = ""
  for i in 0 ..< lineCount - 1:
    content.add("line ")
    content.add($i)
    content.add(" no match here\n")
  content.add("final line with TARGETPATTERN here\n")
  let bufLast = newTextBuffer(content)

  for i in 0 ..< iterations:
    let start = cpuTime()
    discard bufLast.findNext("TARGETPATTERN", BufferPosition(line: 0, column: 0))
    totalLastLine += (cpuTime() - start)

  return (
    notFound: (totalNotFound / iterations.float) * 1000.0,
    lastLine: (totalLastLine / iterations.float) * 1000.0,
  )

proc main() =
  echo "=".repeat(70)
  echo "Search Performance Benchmark"
  echo "=".repeat(70)
  echo ""

  let testSizes = [100, 500, 1_000, 2_000, 5_000, 10_000]
  let iterations = 100

  echo &"Running {iterations} iterations for each test size..."
  echo ""
  echo "Buffer Size | First Search | Next (n) | Previous (N) | Total"
  echo "-".repeat(70)

  for size in testSizes:
    let results = benchmarkSearch(size, iterations)
    let total = results.firstSearch + results.avgNext + results.avgPrev
    echo &"{size:>11} | {results.firstSearch:>11.4f}ms | {results.avgNext:>8.4f}ms | {results.avgPrev:>12.4f}ms | {total:>8.4f}ms"

  echo ""
  echo "=".repeat(70)
  echo "Worst-Case Performance (Full Buffer Scans)"
  echo "=".repeat(70)
  echo ""
  echo "Buffer Size | Not Found | Last Line"
  echo "-".repeat(45)

  let worstCaseSizes = [1_000, 2_000, 5_000, 10_000, 20_000, 50_000]
  for size in worstCaseSizes:
    let results = benchmarkWorstCase(size, iterations = 50)
    echo &"{size:>11} | {results.notFound:>9.4f}ms | {results.lastLine:>9.4f}ms"

  echo ""
  echo "=".repeat(70)
  echo "Unicode Search Performance"
  echo "=".repeat(70)
  echo ""
  echo "Buffer Size | Average Search Time"
  echo "-".repeat(40)

  for size in [100, 500, 1_000, 2_000, 5_000]:
    let result = benchmarkUnicodeSearch(size, iterations)
    echo &"{size:>11} | {result:>18.4f}ms"

  echo ""
  echo "=".repeat(70)
  echo "Performance Notes:"
  echo "- Times are averaged over " & $iterations & " iterations"
  echo "- 'First Search' = Initial search from buffer start"
  echo "- 'Next (n)' = Sequential forward searches (typical n command usage)"
  echo "- 'Previous (N)' = Sequential backward searches (typical N command usage)"
  echo "- Acceptable threshold: < 50ms for responsive UI"
  echo "=".repeat(70)

when isMainModule:
  main()
