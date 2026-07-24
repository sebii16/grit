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

| Directive      | Effect                                                                |
| -------------- | --------------------------------------------------------------------- |
| `@default`     | Marks the next rule as the default.                                   |
| `@parallel`    | Commands after this run parallel to each other, until `@sequential`.  |     
| `@sequential`  | Commands after this run one at a time (default).                      |
| `@if`          | Executes the commands in its block only if the condition is true      |

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
    }

    @if OS == "linux" {
        "zig build-exe $SRC -femit-bin=$OUT $FLAGS"
    }
}

# Another rule with multiple commands and parallel and sequential mode
clean {
    @parallel
    @if OS == "windows" {
        "del $OUT.exe"
        "del $OUT.pdb"
    }

    @if OS == "linux" {
        "rm -f $OUT"
        "rm -f $OUT.pdb"
    }

    @sequential
    'echo "Cleanup done"'
}
```

**Run the default rule:**

```sh
grit
```

**Run a different rule:**

```sh
grit clean
```

**Run a different build file:**

```sh
grit -f file_name
```

**Run with a specific number of parallel threads:**

```sh
grit release -t 4
```

## Flags

```text
Build flags:
-d, --dry       Print commands without executing them.
-f, --file      Specify the build file.
-r, --rule      Specify the build rule.
-t, --threads   Specify the max. amount of threads (default = CPU core count)
--ignore-errors Ignore execution errors.
--no-colors     Disable colors.
--no-expand     Disable variable expansion.

Global flags: 
-h, --help      Show help message.
-v, --version   Show version and license information.
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
| `GRIT_VER`     | Current version of grit                                              |

## License

Grit is licensed under the **[MIT License](LICENSE)**.
