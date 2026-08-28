package dev.msa.agent;

import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.pm.PackageInfo;
import android.content.pm.PackageManager;

import java.util.Collections;
import java.util.HashSet;
import java.util.List;
import java.util.Set;

final class PackageEventStore {
    private static final String PREFERENCES = "package-events";
    private static final String PENDING = "pending";
    private static final String KNOWN = "known-launchable-packages";
    private static final Object LOCK = new Object();
    private final Context context;
    private final SharedPreferences preferences;

    PackageEventStore(Context context) {
        this.context = context.getApplicationContext();
        Context storage = this.context.createDeviceProtectedStorageContext();
        preferences = storage.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE);
    }

    void add(String packageName) {
        synchronized (LOCK) {
            Set<String> pending = new HashSet<>(preferences.getStringSet(PENDING, Collections.emptySet()));
            pending.add(packageName);
            preferences.edit().putStringSet(PENDING, pending).commit();
        }
    }

    Set<String> pending() {
        synchronized (LOCK) {
            Set<String> current = launchablePackages();
            Set<String> known = new HashSet<>(preferences.getStringSet(KNOWN, current));
            Set<String> pending = new HashSet<>(preferences.getStringSet(PENDING, Collections.emptySet()));
            Set<String> added = new HashSet<>(current);
            added.removeAll(known);
            pending.addAll(added);
            pending.retainAll(current);
            preferences.edit().putStringSet(KNOWN, current).putStringSet(PENDING, pending).commit();
            return pending;
        }
    }

    void acknowledge(String packageName) {
        synchronized (LOCK) {
            Set<String> pending = new HashSet<>(preferences.getStringSet(PENDING, Collections.emptySet()));
            if (pending.remove(packageName)) {
                preferences.edit().putStringSet(PENDING, pending).commit();
            }
        }
    }

    private Set<String> launchablePackages() {
        PackageManager packageManager = context.getPackageManager();
        List<PackageInfo> packages = packageManager.getInstalledPackages(0);
        Set<String> result = new HashSet<>();
        for (PackageInfo packageInfo : packages) {
            String packageName = packageInfo.packageName;
            Intent launcher = packageManager.getLaunchIntentForPackage(packageName);
            if (launcher != null && !context.getPackageName().equals(packageName)) {
                result.add(packageName);
            }
        }
        return result;
    }
}