package dev.msa.agent;

import android.content.Context;
import android.util.Log;

import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStreamReader;
import java.net.InetAddress;
import java.net.ServerSocket;
import java.net.Socket;
import java.nio.charset.StandardCharsets;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

final class AgentServer implements AutoCloseable {
    private static final String TAG = "MsaAgent";
    private final Context context;
    private final int port;
    private final ExecutorService clients = Executors.newCachedThreadPool();
    private volatile boolean closed;
    private ServerSocket listener;

    AgentServer(Context context, int port) {
        this.context = context;
        this.port = port;
    }

    void start() {
        Thread thread = new Thread(this::acceptLoop, "msa-listener");
        thread.start();
    }

    private void acceptLoop() {
        try (ServerSocket socket = new ServerSocket(port, 16, InetAddress.getByName("0.0.0.0"))) {
            listener = socket;
            while (!closed) {
                Socket client = socket.accept();
                client.setTcpNoDelay(true);
                clients.execute(() -> serve(client));
            }
        } catch (IOException e) {
            if (!closed) Log.e(TAG, "Listener failed", e);
        }
    }

    private void serve(Socket socket) {
        try (socket) {
            BufferedReader reader = new BufferedReader(new InputStreamReader(
                    socket.getInputStream(), StandardCharsets.UTF_8));
            String hello = reader.readLine();
            SessionConfig config = SessionConfig.parse(hello);
            try (AppSession session = new AppSession(context, config, socket.getOutputStream())) {
                session.start();
                String line;
                while ((line = reader.readLine()) != null) {
                    try {
                        session.handleInput(line);
                    } catch (IllegalArgumentException e) {
                        Log.w(TAG, "Ignoring invalid input event: " + line, e);
                    }
                }
            }
        } catch (Exception e) {
            Log.e(TAG, "Client session failed", e);
        }
    }

    @Override
    public void close() {
        closed = true;
        try { if (listener != null) listener.close(); } catch (IOException ignored) {}
        clients.shutdownNow();
    }
}
