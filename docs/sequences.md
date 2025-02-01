# Control and Escape Sequences

⚠️  **This is super out of date. Ghostty's support is much better
than this document seems. TODO to update this.** ⚠️


This is the list of control and escape sequences known in the ecosystem
of terminal emulators and their implementation status in ghostty. Note that
some control sequences may never be implemented in ghostty. In these scenarios,
it is noted why.

Status meanings:

  * ✅ - Implementation is complete and considered 100% accurate.
  * ⚠️  - Implementation works, but may be missing some functionality. The
    details of how well it works or doesn't are in the linked page. In many
    cases, the missing functionality is very specific or esoteric. Regardless,
    we don't consider a sequence a green checkmark until all known feature
    interactions are complete.
  * ❌ - Implementation is effectively non-functional, but ghostty continues
    in the face of it (probably in some broken state).
  * 💥 - Ghostty crashes if this control sequence is sent.

| ID | ASCII | Name | Status |
|:---:|:-----:|:-----|:------:|
| `ENQ` | `0x05` | [Enquiry](sequences/enq.md) | ✅ |
| `BEL` | `0x07` | [Bell](sequences/bel.md) | ❌ |
| `BS` | `0x08` | [Backspace](sequences/bs.md) | ⚠️ |
| `TAB` | `0x09` | [Tab](sequences/tab.md) | ⚠️ |
| `LF` | `0x0A` | [Linefeed](sequences/lf.md) | ⚠️ |
| `VT` | `0x0B` | [Vertical Tab](sequences/vt.md) | ✅ |
| `FF` | `0x0C` | [Form Feed](sequences/ff.md) | ✅ |
| `CR` | `0x0D` | [Carriage Return](sequences/cr.md) | ⚠️ |
| `SO` | `0x0E` | [Shift Out](#) | ❌ |
| `SI` | `0x0F` | [Shift In](#) | ❌ |
| `CAN` | `0x18` | [Cancel Parsing](sequences/can.md) | ✅ |
| `SUB` | `0x1A` | [Cancel Parsing (Alias)](sequences/can.md) | ✅ |
| `IND` | `ESC D` | [Index](sequences/ind.md) | ✅ |
| `NEL` | `ESC E` | [Next Line](sequences/nel.md) | ✅ |
| `HTS` | `ESC H` | [Horizontal Tab Set](sequences/hts.md) | ✅ |
| `RI` | `ESC M` | [Reverse Index](sequences/ri.md) | ⚠️ |
| `SS2` | `ESC N` | [Single Shift 2](#) | ❌ |
| `SS3` | `ESC O` | [Single Shift 3](#) | ❌ |
| `SPA` | `ESC V` | [Start Protected Area](#) | ❌ |
| `EPA` | `ESC W` | [End Protected Area](#) | ❌ |
