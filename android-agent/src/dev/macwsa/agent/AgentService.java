package dev.macwsa.agent;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.Service;
import android.content.Intent;
import android.os.IBinder;
import android.util.Log;

public final class AgentService extends Service {
    private static final String TAG = "MacWsaAgent";
    private static final String CHANNEL = "macwsa-agent";
    private AgentServer server;

    @Override
    public void onCreate() {
        super.onCreate();
        NotificationManager nm = getSystemService(NotificationManager.class);
        nm.createNotificationChannel(new NotificationChannel(
                CHANNEL, "MacWSA agent", NotificationManager.IMPORTANCE_LOW));
        Notification notification = new Notification.Builder(this, CHANNEL)
                .setSmallIcon(android.R.drawable.stat_sys_upload)
                .setContentTitle("MacWSA agent")
                .setContentText("Listening for macOS app windows")
                .setOngoing(true)
                .build();
        startForeground(1, notification);
        server = new AgentServer(this, 27183);
        server.start();
        Log.i(TAG, "Agent started on TCP 27183");
    }

    @Override
    public void onDestroy() {
        if (server != null) server.close();
        super.onDestroy();
    }

    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }
}
