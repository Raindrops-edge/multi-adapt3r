# Reverse Index

|     |   |
| --- | --- |
| Text | `ESC M`     |
| Hex  | `0x18 0x4D` |

Reverse [index](ind.md). This unsets the pending wrap state.

If the cursor is outside of the scrolling region:

  * move the cursor one line up unless it is the top-most line of the screen.

If the cursor is inside the scrolling region:

  * If the cursor is on the top-most line: invoke [scroll down](#) with value `1`
  * Else: move the cursor one line up.

## TODO

  * Scroll region edge cases
