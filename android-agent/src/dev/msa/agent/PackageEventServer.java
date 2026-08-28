package dev.msa.agent;

import android.util.Log;

import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStreamReader;
import java.io.PrintWriter;
import java.net.InetAddress;
import java.net.ServerSocket;
import java.net.Socket;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.regex.Pattern;

final class PackageEventServer implements AutoCloseable {
    private static final String TAG = "MsaAgent";
    private static final Pattern PACKAGE_NAME = Pattern.compile("[A-Za-z0-9_]+(?:\\.[A-Za-z0-9_]+)+");
    private final PackageEventStore store;
    private final int port;
    private final ExecutorService clients = Executors.newCachedThreadPool();
    private volatile boolean closed;
    private ServerSocket listener;

    PackageEventServer(PackageEventStore store, int port) {
        this.store = store;
        this.port = port;
    }

    void start() {
        new Thread(this::acceptLoop, "msa-package-listener").start();
    }

    private void acceptLoop() {
        try (ServerSocket socket = new ServerSocket(port, 16, InetAddress.getByName("0.0.0.0"))) {
            listener = socket;
            while (!closed) {
                Socket client = socket.accept();
                client.setSoTimeout(5000);
                clients.execute(() -> serve(client));
            }
        } catch (IOException e) {
            if (!closed) Log.e(TAG, "Package listener failed", e);
        }
    }

    private void serve(Socket socket) {
        try (socket;
             BufferedReader reader = new BufferedReader(new InputStreamReader(
                     socket.getInputStream(), StandardCharsets.UTF_8));
             PrintWriter writer = new PrintWriter(socket.getOutputStream(), true, StandardCharsets.UTF_8)) {
            String command = reader.readLine();
            if ("LIST_PENDING".equals(command)) {
                List<String> packages = new ArrayList<>(store.pending());
                Collections.sort(packages);
                for (String packageName : packages) writer.println("PACKAGE " + packageName);
                writer.println("END");
            } else if (command != null && command.startsWith("ACK ")) {
                String packageName = command.substring(4);
                if (!PACKAGE_NAME.matcher(packageName).matches()) {
                    writer.println("ERROR invalid-package");
                    return;
                }
                store.acknowledge(packageName);
                writer.println("OK");
            } else {
                writer.println("ERROR invalid-command");
            }
        } catch (IOException e) {
            Log.w(TAG, "Package client failed", e);
        }
    }

    @Override
    public void close() {
        closed = true;
        try { if (listener != null) listener.close(); } catch (IOException ignored) {}
        clients.shutdownNow();
    }
}