# Backspace

|      |        |
| ---- | ------ |
| Text |        |
| Hex  | `0x08` |

Move the cursor left one cell.

TODO: Details about how this interacts with soft wrapping.

## Implementation Details

- ghostty implements this naively as `cursor.x -|= 1` (`-|=` being a
  saturating subtraction).

## TODO

- Soft wrap integration
