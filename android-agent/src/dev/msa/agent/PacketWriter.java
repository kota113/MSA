package dev.msa.agent;

import java.io.DataOutputStream;
import java.io.IOException;
import java.io.OutputStream;
import java.nio.charset.StandardCharsets;

final class PacketWriter {
    static final byte PACKET_CONFIG = 1;
    static final byte PACKET_FRAME = 2;
    static final byte PACKET_CLIPBOARD = 3;

    private final DataOutputStream output;

    PacketWriter(OutputStream output) {
        this.output = new DataOutputStream(output);
    }

    synchronized void sendStreamHeader() throws IOException {
        output.write("MSA01\n".getBytes(StandardCharsets.US_ASCII));
        output.flush();
    }

    synchronized void send(byte type, int flags, long ptsUs, byte[] bytes) throws IOException {
        output.writeByte(type);
        output.writeByte(flags & 0xff);
        output.writeLong(ptsUs);
        output.writeInt(bytes.length);
        output.write(bytes);
        output.flush();
    }

    void sendClipboard(String mimeType, byte[] bytes) throws IOException {
        byte[] mime = mimeType.getBytes(StandardCharsets.UTF_8);
        byte[] payload = new byte[mime.length + 1 + bytes.length];
        System.arraycopy(mime, 0, payload, 0, mime.length);
        payload[mime.length] = '\n';
        System.arraycopy(bytes, 0, payload, mime.length + 1, bytes.length);
        send(PACKET_CLIPBOARD, 1, 0, payload);
    }

    void sendClipboardClear() throws IOException {
        send(PACKET_CLIPBOARD, 0, 0, new byte[0]);
    }
}