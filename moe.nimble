# Package

version       = "0.3.0"
author        = "fox0430"
description   = "A command lined based text editor"
license       = "GPLv3"
srcDir        = "src"
bin           = @["moe"]

# Dependencies

requires "nim >= 1.4.2"
requires "ncurses >= 1.0.2"
requires "unicodedb >= 0.10.0"
requires "parsetoml >= 0.6.0"

task release, "Build for release":
  exec "nimble build -d:release"

task debug, "Build for debug":
  exec "nimble build -d:debug --debugger:native --verbose -y"
