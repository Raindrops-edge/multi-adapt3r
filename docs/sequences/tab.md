# Tab

|     |   |
| --- | --- |
| Text |        |
| Hex  | `0x09`   |

Move the cursor right to the next tab stop.

A tab stop is a specifically marked column that a cursor stops when a tab
is invoked. Tab stops are typically thought of as uniform spacing (i.e.
four spaces) but in terminals this is not the case: tab stops can be set
at any column number using the [tab set](#) and [tab clear](#)
sequences.

Initially, tab stops are set on every 8th column.

## TODO

  * Integration with left/right margins of the scrolling region.
  * How does horizontal tab interact with the pending wrap state?
