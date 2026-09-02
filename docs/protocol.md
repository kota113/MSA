# Wire protocol

One TCP connection owns one Android app session. The macOS client first sends one UTF-8 line:

    HELLO <package> <width> <height> <densityDpi> <bitrate>

The Android agent replies with `MSA01\n`, followed by framed packets:

| Field | Size | Encoding |
|---|---:|---|
| kind | 1 | 1 = codec config, 2 = picture, 3 = clipboard |
| MediaCodec flags | 1 | low 8 bits |
| presentation time | 8 | microseconds, big endian |
| payload length | 4 | big endian |
| payload | N | Packet-kind-specific bytes |

Input travels in the opposite direction as newline-delimited commands. Numeric actions use the
Android constants (`DOWN=0`, `UP=1`, `MOVE=2`, mouse press `11`, mouse release `12`).

    TOUCH <action> <x> <y> <pointerId>
    MOUSE_MOVE <dx> <dy>  # agent supports this; macOS host intentionally sends no hover movement
    MOUSE_BUTTON <action> <button>
    SCROLL <horizontal> <vertical>
    KEY <action> <androidKeyCode>
    RESIZE <width> <height> <densityDpi>
    LAUNCH <package>
    CLIPBOARD CLEAR
    CLIPBOARD <mime-type> <base64-payload>

Clipboard commands currently accept UTF-8 `text/*` and `image/*` payloads up to 8 MiB. Images
copied from macOS are normalized to PNG.

Android-to-macOS clipboard updates use the same binary packet header as video, with `kind = 3`.
For a clear event, flags and payload length are zero. Otherwise flags is 1 and the payload is a
UTF-8 MIME type, one newline byte, and the raw clipboard bytes. The Android agent serializes these
packets with video writes so packet boundaries cannot interleave.

The transport intentionally has no authentication yet. Keep it behind `adb forward` — it is
not designed to be exposed to a network.

## Package events

TCP port `27184` is reserved for package installation events and is also exposed only through
`adb forward`. Events remain in device-protected storage until macOS acknowledges successful
bundle generation. Each connection contains one request and one response:

    LIST_PENDING
    PACKAGE com.example.app
    END

    ACK com.example.app
    OK
