# Shell Integration Code

This is the shell-specific shell-integration code that is
used for the shell-integration feature set that Ghostty
supports.

This README is meant as developer documentation and not as
user documentation. For user documentation, see the main
README.

## Implementation Details

### Bash

The bash shell integration must currently be sourced manually
from `bash/ghostty.bash`.

### Fish

For [Fish](https://fishshell.com/), Ghostty prepends to the
`XDG_DATA_DIRS` directory. Fish automatically loads configuration
files in `<XDG_DATA_DIR>/fish/vendor_conf.d/*.fish` on startup,
allowing us to automatically integrate with the shell. For details
on the Fish startup process, see the
[Fish documentation](https://fishshell.com/docs/current/language.html).

### Zsh

For `zsh`, Ghostty sets `ZDOTDIR` so that it loads our configuration
from the `zsh` directory. The existing `ZDOTDIR` is retained so that
after loading the Ghostty shell integration the normal Zsh loading
sequence occurs.
