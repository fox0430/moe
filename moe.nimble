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
requires "celina >= 0.12.0"
requires "parsetoml >= 0.7.1"
requires "chronos >= 4.2.2"
requires "stew >= 0.2.0"
requires "editorconfig >= 0.1.1"
requires "regex >= 0.26.1"
requires "jsony >= 1.1.6"

task release, "Build for release":
  exec "nimble build -d:release"

task debug, "Build for debug":
  exec "nimble build -d:debug --debugger:native --verbose -y"

task ptest, "Run tests in parallel":
  exec "nim r tools/paralleltest.nim"

task genhowtouse, "Regenerate auto-generated tables in documents/howtouse.md":
  exec "nim r --hints:off --warnings:off tools/gen_howtouse_docs.nim"

task gendocs, "Regenerate all auto-generated documentation":
  exec "nim r --hints:off --warnings:off tools/gen_config_docs.nim"
  exec "nim r --hints:off --warnings:off tools/gen_howtouse_docs.nim"
