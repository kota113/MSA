package dev.msa.agent;

import android.content.ContentProvider;
import android.content.ContentValues;
import android.database.Cursor;
import android.database.MatrixCursor;
import android.net.Uri;
import android.os.ParcelFileDescriptor;
import android.provider.OpenableColumns;

import java.io.File;
import java.io.FileNotFoundException;
import java.io.IOException;
import java.nio.file.Files;
import java.util.UUID;

public final class ClipboardImageProvider extends ContentProvider {
    static final String AUTHORITY = "dev.msa.agent.clipboard";

    static Uri store(android.content.Context context, String mimeType, byte[] bytes) throws IOException {
        File directory = new File(context.createDeviceProtectedStorageContext().getCacheDir(), "clipboard");
        if (!directory.exists() && !directory.mkdirs()) {
            throw new IOException("Could not create clipboard cache");
        }
        File file = new File(directory, UUID.randomUUID().toString());
        Files.write(file.toPath(), bytes);
        prune(directory, file);
        return new Uri.Builder().scheme("content").authority(AUTHORITY)
                .appendPath(file.getName()).appendQueryParameter("type", mimeType).build();
    }

    private static void prune(File directory, File current) {
        File[] files = directory.listFiles();
        if (files == null) return;
        long cutoff = System.currentTimeMillis() - 60 * 60 * 1000L;
        for (File file : files) {
            if (!file.equals(current) && file.lastModified() < cutoff) file.delete();
        }
    }

    @Override
    public boolean onCreate() { return true; }

    @Override
    public String getType(Uri uri) { return uri.getQueryParameter("type"); }

    @Override
    public ParcelFileDescriptor openFile(Uri uri, String mode) throws FileNotFoundException {
        if (!"r".equals(mode) || uri.getPathSegments().size() != 1) {
            throw new FileNotFoundException("Invalid clipboard URI");
        }
        return ParcelFileDescriptor.open(fileFor(uri), ParcelFileDescriptor.MODE_READ_ONLY);
    }

    private android.content.Context providerContext() throws FileNotFoundException {
        android.content.Context context = getContext();
        if (context == null) throw new FileNotFoundException("Provider is unavailable");
        return context;
    }

    @Override
    public Cursor query(Uri uri, String[] projection, String selection, String[] selectionArgs,
                        String sortOrder) {
        try {
            File file = fileFor(uri);
            String[] columns = projection == null
                    ? new String[] {OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE} : projection;
            MatrixCursor cursor = new MatrixCursor(columns, 1);
            MatrixCursor.RowBuilder row = cursor.newRow();
            for (String column : columns) {
                if (OpenableColumns.DISPLAY_NAME.equals(column)) row.add("clipboard-image");
                else if (OpenableColumns.SIZE.equals(column)) row.add(file.length());
                else row.add(null);
            }
            return cursor;
        } catch (FileNotFoundException e) {
            return null;
        }
    }

    private File fileFor(Uri uri) throws FileNotFoundException {
        if (uri.getPathSegments().size() != 1) {
            throw new FileNotFoundException("Invalid clipboard URI");
        }
        File directory = new File(providerContext().createDeviceProtectedStorageContext().getCacheDir(),
                "clipboard");
        File file = new File(directory, uri.getLastPathSegment());
        if (!file.getParentFile().equals(directory) || !file.isFile()) {
            throw new FileNotFoundException("Clipboard image not found");
        }
        return file;
    }
    @Override
    public Uri insert(Uri uri, ContentValues values) { throw new UnsupportedOperationException(); }
    @Override
    public int delete(Uri uri, String selection, String[] selectionArgs) { return 0; }
    @Override
    public int update(Uri uri, ContentValues values, String selection, String[] selectionArgs) {
        return 0;
    }
}