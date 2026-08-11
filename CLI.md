```text
General Options:
  -h, --help           Show this help message and exit.
  -v, --version        Show version, license information and exit.
      --no-colors      Disable colored output.

Execution Options:
  -f, --file <FILE>    Override file to read from (default: gritfile).
  -d, --dry-run        Print commands without executing them.
  -t, --threads <NUM>  Set the maximum number of threads (default: CPU core count).
  -i, --ignore-errors  Treat execution errors as warnings.
  -e, --eval <SRC>     Execute SRC instead of reading from a file.
  -q, --quiet          Only print errors.
  -s, --shell <SHELL>  Set the shell used to execute commands (e.g. -s "pwsh.exe -c").
  -l, --list           List all tasks and exit.
      --no-discovery   Only look for a gritfile in the current directory.
      --no-expand      Disable variable expansion.
      --dump-vars      List all variables and exit.
```