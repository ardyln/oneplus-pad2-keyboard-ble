package local.pad2kbd.pogopair;

import android.app.Service;
import android.bluetooth.BluetoothAdapter;
import android.bluetooth.BluetoothDevice;
import android.bluetooth.BluetoothGatt;
import android.bluetooth.BluetoothGattCallback;
import android.bluetooth.BluetoothProfile;
import android.content.Intent;
import android.content.SharedPreferences;
import android.os.Handler;
import android.os.IBinder;
import android.os.Looper;
import android.util.Log;

/**
 * Keeps a GATT client open so the touchpad doesn't run on a slow BLE interval.
 *
 * Android connects at ~45 ms and only switches to the keyboard's preferred 7.5 ms after it has read
 * the keyboard's preferred connection parameters, which it does at pairing and forgets at reboot
 * (docs/ROM-NATIVE.md). On each detach the module's root helper ("HidCtl tune") applies them; this
 * is the fallback for when it can't, and for reconnects in between: after the stack and the helper
 * have settled, it requests the high-priority interval (11.25-15 ms) only when the link is still
 * slower than that. A faster link is left alone.
 * The MAC arrives as an intent extra and is remembered so a sticky restart (null intent) still works.
 */
public final class LatencyService extends Service {
    private static final String TAG = PairReceiver.TAG;
    private static final long MAX_RETRY_MS = 30000;
    // Time for the stack's own updates after a connect (45 ms first, the keyboard's 7.5 ms ~1 s later)
    // and for "HidCtl tune" (applies the keyboard's parameters ~3.5 s after it connects)
    private static final long SETTLE_MS = 6000;
    // CONNECTION_PRIORITY_HIGH's slowest interval (12 x 1.25 ms = 15 ms, AOSP default)
    private static final int HIGH_MAX_INTERVAL = 12;
    private static final int MAX_REQUESTS_PER_CONNECTION = 3;
    private final Handler handler = new Handler(Looper.getMainLooper());
    private BluetoothGatt gatt;
    private String mac;
    private boolean stopped;
    private long retryMs = 1500;
    private volatile int interval;   // last interval reported for this link, in 1.25 ms units; 0 = not known
    private int requests;

    private final Runnable check = () -> checkInterval();

    private final BluetoothGattCallback callback = new BluetoothGattCallback() {
        @Override public void onConnectionStateChange(BluetoothGatt current, int status, int state) {
            Log.i(TAG, "Latency GATT state=" + state + " status=" + status);
            if (current != gatt) return;
            if (state == BluetoothProfile.STATE_CONNECTED) {
                retryMs = 1500;
                requests = 0;
                handler.removeCallbacks(check);
                handler.postDelayed(check, SETTLE_MS);
            } else if (state == BluetoothProfile.STATE_DISCONNECTED && !stopped) {
                interval = 0;
                handler.removeCallbacks(check);
                handler.postDelayed(() -> connect(), retryMs);
                retryMs = Math.min(retryMs * 2, MAX_RETRY_MS);
            }
        }

        // Hidden in BluetoothGattCallback, but called for every client on the link, including
        // updates the HID host or the keyboard started.
        public void onConnectionUpdated(BluetoothGatt current, int newInterval, int latency, int timeout,
                int status) {
            if (current != gatt || status != BluetoothGatt.GATT_SUCCESS) return;
            interval = newInterval;
            Log.i(TAG, "BLE interval now " + newInterval * 1.25 + " ms, latency " + latency);
            // Something made the link slow again: check once things have settled
            if (newInterval > HIGH_MAX_INTERVAL) {
                handler.removeCallbacks(check);
                handler.postDelayed(check, SETTLE_MS);
            }
        }
    };

    @Override public int onStartCommand(Intent intent, int flags, int startId) {
        stopped = false;
        SharedPreferences prefs = getSharedPreferences("state", MODE_PRIVATE);
        String extra = intent != null ? intent.getStringExtra("mac") : null;
        if (extra != null && BluetoothAdapter.checkBluetoothAddress(extra)) {
            mac = extra;
            prefs.edit().putString("mac", mac).apply();
        } else if (mac == null) {
            mac = prefs.getString("mac", null);
        }
        if (mac == null) {
            Log.w(TAG, "LatencyService started without a MAC; stopping");
            stopSelf();
            return START_NOT_STICKY;
        }
        retryMs = 1500;
        connect();
        return START_STICKY;
    }

    private void connect() {
        if (stopped) return;
        BluetoothAdapter adapter = BluetoothAdapter.getDefaultAdapter();
        if (adapter == null || !adapter.isEnabled()) {
            handler.postDelayed(() -> connect(), 2000);
            return;
        }
        BluetoothDevice device = adapter.getRemoteDevice(mac);
        if (device.getBondState() != BluetoothDevice.BOND_BONDED) {
            // Pairing may still be in progress (on ROMs that pair the keyboard themselves)
            handler.postDelayed(() -> connect(), retryMs);
            retryMs = Math.min(retryMs * 2, MAX_RETRY_MS);
            return;
        }
        if (gatt != null) {
            gatt.close();
            gatt = null;
        }
        interval = 0;
        Log.i(TAG, "Opening latency GATT client for " + mac);
        gatt = device.connectGatt(this, false, callback, BluetoothDevice.TRANSPORT_LE);
    }

    private void checkInterval() {
        if (gatt == null || stopped) return;
        if (interval != 0 && interval <= HIGH_MAX_INTERVAL) {
            Log.i(TAG, "BLE interval already " + interval * 1.25 + " ms; not requesting high priority");
            return;
        }
        if (requests >= MAX_REQUESTS_PER_CONNECTION) {
            Log.w(TAG, "BLE interval still " + interval * 1.25 + " ms after " + requests + " requests; giving up");
            return;
        }
        requests++;
        boolean accepted = gatt.requestConnectionPriority(BluetoothGatt.CONNECTION_PRIORITY_HIGH);
        Log.i(TAG, "BLE interval " + (interval == 0 ? "unknown" : interval * 1.25 + " ms")
                + ": high-priority request accepted=" + accepted);
    }

    @Override public void onDestroy() {
        stopped = true;
        handler.removeCallbacksAndMessages(null);
        if (gatt != null) gatt.close();
        gatt = null;
        super.onDestroy();
    }

    @Override public IBinder onBind(Intent intent) { return null; }
}
