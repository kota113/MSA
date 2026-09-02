package dev.msa.agent;

import android.media.MediaCodec;
import android.media.MediaCodecInfo;
import android.media.MediaFormat;
import android.view.Surface;

import java.io.IOException;
import java.nio.ByteBuffer;

final class H264Encoder implements AutoCloseable {
    private final MediaCodec codec;
    private final Surface inputSurface;
    private final PacketWriter output;
    private volatile boolean running;
    private Thread drainThread;

    H264Encoder(SessionConfig config, PacketWriter output) throws IOException {
        this.output = output;
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
            output.sendStreamHeader();
        }
        codec.start();
        running = true;
        drainThread = new Thread(this::drain, "msa-h264");
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
                                ? PacketWriter.PACKET_CONFIG : PacketWriter.PACKET_FRAME;
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
        send(PacketWriter.PACKET_CONFIG, MediaCodec.BUFFER_FLAG_CODEC_CONFIG, 0, bytes);
    }

    private void send(byte type, int flags, long ptsUs, byte[] bytes) throws IOException {
        output.send(type, flags, ptsUs, bytes);
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
