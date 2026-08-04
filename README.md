# Grit

**Grit is a simple build automation tool inspired by Make. It is currently still early in development - for now it supports variable expansion, a few built-in variables, conditional command execution, parallel and sequential command execution and several other features described below.**

> [!NOTE]
> Grit is currently experimental and under active development.
> Build file syntax, features and general behavior may change at any time.

## Installation

### Option 1 - Build it yourself

```sh
git clone https://github.com/sebii16/grit-build-tool
cd grit
zig build-exe src/main.zig -O ReleaseFast -lc
```
> [!IMPORTANT]
> Grit requires Zig 0.16.0. Other versions are currently unsupported.

## Build files

**A build file (`build.grit` by default) is a list of variable declarations and rules. Each rule can hold one or more commands to run.**

### Comments

Lines starting with `#` are comments and ignored.

### Variable declarations and expansion

Declare variables with `NAME = "value"` and expand them inside commands with `$NAME`.

To get a literal `$`, write `$$`.

Disable expansion completely by using the `--no-expand` flag.

### Strings

Commands and variables have to be strings and wrapped in quotes like this:

```sh
"Hello World!"
```

or to use double quotes inside strings:

```sh
'This tool is called "grit"!'
```

### Directives

Directives start with `@` and modify how following commands or rules behave.

| Directive             | Effect                                                                              |
| --------------------- | ----------------------------------------------------------------------------------- |
| `@default`            | Marks the next rule as the default.                                                 |
| `@parallel`           | Commands after this run parallel to each other, until `@sequential`.                |     
| `@sequential`         | Commands after this run one at a time (default).                                    |
| `@if, @elif, @else`   | Executes the first block whose condition is true, or a @else block if none are true |

Parallel and sequential blocks can be mixed inside a rule.

## Example

```sh
# Variable declarations
SRC = "src/main.zig"
OUT = "grit"
FLAGS = "-O Debug -lc"

# Default rule
@default
build {
    @if OS == "windows" {
        "zig build-exe $SRC -femit-bin=$OUT.exe $FLAGS"
    } @elif OS == "linux" {
        "zig build-exe $SRC -femit-bin=$OUT $FLAGS"
    } @else {
        print "OS not supported"
    }
}
```

**Run the default rule:**

```sh
grit
```

**Run a different rule:**

```sh
grit RULE
```

**Run a different build file:**

```sh
grit -f FILE
```

**Run with a specific number of parallel threads:**

```sh
grit release -t 4
```

## Flags

```text
Build flags:
  -d, --dry-run       Print commands without executing them.
  -f, --file FILE     Build file to use (default: build.grit).
  -t, --threads N     Max. number of threads (default: CPU core count).
  -e, --eval SRC      Execute SRC instead of reading a build file.          
  -i, --ignore-errors Treat execution errors as warnings.
  -q, --quiet         Only print errors.
      --no-colors     Disable colored output.
      --no-expand     Disable variable expansion.
    
Global flags: 
  -h, --help          Show this help message.
  -v, --version       Show version and license information.  
```

## Built-in Variables

These variables are automatically available in every build file. They are reserved and can't be overwritten.

| Variable       | Description                                                          |
| -------------- | ---------------------------------------------------------------------|
| `OS`           | Current operating system                                             |
| `ARCH`         | Current CPU architecture                                             |
| `TIME`         | Current time                                                         |
| `DATE`         | Current date                                                         |
| `CWD`          | Current working directory                                            |
| `GRIT_VER`     | Your version of grit                                              |

## License

Grit is licensed under the **[MIT License](LICENSE)**.
