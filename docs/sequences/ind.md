# Index

|      |             |
| ---- | ----------- |
| Text | `ESC D`     |
| Hex  | `0x18 0x44` |

Move the cursor to the next line in the scrolling region, scrolling
if necessary. This always unsets the pending wrap state.

If the cursor is currently outside the scrolling region:

- move the cursor down one line if it is not on bottom line of the screen.

If the cursor is inside the scrolling region:

- If the cursor is on the bottom-most line of the screen: invoke
  [scroll up](su.md) with the value `1`.
- Else: move the cursor one line down.
