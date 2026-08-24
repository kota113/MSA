# PoC wire protocol

One TCP connection owns one Android app session. The macOS client first sends one UTF-8 line:

    HELLO <package> <width> <height> <densityDpi> <bitrate>

The Android agent replies with `MWSA1\n`, followed by H.264 packets:

| Field | Size | Encoding |
|---|---:|---|
| kind | 1 | 1 = codec config, 2 = picture |
| MediaCodec flags | 1 | low 8 bits |
| presentation time | 8 | microseconds, big endian |
| payload length | 4 | big endian |
| payload | N | Annex-B or AVCC H.264 access unit |

Input travels in the opposite direction as newline-delimited commands. Numeric actions use the
Android constants (`DOWN=0`, `UP=1`, `MOVE=2`, mouse press `11`, mouse release `12`).

    TOUCH <action> <x> <y> <pointerId>
    MOUSE_MOVE <dx> <dy>  # agent supports this; macOS host intentionally sends no hover movement
    MOUSE_BUTTON <action> <button>
    SCROLL <horizontal> <vertical>
    KEY <action> <androidKeyCode>
    RESIZE <width> <height> <densityDpi>
    LAUNCH <package>

The transport intentionally has no authentication. Keep it behind `adb forward`; it is a PoC,
not a network-facing protocol.
