package dev.msa.agent;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.net.Uri;
import android.util.Log;

public final class PackageChangeReceiver extends BroadcastReceiver {
    private static final String TAG = "MsaAgent";

    @Override
    public void onReceive(Context context, Intent intent) {
        if (!Intent.ACTION_PACKAGE_ADDED.equals(intent.getAction())
                || intent.getBooleanExtra(Intent.EXTRA_REPLACING, false)) {
            return;
        }
        Uri data = intent.getData();
        String packageName = data == null ? null : data.getSchemeSpecificPart();
        if (packageName == null || packageName.equals(context.getPackageName())) {
            return;
        }
        new PackageEventStore(context).add(packageName);
        Log.i(TAG, "Queued installed package " + packageName);
        context.startForegroundService(new Intent(context, AgentService.class));
    }
}