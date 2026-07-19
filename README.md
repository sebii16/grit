# Grit

**Grit is a simple build automation tool inspired by Make. It is currently still early in development - for now it supports simple variable expansion, parallel and sequential command execution and a few extra features described below.**

> [!NOTE]
> Grit is currently experimental and under active development.
> Build file syntax and general behavior may change between releases.

## Installation

### Option 1 - Build it yourself

```sh
git clone https://github.com/sebii16/grit-build-tool
cd grit
zig build-exe src/main.zig -O ReleaseSmall -lc
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

### Annotations

Annotations start with `@` and modify how following commands or rules behave.

| Annotation     | Effect                                                                 |
| -------------- | ---------------------------------------------------------------------- |
| `@default`     | Marks the next rule as the default.   |
| `@parallel`    | Commands after this run parallel to each other, until `@sequential`.             |
| `@sequential`  | Commands after this run one at a time (default).                   |

Parallel and sequential blocks can be mixed inside a rule.

## Example

```sh
# Variable declarations
SRC = "src/main.zig"
OUT = "grit.exe"
FLAGS = "-O ReleaseSmall -fstrip -lc"

# Default rule
@default
build {
    "zig build-exe $SRC -femit-bin=$OUT $FLAGS"
}

# Another rule with multiple commands and parallel and sequential mode
clean {
    @parallel
    "rm -f *.exe"
    "rm -f *.pdb"
    @sequential
    'echo "all clean"'
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
--no-expand      Disable variable expansion.

Global flags: 
-h, --help      Show help message.
-v, --version   Show version and license information.
-l, --list      List build rules.
```

## License

Grit is licensed under the **[MIT License](LICENSE)**.
