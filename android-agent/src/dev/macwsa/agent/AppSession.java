package dev.macwsa.agent;

import android.app.ActivityOptions;
import android.companion.AssociationInfo;
import android.companion.CompanionDeviceManager;
import android.companion.virtual.VirtualDeviceManager;
import android.companion.virtual.VirtualDeviceManager.VirtualDevice;
import android.companion.virtual.VirtualDeviceParams;
import android.content.Context;
import android.content.Intent;
import android.hardware.display.DisplayManager;
import android.hardware.display.VirtualDisplay;
import android.hardware.display.VirtualDisplayConfig;
import android.hardware.input.VirtualKeyEvent;
import android.hardware.input.VirtualKeyboard;
import android.hardware.input.VirtualKeyboardConfig;
import android.hardware.input.VirtualMouse;
import android.hardware.input.VirtualMouseButtonEvent;
import android.hardware.input.VirtualMouseConfig;
import android.hardware.input.VirtualMouseRelativeEvent;
import android.hardware.input.VirtualMouseScrollEvent;
import android.hardware.input.VirtualTouchEvent;
import android.hardware.input.VirtualTouchscreen;
import android.hardware.input.VirtualTouchscreenConfig;
import android.os.SystemClock;
import android.view.KeyEvent;

import java.io.OutputStream;
import java.util.List;

final class AppSession implements AutoCloseable {
    private final Context context;
    private final SessionConfig config;
    private final OutputStream output;
    private H264Encoder encoder;
    private VirtualDevice device;
    private VirtualDisplay display;
    private VirtualTouchscreen touchscreen;
    private VirtualMouse mouse;
    private VirtualKeyboard keyboard;
    private int currentWidth;
    private int currentHeight;
    private int currentDensityDpi;

    AppSession(Context context, SessionConfig config, OutputStream output) throws Exception {
        this.context = context;
        this.config = config;
        this.output = output;
        this.encoder = new H264Encoder(config, output);
        this.currentWidth = config.width;
        this.currentHeight = config.height;
        this.currentDensityDpi = config.densityDpi;
    }

    void start() throws Exception {
        CompanionDeviceManager cdm = context.getSystemService(CompanionDeviceManager.class);
        List<AssociationInfo> associations = cdm.getMyAssociations();
        if (associations.isEmpty()) {
            throw new IllegalStateException("No CDM association; run scripts/provision-emulator.sh");
        }
        int associationId = associations.get(0).getId();
        VirtualDeviceManager vdm = context.getSystemService(VirtualDeviceManager.class);
        VirtualDeviceParams params = new VirtualDeviceParams.Builder()
                .setName("MacWSA:" + config.packageName)
                .setLockState(VirtualDeviceParams.LOCK_STATE_ALWAYS_UNLOCKED)
                .build();
        device = vdm.createVirtualDevice(associationId, params);
        device.setShowPointerIcon(false);

        VirtualDisplayConfig displayConfig = new VirtualDisplayConfig.Builder(
                "MacWSA:" + config.packageName, config.width, config.height, config.densityDpi)
                .setSurface(encoder.surface())
                .setFlags(DisplayManager.VIRTUAL_DISPLAY_FLAG_PUBLIC
                        | DisplayManager.VIRTUAL_DISPLAY_FLAG_OWN_CONTENT_ONLY
                        | DisplayManager.VIRTUAL_DISPLAY_FLAG_TRUSTED)
                .build();
        display = device.createVirtualDisplay(displayConfig, null, null);
        if (display == null) throw new IllegalStateException("Virtual display creation failed");
        int displayId = display.getDisplay().getDisplayId();

        createTouchscreen(config.width, config.height, displayId);
        mouse = device.createVirtualMouse(new VirtualMouseConfig.Builder()
                .setAssociatedDisplayId(displayId).setInputDeviceName(inputName("Mouse", displayId))
                .setVendorId(0x18d1).setProductId(0x4ee8).build());
        keyboard = device.createVirtualKeyboard(new VirtualKeyboardConfig.Builder()
                .setAssociatedDisplayId(displayId).setInputDeviceName(inputName("Keyboard", displayId))
                .setVendorId(0x18d1).setProductId(0x4ee9).build());

        encoder.start(true);
        launch(config.packageName, displayId);
    }

    private void launch(String packageName, int displayId) {
        Intent intent = context.getPackageManager().getLaunchIntentForPackage(packageName);
        if (intent == null) throw new IllegalArgumentException("Package has no launch activity: " + packageName);
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_MULTIPLE_TASK);
        ActivityOptions options = ActivityOptions.makeBasic();
        options.setLaunchDisplayId(displayId);
        context.startActivity(intent, options.toBundle());
    }

    void handleInput(String line) throws Exception {
        String[] p = line.trim().split("\\s+");
        if (p.length == 0) return;
        switch (p[0]) {
            case "TOUCH" -> sendTouch(p);
            case "MOUSE_MOVE" -> mouse.sendRelativeEvent(new VirtualMouseRelativeEvent.Builder()
                    .setRelativeX(Float.parseFloat(p[1])).setRelativeY(Float.parseFloat(p[2]))
                    .setEventTimeNanos(now()).build());
            case "MOUSE_BUTTON" -> mouse.sendButtonEvent(new VirtualMouseButtonEvent.Builder()
                    .setAction(Integer.parseInt(p[1])).setButtonCode(Integer.parseInt(p[2]))
                    .setEventTimeNanos(now()).build());
            case "SCROLL" -> sendScroll(p);
            case "KEY" -> keyboard.sendKeyEvent(new VirtualKeyEvent.Builder()
                    .setAction(Integer.parseInt(p[1])).setKeyCode(Integer.parseInt(p[2]))
                    .setEventTimeNanos(now()).build());
            case "RESIZE" -> resize(Integer.parseInt(p[1]), Integer.parseInt(p[2]),
                    Integer.parseInt(p[3]));
            case "LAUNCH" -> launch(p[1], display.getDisplay().getDisplayId());
            default -> throw new IllegalArgumentException("Unknown input command: " + p[0]);
        }
    }

    private void sendTouch(String[] p) {
        int action = Integer.parseInt(p[1]);
        touchscreen.sendTouchEvent(new VirtualTouchEvent.Builder()
                .setPointerId(Integer.parseInt(p[4]))
                .setToolType(VirtualTouchEvent.TOOL_TYPE_FINGER)
                .setAction(action)
                .setX(Float.parseFloat(p[2])).setY(Float.parseFloat(p[3]))
                .setPressure(action == VirtualTouchEvent.ACTION_UP ? 0f : 1f)
                .setEventTimeNanos(now()).build());
    }

    private void resize(int width, int height, int densityDpi) throws Exception {
        if (width < 64 || height < 64 || width > 4096 || height > 4096
                || densityDpi < 72 || densityDpi > 640) {
            throw new IllegalArgumentException("Invalid resize dimensions or density");
        }
        if (currentWidth == width && currentHeight == height
                && currentDensityDpi == densityDpi) return;

        H264Encoder replacement = new H264Encoder(
                config.withDisplay(width, height, densityDpi), output);
        int displayId = display.getDisplay().getDisplayId();
        touchscreen.close();
        touchscreen = null;
        display.setSurface(null);
        encoder.close();
        display.resize(width, height, densityDpi);
        display.setSurface(replacement.surface());
        encoder = replacement;
        createTouchscreen(width, height, displayId);
        encoder.start(false);
        currentWidth = width;
        currentHeight = height;
        currentDensityDpi = densityDpi;
    }

    private void createTouchscreen(int width, int height, int displayId) {
        touchscreen = device.createVirtualTouchscreen(new VirtualTouchscreenConfig.Builder(width, height)
                .setAssociatedDisplayId(displayId).setInputDeviceName(inputName("Touch", displayId))
                .setVendorId(0x18d1).setProductId(0x4ee7).build());
    }

    private static String inputName(String type, int displayId) {
        return "MacWSA " + type + " display-" + displayId;
    }

    private void sendScroll(String[] p) {
        float x = clampScroll(Float.parseFloat(p[1]));
        float y = clampScroll(Float.parseFloat(p[2]));
        if (x == 0f && y == 0f) return;
        mouse.sendScrollEvent(new VirtualMouseScrollEvent.Builder()
                .setXAxisMovement(x).setYAxisMovement(y)
                .setEventTimeNanos(now()).build());
    }

    private static float clampScroll(float value) {
        return Math.max(-1f, Math.min(1f, value));
    }

    private static long now() { return SystemClock.uptimeMillis() * 1_000_000L; }

    @Override
    public void close() {
        if (keyboard != null) keyboard.close();
        if (mouse != null) mouse.close();
        if (touchscreen != null) touchscreen.close();
        if (display != null) display.release();
        if (device != null) device.close();
        if (encoder != null) encoder.close();
    }
}
