package local.pad2kbd.pogopair;

import android.bluetooth.BluetoothDevice;
import android.bluetooth.BluetoothGatt;
import android.bluetooth.BluetoothGattCallback;
import android.bluetooth.BluetoothGattCharacteristic;
import android.bluetooth.BluetoothGattService;
import android.bluetooth.BluetoothProfile;
import android.content.Context;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;
import java.util.UUID;

/**
 * "HidCtl tune MAC": gives the keyboard its own preferred BLE connection parameters (7.5 ms).
 *
 * Android applies them only when it reads them during a service discovery, which a paired keyboard
 * gets only at pairing; the values live in memory until the next reboot, so after a reboot the link
 * stays at ~45 ms (docs/ROM-NATIVE.md). This connects a GATT client, reads the keyboard's
 * Peripheral Preferred Connection Parameters, lets the stack settle and, if the link is slower,
 * requests them with the same adjustment Android makes (maximum at least 11.25 ms). The request
 * call is hidden from apps, which is why this runs as root via app_process. The link keeps the
 * parameters after this client closes. Exits 0 when the link is at the keyboard's parameters.
 */
final class LinkTuner {
    private static final String TAG = "pad2kbd";
    private static final UUID GAP_SERVICE = UUID.fromString("00001800-0000-1000-8000-00805f9b34fb");
    private static final UUID PREFERRED_PARAMS = UUID.fromString("00002a04-0000-1000-8000-00805f9b34fb");
    private static final long BOND_WAIT_MS = 90000;    // the ROM or the module may still be pairing
    private static final long TOTAL_MS = 150000;
    private static final long SETTLE_MS = 3000;        // the stack's own updates after a connect
    private static final long RESULT_MS = 4000;
    // Android raises a preferred maximum below this (11.25 ms) to it (BTM_BLE_CONN_INT_MIN_LIMIT)
    private static final int MIN_LIMIT_INTERVAL = 9;

    private final Context context;
    private final BluetoothDevice device;
    private final Handler handler = new Handler(Looper.getMainLooper());
    private BluetoothGatt gatt;
    private volatile int interval;   // in 1.25 ms units; 0 = not known
    private volatile int[] preferred; // min, max (adjusted), latency, timeout
    private boolean requested;
    private int waits;

    LinkTuner(Context context, BluetoothDevice device) {
        this.context = context;
        this.device = device;
    }

    void run() {
        handler.postDelayed(() -> finish(3, "timeout"), TOTAL_MS);
        waitForBond(System.currentTimeMillis());
        Looper.loop();
    }

    private void waitForBond(long since) {
        if (device.getBondState() == BluetoothDevice.BOND_BONDED) {
            gatt = device.connectGatt(context, false, callback, BluetoothDevice.TRANSPORT_LE);
            if (gatt == null) finish(4, "connectGatt failed");
        } else if (System.currentTimeMillis() - since > BOND_WAIT_MS) {
            finish(5, "keyboard not paired");
        } else {
            handler.postDelayed(() -> waitForBond(since), 1000);
        }
    }

    private final BluetoothGattCallback callback = new BluetoothGattCallback() {
        @Override public void onConnectionStateChange(BluetoothGatt g, int status, int state) {
            if (state == BluetoothProfile.STATE_CONNECTED) {
                if (!g.discoverServices()) handler.post(() -> finish(7, "service discovery didn't start"));
                handler.postDelayed(() -> decide(), SETTLE_MS);
            } else if (state == BluetoothProfile.STATE_DISCONNECTED) {
                handler.post(() -> finish(6, "keyboard disconnected (status " + status + ")"));
            }
        }

        @Override public void onServicesDiscovered(BluetoothGatt g, int status) {
            BluetoothGattService gap = g.getService(GAP_SERVICE);
            BluetoothGattCharacteristic c = gap != null ? gap.getCharacteristic(PREFERRED_PARAMS) : null;
            if (status != BluetoothGatt.GATT_SUCCESS || c == null || !g.readCharacteristic(c)) {
                handler.post(() -> finish(7, "can't read the keyboard's preferred parameters"));
            }
        }

        @Override public void onCharacteristicRead(BluetoothGatt g, BluetoothGattCharacteristic c,
                byte[] value, int status) {
            if (!PREFERRED_PARAMS.equals(c.getUuid())) return;
            int[] p = status == BluetoothGatt.GATT_SUCCESS ? parse(value) : null;
            if (p == null) handler.post(() -> finish(7, "keyboard's preferred parameters unusable"));
            preferred = p;
        }

        @SuppressWarnings("deprecation")
        @Override public void onCharacteristicRead(BluetoothGatt g, BluetoothGattCharacteristic c, int status) {
            // Called instead of the method above before Android 13
            if (preferred == null) onCharacteristicRead(g, c, c.getValue(), status);
        }

        // Hidden in BluetoothGattCallback; called for every client on the link
        public void onConnectionUpdated(BluetoothGatt g, int newInterval, int latency, int timeout, int status) {
            if (status != BluetoothGatt.GATT_SUCCESS) return;
            interval = newInterval;
            int[] p = preferred;
            if (requested && p != null && newInterval <= p[1]) {
                handler.post(() -> finish(0, "interval now " + newInterval * 1.25 + " ms, latency " + latency));
            }
        }
    };

    /** Peripheral Preferred Connection Parameters, adjusted like Android (bta_hh_le.cc). */
    private static int[] parse(byte[] v) {
        if (v == null || v.length != 8) return null;
        int min = (v[0] & 0xff) | (v[1] & 0xff) << 8, max = (v[2] & 0xff) | (v[3] & 0xff) << 8;
        int latency = (v[4] & 0xff) | (v[5] & 0xff) << 8, timeout = (v[6] & 0xff) | (v[7] & 0xff) << 8;
        if (timeout == 0xffff) timeout = 500;            // no preference: 5 s
        if (max < MIN_LIMIT_INTERVAL) max = MIN_LIMIT_INTERVAL;
        if (min < 6 || max > 3200 || min > max || latency > 499 || timeout < 10 || timeout > 3200) return null;
        return new int[] {min, max, latency, timeout};
    }

    private void decide() {
        int[] p = preferred;
        if (p == null) {
            if (++waits <= 3) { handler.postDelayed(() -> decide(), 1000); return; }
            finish(7, "keyboard's preferred parameters not read");
            return;
        }
        String want = p[0] * 1.25 + "-" + p[1] * 1.25 + " ms, latency " + p[2];
        if (interval != 0 && interval <= p[1]) {
            finish(0, "already " + interval * 1.25 + " ms (keyboard prefers " + want + ")");
            return;
        }
        try {
            requested = (Boolean) BluetoothGatt.class.getMethod("requestLeConnectionUpdate",
                    int.class, int.class, int.class, int.class, int.class, int.class)
                    .invoke(gatt, p[0], p[1], p[2], p[3], 0, 0);
        } catch (Throwable t) {
            finish(8, "can't request " + want + ": " + t);
            return;
        }
        if (!requested) { finish(8, "request for " + want + " refused"); return; }
        String was = interval == 0 ? "unknown" : interval * 1.25 + " ms";
        handler.postDelayed(() -> finish(interval != 0 && interval <= p[1] ? 0 : 9,
                "requested " + want + " (was " + was + "), interval now "
                        + (interval == 0 ? "unknown" : interval * 1.25 + " ms")), RESULT_MS);
    }

    private void finish(int code, String message) {
        Log.i(TAG, "HidCtl tune: " + message);
        System.out.println("tune: " + message);
        if (gatt != null) gatt.close();
        System.exit(code);
    }
}
