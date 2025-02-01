# Bell

|     |   |
| --- | --- |
| Text |        |
| Hex  | `0x07`   |

Rings a "bell" to alert the operator to some condition.

## Implementation Details

  * ghostty logs "BELL"

## TODO

  * Add a configurable visual bell -- common in most terminal emulators --
    to flash the border.
  * Mark the window as requesting attention, most operating systems support
    this. For example, Windows windows will flash in the toolbar.
  * Support an audible bell.

## References

  * https://vt100.net/docs/vt100-ug/chapter3.html
