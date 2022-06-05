# Package

version       = "0.4.0"
author        = "fox0430"
description   = "A command lined based text editor"
license       = "GPLv3"
srcDir        = "src"
bin           = @["moe"]

# Dependencies

requires "nim >= 1.6.2"
requires "unicodedb >= 0.10.0"
requires "parsetoml >= 0.6.0"
requires "parsetoml >= 0.6.0"
requires "https://github.com/iffy/termtools >= 0.1.0"

task release, "Build for release":
  exec "nimble build -d:release"

task debug, "Build for debug":
  exec "nimble build -d:debug --debugger:native --verbose -y"
