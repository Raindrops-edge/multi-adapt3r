# Cancel Parsing

|     |   |
| --- | --- |
| Text |        |
| Hex  | `0x18` or `0x1A`  |

Cancels sequence parsing. Any partially completed sequence such as `ESC`
can send `0x18` and revert back to an unparsed state. The sequence characters
up to that point are discarded.
