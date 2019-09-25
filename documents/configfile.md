# Configuration file

Write moe's configuration file in toml.  
The location is

```
~/.config/moe/moerc.toml
```

You can use the example -> https://github.com/fox0430/moe/blob/master/example/moerc.toml

## Setting items

### Standard table
Color theme (String)
default is ```"vivid"```. ```"vivid"``` or ```"dark"``` or ```"light"```
```
theme
```

isplay line numbers (bool)  
default is true
```
number
```

Display status bar (bool)  
default is true
```
statusBar
```

Enable syntax highlighting (bool)  
default is true
```
syntax
```

Set tab width (Integer)  
default is 2
```
tabStop
```

Automatic closing brackets (bool)  
default is true
```
autoCloseParen
```

Automatic indentation (bool)  
default is true
```
autoIndent
```

Set cursor shape of the terminal emulator you are using (String) ```"block"``` or ```"ibeam"```  
default is block
```
defaultCursor
```

Set cursor shape in normal mode (String) ```"block"``` or ```"ibeam"```  
default is block
```
normalModeCursor
```

Set cursor shape in insert mode (String) ```"block"``` or ```"ibeam"```  
default is ibeam

```
insertModeCursor
```

### StatusBar table
Display current mode (bool)  
default is true
```
mode
```

Display edit history mark (bool)  
default is true
```
chanedMark
```

Display line info (bool)  
default is true
```
line
```

Display column info (bool)  
default is ture
```
column
```

Display character encoding (bool)  
default is true
```
encoding
```

Display language (bool)  
default is true
```
language
```

Display file location (bool)  
default is true
```
directory
```

### Color and theme
coming soon...
