# Platform / Terminal

## [KDE Konsole](https://konsole.kde.org)

Currently, Moe doesn't display correct colors when using 24 bit color on Konsole.
So, you need to use 256 color mode on Konsole.

![konsole](https://github.com/fox0430/moe/assets/15966436/cbde3452-c904-4941-b262-804f04116401)

You need to set `colorMode` in your configuration file like this.

```
$ cat ~/.config/moerc.toml

[Standard]
colorMode = "256"
```

### Reference

- https://github.com/fox0430/moe/issues/1751

## The TERM environment variable

Please set `$TERM` to `xterm-256color`. Otherwise, it may not work properly. This is a Ncurses limitation.

### Reference

- https://github.com/fox0430/moe/issues/1803
