package dev.macwsa.agent;

final class SessionConfig {
    final String packageName;
    final int width;
    final int height;
    final int densityDpi;
    final int bitrate;

    private SessionConfig(String packageName, int width, int height, int densityDpi, int bitrate) {
        this.packageName = packageName;
        this.width = width;
        this.height = height;
        this.densityDpi = densityDpi;
        this.bitrate = bitrate;
    }

    static SessionConfig parse(String line) {
        if (line == null) throw new IllegalArgumentException("Missing HELLO");
        String[] p = line.trim().split("\\s+");
        if (p.length != 6 || !p[0].equals("HELLO")) {
            throw new IllegalArgumentException("Expected: HELLO package width height density bitrate");
        }
        int width = Integer.parseInt(p[2]);
        int height = Integer.parseInt(p[3]);
        int density = Integer.parseInt(p[4]);
        int bitrate = Integer.parseInt(p[5]);
        if (width < 64 || height < 64 || density < 72 || bitrate < 100_000) {
            throw new IllegalArgumentException("Invalid stream dimensions/density/bitrate");
        }
        return new SessionConfig(p[1], width, height, density, bitrate);
    }

    SessionConfig withDimensions(int width, int height) {
        return new SessionConfig(packageName, width, height, densityDpi, bitrate);
    }
}
