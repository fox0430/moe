# Package

version       = "0.3.0"
author        = "fox0430"
description   = "A command lined based text editor"
license       = "GPLv3"
srcDir        = "src"
bin           = @["moe"]

# Dependencies

requires "nim >= 1.6.16"
requires "ncurses >= 1.0.2"
requires "unicodedb >= 0.13.0"
requires "parsetoml >= 0.7.1"
requires "regex >= 0.25.0"
requires "results >= 0.4.0"
requires "jsony >= 1.1.5"
requires "chronos >= 4.0.3"
requires "stew >= 0.1.0"

task release, "Build for release":
  exec "nimble build -d:release"

task debug, "Build for debug":
  exec "nimble build -d:debug --debugger:native --verbose -y"
