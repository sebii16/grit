# Grit

**Grit is a simple and fast command runner written in Zig**

## Features

- Variable expansion
- Default tasks with `@default`
- Automatic `gritfile` discovery from parent directories
- Built-in variables
- Parallel and sequential execution
- Conditional execution with `@if`, `@elif` and `@else`
- Inline source execution with `--eval`
- Dry-run mode with `--dry-run`
- Custom shell support with `--shell`
- And more options listed in **[CLI.md](CLI.md)**

## Installation

### Option 1 - Build it yourself

```sh
git clone https://github.com/sebii16/grit
cd grit
zig build-exe src/main.zig -O ReleaseFast -lc
```

> [!IMPORTANT]
> Grit requires Zig 0.16.0. Other versions are untested and may not work.

## Task files

**A task file (named `gritfile` by default) is a list of variable declarations and tasks. Each task can hold one or more commands to run.**

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

Directives start with `@` and modify how following commands or tasks behave.

| Directive             | Effect                                                                              |
| --------------------- | ----------------------------------------------------------------------------------- |
| `@default`            | Marks the next task as default.                                                 |
| `@parallel`           | Commands after this run parallel to each other, until `@sequential`.                |     
| `@sequential`         | Commands after this run one at a time (default).                                    |
| `@if, @elif, @else`   | Executes the first block whose condition is true, or a @else block if none are true |

Parallel and sequential blocks can be mixed inside a task.

## Example

```sh
# Variable declarations
SRC = "src/main.zig"
OUT = "grit"
FLAGS = "-O Debug -lc"

# Default task
@default
build {
    @if OS == "windows" {
        "zig build-exe $SRC -femit-bin=$OUT.exe $FLAGS"
    } @elif OS == "linux" {
        "zig build-exe $SRC -femit-bin=$OUT $FLAGS"
    } @else {
        "echo OS not supported"
    }
}

another_task {
    "echo test"
}
```

**Run the default task:**

```sh
grit
```

**Run a different task:**

```sh
grit another_task
```

**Use a different file:**

```sh
grit -f FILE
```

**Use a different shell**

```sh
grit --shell "pwsh.exe -c"
```

## CLI Options

**For the complete list of cli options see [CLI.md](CLI.md)**

## Built-in Variables

These variables are automatically available. They are reserved and can't be overwritten.

| Variable       | Description                                                          |
| -------------- | ---------------------------------------------------------------------|
| `OS`           | Current operating system                                             |
| `ARCH`         | Current CPU architecture                                             |
| `CWD`          | Directory from which Grit was called                                 |
| `GRIT_VER`     | Your version of grit                                                 |
| `ROOT_DIR`     | Directory containing the gritfile and used to run tasks              |

## License

Grit is licensed under the **[MIT License](LICENSE)**.
