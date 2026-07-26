# Parallel test runner.
# Usage: nim r tools/paralleltest.nim [jobs]
# Ex: nim r tools/paralleltest.nim 8
#
# Environment:
#   MOE_TEST_JOBS      parallel jobs (default: number of logical CPUs)
#   MOE_TEST_TIMEOUT   per-file timeout in seconds, 0 disables (default: 120)
#   MOE_TEST_EXCLUDE   comma separated file names to skip entirely
#   MOE_TEST_SHARDS    total number of shards (default: 1, i.e. run everything)
#   MOE_TEST_SHARD     1-based index of the shard to run (default: 1)
#   MOE_TEST_DRY_RUN   list the selected files and exit without running them

import std/[algorithm, osproc, os, strutils, sequtils]

const
  # Fallback when the number of CPUs cannot be detected (countProcessors() == 0).
  FallbackJobs = 4
  DefaultTimeoutSec = 120

  # Flaky tests that must be run sequentially after the parallel batch
  # so concurrent file/clipboard/etc. usage cannot perturb them.
  SequentialTests = ["test_registers.nim", "test_terminal_handler.nim", "test_pty.nim"]

proc defaultJobs(): int =
  # Default to the number of logical CPUs (hardware threads) available.
  let cpus = osproc.countProcessors()
  if cpus > 0: cpus else: FallbackJobs

proc parseFileList(s: string): seq[string] =
  # Comma separated test file names, e.g. "test_a.nim,test_b.nim".
  s.split(',').mapIt(it.strip()).filterIt(it.len > 0)

proc shardConfig(): tuple[index, total: int] =
  # 1-based shard index out of `total` shards. Defaults to a single shard so
  # local runs stay unchanged; CI sets both to split the suite across runners.
  let total =
    if getEnv("MOE_TEST_SHARDS").len > 0:
      parseInt(getEnv("MOE_TEST_SHARDS"))
    else:
      1
  let index =
    if getEnv("MOE_TEST_SHARD").len > 0:
      parseInt(getEnv("MOE_TEST_SHARD"))
    else:
      1

  if total < 1:
    quit("MOE_TEST_SHARDS must be >= 1 (got " & $total & ")", 1)
  if index < 1 or index > total:
    quit("MOE_TEST_SHARD must be in 1.." & $total & " (got " & $index & ")", 1)

  (index, total)

proc main() =
  let jobs =
    if paramCount() >= 1:
      parseInt(paramStr(1))
    elif getEnv("MOE_TEST_JOBS").len > 0:
      parseInt(getEnv("MOE_TEST_JOBS"))
    else:
      defaultJobs()

  # Per-file timeout (compile + run) to protect CI from hanging tests.
  # Set MOE_TEST_TIMEOUT=0 to disable. Requires GNU coreutils `timeout`.
  let timeoutSec =
    if getEnv("MOE_TEST_TIMEOUT").len > 0:
      parseInt(getEnv("MOE_TEST_TIMEOUT"))
    else:
      DefaultTimeoutSec

  let
    excluded = parseFileList(getEnv("MOE_TEST_EXCLUDE"))
    (shardIndex, shardTotal) = shardConfig()

  var discovered = toSeq(walkDir("tests", relative = true))
    .filterIt(
      it.kind == pcFile and it.path.startsWith("t") and it.path.endsWith(".nim")
    )
    .mapIt(it.path)
    .filterIt(it notin excluded)

  # Largest first: it packs the parallel batch better and makes the shard split
  # below deterministic regardless of the order walkDir happens to return.
  discovered.sort do(a, b: string) -> int:
    result = cmp(getFileSize("tests" / b), getFileSize("tests" / a))
    if result == 0:
      result = cmp(a, b)

  # Round-robin over the size-sorted list so each shard gets a comparable share
  # of the (compile dominated) workload.
  var allTestFiles: seq[string]
  for i, file in discovered:
    if i mod shardTotal == shardIndex - 1:
      allTestFiles.add(file)

  let parallelFiles = allTestFiles.filterIt(it notin SequentialTests)
  let sequentialFiles = allTestFiles.filterIt(it in SequentialTests)
  let totalFiles = parallelFiles.len + sequentialFiles.len

  if getEnv("MOE_TEST_DRY_RUN").len > 0:
    # Lets a shard split be audited (e.g. that the shards union to the full set)
    # without paying for a real run. stdout stays a bare file list.
    stderr.writeLine "Shard " & $shardIndex & "/" & $shardTotal & ": " & $totalFiles &
      " of " & $discovered.len & " test files"
    for file in parallelFiles & sequentialFiles:
      echo file
    quit(0)

  if excluded.len > 0:
    echo "Excluded: ", excluded.join(", ")
  if shardTotal > 1:
    echo "Shard ",
      shardIndex, "/", shardTotal, ": ", totalFiles, " of ", discovered.len,
      " test files"

  if timeoutSec > 0:
    echo "Running ",
      parallelFiles.len, " tests with ", jobs, " parallel jobs (timeout: ", timeoutSec,
      "s per file)..."
  else:
    echo "Running ", parallelFiles.len, " tests with ", jobs, " parallel jobs..."

  proc buildCommand(file: string): string =
    if timeoutSec > 0:
      "timeout --foreground --kill-after=5 " & $timeoutSec & " nim c -r tests/" & file
    else:
      "nim c -r tests/" & file

  let commands = parallelFiles.mapIt(buildCommand(it))

  var failedTests: seq[tuple[name: string, exitCode: int]]

  proc afterTest(idx: int, p: Process) =
    let code = p.peekExitCode()
    if code != 0:
      failedTests.add((parallelFiles[idx], code))

  var exitCode = execProcesses(
    commands,
    n = jobs,
    options = {poParentStreams, poUsePath},
    afterRunEvent = afterTest,
  )

  if sequentialFiles.len > 0:
    echo "\nRunning ", sequentialFiles.len, " flaky test(s) sequentially..."
    for file in sequentialFiles:
      let code = execCmd(buildCommand(file))
      if code != 0:
        failedTests.add((file, code))
        if exitCode == 0:
          exitCode = code

  echo "\nFinished ", totalFiles, " files"

  if failedTests.len > 0:
    echo "\nFailed (", failedTests.len, "/", totalFiles, "):"
    for (name, code) in failedTests:
      let suffix =
        if code == 124:
          " (TIMEOUT)"
        elif code == 137:
          " (TIMEOUT/KILLED)"
        else:
          ""
      echo "  FAIL: tests/", name, " (exit code: ", code, ")", suffix
    echo '\n'
  else:
    echo "\nAll tests passed."

  quit(exitCode)

main()
