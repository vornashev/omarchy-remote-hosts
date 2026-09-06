#!/usr/bin/python3
"""OpenSSH-only password pipe. Never print diagnostics or a traceback."""
import sys

# Omarchy watches this directory; bytecode writes would reload the shell plugins.
sys.dont_write_bytecode = True
from helper import askpass

if __name__ == "__main__":
    try:
        if len(sys.argv) != 2:
            raise ValueError()
        password = askpass(sys.argv[1])
        if not isinstance(password, str):
            raise ValueError()
        sys.stdout.write(password + "\n")
        sys.stdout.flush()
    except Exception:
        sys.exit(1)
