package dev.msa.agent;

import android.content.ContentProvider;
import android.content.ContentValues;
import android.content.pm.PackageManager;
import android.database.Cursor;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.PorterDuff;
import android.graphics.drawable.Drawable;
import android.net.Uri;
import android.os.ParcelFileDescriptor;
import android.util.Log;

import java.io.FileNotFoundException;
import java.io.IOException;
import java.util.List;

/** Exports Android-rendered app icons to the adb shell as PNG. */
public final class IconProvider extends ContentProvider {
    private static final String TAG = "MsaAgent";
    private static final int ICON_SIZE = 1024;

    @Override
    public boolean onCreate() {
        return true;
    }

    @Override
    public String getType(Uri uri) {
        return "image/png";
    }

    @Override
    public ParcelFileDescriptor openFile(Uri uri, String mode) throws FileNotFoundException {
        if (!"r".equals(mode)) {
            throw new FileNotFoundException("Icons are read-only");
        }
        List<String> path = uri.getPathSegments();
        if (path.size() != 2 || !"icon".equals(path.get(0)) || path.get(1).isEmpty()) {
            throw new FileNotFoundException("Expected /icon/<package-name>");
        }
        String packageName = path.get(1);
        try {
            getContext().getPackageManager().getApplicationInfo(packageName, 0);
            ParcelFileDescriptor[] pipe = ParcelFileDescriptor.createPipe();
            Thread renderer = new Thread(
                    () -> render(packageName, pipe[1]),
                    "msa-icon-" + packageName);
            renderer.start();
            return pipe[0];
        } catch (PackageManager.NameNotFoundException | IOException e) {
            throw new FileNotFoundException(e.getMessage());
        }
    }

    private void render(String packageName, ParcelFileDescriptor output) {
        try (ParcelFileDescriptor.AutoCloseOutputStream stream =
                     new ParcelFileDescriptor.AutoCloseOutputStream(output)) {
            Drawable icon = getContext().getPackageManager().getApplicationIcon(packageName);
            Bitmap bitmap = Bitmap.createBitmap(
                    ICON_SIZE, ICON_SIZE, Bitmap.Config.ARGB_8888);
            Canvas canvas = new Canvas(bitmap);
            canvas.drawColor(Color.TRANSPARENT, PorterDuff.Mode.CLEAR);
            icon.setBounds(0, 0, ICON_SIZE, ICON_SIZE);
            icon.draw(canvas);
            if (!bitmap.compress(Bitmap.CompressFormat.PNG, 100, stream)) {
                throw new IOException("PNG compression failed");
            }
            stream.flush();
            bitmap.recycle();
        } catch (Exception e) {
            // Closing the write side makes `content read` fail or return invalid image data.
            Log.e(TAG, "Could not render icon for " + packageName, e);
        }
    }

    @Override
    public Cursor query(Uri uri, String[] projection, String selection,
                        String[] selectionArgs, String sortOrder) {
        return null;
    }

    @Override
    public Uri insert(Uri uri, ContentValues values) {
        throw new UnsupportedOperationException("Read-only provider");
    }

    @Override
    public int delete(Uri uri, String selection, String[] selectionArgs) {
        throw new UnsupportedOperationException("Read-only provider");
    }

    @Override
    public int update(Uri uri, ContentValues values, String selection,
                      String[] selectionArgs) {
        throw new UnsupportedOperationException("Read-only provider");
    }
}
