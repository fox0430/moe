# Package

version = "0.5.0"
author = "fox0430"
description = "A command lined based text editor"
license = "GPLv3"
srcDir = "src"
bin = @["moe"]

# Dependencies

requires "nim >= 2.0.10"
requires "results >= 0.5.1"
requires "celina >= 0.9.0"
requires "parsetoml >= 0.7.1"
requires "chronos >= 4.0.4"
requires "stew >= 0.2.0"

task release, "Build for release":
  exec "nimble build -d:release"

task debug, "Build for debug":
  exec "nimble build -d:debug --debugger:native --verbose -y"

task ptest, "Run tests in parallel":
  exec "nim r tools/paralleltest.nim"
