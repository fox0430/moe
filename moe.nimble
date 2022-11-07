# Package

version       = "0.4.0"
author        = "fox0430"
description   = "A command lined based text editor"
license       = "GPLv3"
srcDir        = "src"
bin           = @["moe"]

# Dependencies

requires "nim >= 1.6.2"
requires "ncurses >= 1.0.2"
requires "unicodedb >= 0.11.1"
requires "https://github.com/nim-lang/parsetoml#db204a9464a6f0e6895b41c7d39bf76dd0cbb87a"

task release, "Build for release":
  exec "nimble build -d:release"

task debug, "Build for debug":
  exec "nimble build -d:debug --debugger:native --verbose -y"
