package dev.msa.agent;

import android.content.ClipData;
import android.content.ClipDescription;
import android.content.ClipboardManager;
import android.content.Context;
import android.net.Uri;
import android.os.PersistableBundle;
import android.util.Base64;
import android.util.Log;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.Arrays;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.RejectedExecutionException;

final class ClipboardBridge implements AutoCloseable {
    private static final String TAG = "MsaAgent";
    private static final int MAX_BYTES = 8 * 1024 * 1024;
    private final Context context;
    private final ClipboardManager clipboard;
    private final PacketWriter output;
    private final ExecutorService executor = Executors.newSingleThreadExecutor();
    private final ClipboardManager.OnPrimaryClipChangedListener listener = this::scheduleExport;
    private volatile byte[] lastImportedDigest;

    ClipboardBridge(Context context, PacketWriter output) {
        this.context = context;
        this.output = output;
        clipboard = context.getSystemService(ClipboardManager.class);
        clipboard.addPrimaryClipChangedListener(listener);
    }

    private void scheduleExport() {
        try {
            executor.execute(this::exportClipboard);
        } catch (RejectedExecutionException ignored) {
            // The session closed while a clipboard callback was being delivered.
        }
    }

    void handleCommand(String line) throws IOException {
        String[] parts = line.split(" ", 3);
        if (parts.length == 2 && "CLEAR".equals(parts[1])) {
            lastImportedDigest = digest("", new byte[0]);
            clipboard.clearPrimaryClip();
            return;
        }
        if (parts.length != 3 || !isSupportedMimeType(parts[1])) {
            throw new IllegalArgumentException("Invalid CLIPBOARD command");
        }
        byte[] bytes = Base64.decode(parts[2], Base64.DEFAULT);
        if (bytes.length > MAX_BYTES) throw new IllegalArgumentException("Clipboard payload too large");
        lastImportedDigest = digest(parts[1], bytes);
        ClipData clip;
        if (parts[1].startsWith("text/")) {
            clip = ClipData.newPlainText("macOS clipboard", new String(bytes, StandardCharsets.UTF_8));
        } else {
            Uri uri = ClipboardImageProvider.store(context, parts[1], bytes);
            clip = ClipData.newUri(context.getContentResolver(), "macOS clipboard", uri);
        }
        PersistableBundle extras = new PersistableBundle();
        extras.putBoolean(ClipDescription.EXTRA_IS_REMOTE_DEVICE, true);
        clip.getDescription().setExtras(extras);
        clipboard.setPrimaryClip(clip);
    }

    private void exportClipboard() {
        try {
            if (!clipboard.hasPrimaryClip()) {
                byte[] digest = digest("", new byte[0]);
                if (Arrays.equals(lastImportedDigest, digest)) {
                    lastImportedDigest = null;
                    return;
                }
                output.sendClipboardClear();
                return;
            }
            ClipData clip = clipboard.getPrimaryClip();
            if (clip == null || clip.getItemCount() == 0) return;
            ClipDescription description = clip.getDescription();
            if (description.getExtras() != null
                    && description.getExtras().getBoolean(ClipDescription.EXTRA_IS_REMOTE_DEVICE)) {
                lastImportedDigest = null;
                return;
            }
            String mimeType;
            byte[] bytes;
            if (description.hasMimeType("image/*")) {
                Uri uri = clip.getItemAt(0).getUri();
                if (uri == null) return;
                mimeType = context.getContentResolver().getType(uri);
                if (mimeType == null || !mimeType.startsWith("image/")) mimeType = "image/png";
                try (InputStream input = context.getContentResolver().openInputStream(uri)) {
                    if (input == null) return;
                    bytes = readLimited(input);
                }
            } else if (description.hasMimeType("text/*")) {
                CharSequence text = clip.getItemAt(0).coerceToText(context);
                if (text == null) return;
                mimeType = "text/plain";
                bytes = text.toString().getBytes(StandardCharsets.UTF_8);
                if (bytes.length > MAX_BYTES) return;
            } else {
                return;
            }
            byte[] digest = digest(mimeType, bytes);
            if (Arrays.equals(lastImportedDigest, digest)) {
                lastImportedDigest = null;
                return;
            }
            output.sendClipboard(mimeType, bytes);
        } catch (Exception e) {
            Log.w(TAG, "Could not synchronize Android clipboard", e);
        }
    }

    private static byte[] readLimited(InputStream input) throws IOException {
        ByteArrayOutputStream output = new ByteArrayOutputStream();
        byte[] buffer = new byte[16 * 1024];
        int total = 0;
        int count;
        while ((count = input.read(buffer)) != -1) {
            total += count;
            if (total > MAX_BYTES) throw new IOException("Clipboard payload too large");
            output.write(buffer, 0, count);
        }
        return output.toByteArray();
    }

    private static boolean isSupportedMimeType(String mimeType) {
        return mimeType.length() <= 127
                && (mimeType.startsWith("text/") || mimeType.startsWith("image/"));
    }

    private static byte[] digest(String mimeType, byte[] bytes) {
        try {
            MessageDigest digest = MessageDigest.getInstance("SHA-256");
            digest.update(mimeType.getBytes(StandardCharsets.UTF_8));
            digest.update((byte) 0);
            return digest.digest(bytes);
        } catch (java.security.NoSuchAlgorithmException e) {
            throw new AssertionError(e);
        }
    }

    @Override
    public void close() {
        clipboard.removePrimaryClipChangedListener(listener);
        executor.shutdownNow();
    }
}