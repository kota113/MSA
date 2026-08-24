package dev.macwsa.agent;

import android.media.MediaCodec;
import android.media.MediaCodecInfo;
import android.media.MediaFormat;
import android.view.Surface;

import java.io.DataOutputStream;
import java.io.IOException;
import java.io.OutputStream;
import java.nio.ByteBuffer;

final class H264Encoder implements AutoCloseable {
    private static final byte PACKET_CONFIG = 1;
    private static final byte PACKET_FRAME = 2;
    private final MediaCodec codec;
    private final Surface inputSurface;
    private final DataOutputStream output;
    private volatile boolean running;
    private Thread drainThread;

    H264Encoder(SessionConfig config, OutputStream outputStream) throws IOException {
        output = new DataOutputStream(outputStream);
        codec = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_VIDEO_AVC);
        MediaFormat format = MediaFormat.createVideoFormat(
                MediaFormat.MIMETYPE_VIDEO_AVC, config.width, config.height);
        format.setInteger(MediaFormat.KEY_COLOR_FORMAT,
                MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface);
        format.setInteger(MediaFormat.KEY_BIT_RATE, config.bitrate);
        format.setInteger(MediaFormat.KEY_FRAME_RATE, 60);
        format.setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 1);
        format.setInteger(MediaFormat.KEY_PRIORITY, 0);
        codec.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE);
        inputSurface = codec.createInputSurface();
    }

    Surface surface() { return inputSurface; }

    void start(boolean sendStreamHeader) throws IOException {
        if (sendStreamHeader) {
            output.write("MWSA1\n".getBytes(java.nio.charset.StandardCharsets.US_ASCII));
            output.flush();
        }
        codec.start();
        running = true;
        drainThread = new Thread(this::drain, "macwsa-h264");
        drainThread.start();
    }

    private void drain() {
        MediaCodec.BufferInfo info = new MediaCodec.BufferInfo();
        try {
            while (running) {
                int index = codec.dequeueOutputBuffer(info, 10_000);
                if (index == MediaCodec.INFO_TRY_AGAIN_LATER) continue;
                if (index == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                    MediaFormat f = codec.getOutputFormat();
                    sendCsd(f.getByteBuffer("csd-0"));
                    sendCsd(f.getByteBuffer("csd-1"));
                    continue;
                }
                if (index >= 0) {
                    ByteBuffer buffer = codec.getOutputBuffer(index);
                    if (buffer != null && info.size > 0) {
                        buffer.position(info.offset);
                        buffer.limit(info.offset + info.size);
                        byte[] bytes = new byte[info.size];
                        buffer.get(bytes);
                        byte type = (info.flags & MediaCodec.BUFFER_FLAG_CODEC_CONFIG) != 0
                                ? PACKET_CONFIG : PACKET_FRAME;
                        send(type, info.flags, info.presentationTimeUs, bytes);
                    }
                    codec.releaseOutputBuffer(index, false);
                    if ((info.flags & MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) break;
                }
            }
        } catch (Exception ignored) {
            running = false;
        }
    }

    private void sendCsd(ByteBuffer value) throws IOException {
        if (value == null) return;
        ByteBuffer copy = value.duplicate();
        byte[] bytes = new byte[copy.remaining()];
        copy.get(bytes);
        send(PACKET_CONFIG, MediaCodec.BUFFER_FLAG_CODEC_CONFIG, 0, bytes);
    }

    private synchronized void send(byte type, int flags, long ptsUs, byte[] bytes) throws IOException {
        output.writeByte(type);
        output.writeByte(flags & 0xff);
        output.writeLong(ptsUs);
        output.writeInt(bytes.length);
        output.write(bytes);
        output.flush();
    }

    @Override
    public void close() {
        running = false;
        if (drainThread != null) drainThread.interrupt();
        try { codec.stop(); } catch (Exception ignored) {}
        if (drainThread != null) {
            try { drainThread.join(1_000); } catch (InterruptedException ignored) {
                Thread.currentThread().interrupt();
            }
        }
        codec.release();
        inputSurface.release();
    }
}
