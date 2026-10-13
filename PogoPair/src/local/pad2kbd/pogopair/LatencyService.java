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
 * Keeps a GATT client open and requests the high-priority (~11-15 ms) BLE interval for the touchpad.
 * The MAC arrives as an intent extra and is remembered so a sticky restart (null intent) still works.
 */
public final class LatencyService extends Service {
    private static final String TAG = PairReceiver.TAG;
    private static final long MAX_RETRY_MS = 30000;
    private final Handler handler = new Handler(Looper.getMainLooper());
    private BluetoothGatt gatt;
    private String mac;
    private boolean stopped;
    private long retryMs = 1500;

    private final BluetoothGattCallback callback = new BluetoothGattCallback() {
        @Override public void onConnectionStateChange(BluetoothGatt current, int status, int state) {
            Log.i(TAG, "Latency GATT state=" + state + " status=" + status);
            if (state == BluetoothProfile.STATE_CONNECTED) {
                retryMs = 1500;
                requestHighPriority(current);
                handler.postDelayed(() -> requestHighPriority(current), 2000);
            } else if (state == BluetoothProfile.STATE_DISCONNECTED && !stopped) {
                handler.postDelayed(() -> connect(), retryMs);
                retryMs = Math.min(retryMs * 2, MAX_RETRY_MS);
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
        if (device.getBondState() != BluetoothDevice.BOND_BONDED) return;
        if (gatt != null) {
            gatt.close();
            gatt = null;
        }
        Log.i(TAG, "Opening latency GATT client for " + mac);
        gatt = device.connectGatt(this, false, callback, BluetoothDevice.TRANSPORT_LE);
    }

    private void requestHighPriority(BluetoothGatt current) {
        if (current != gatt) return;
        boolean accepted = current.requestConnectionPriority(BluetoothGatt.CONNECTION_PRIORITY_HIGH);
        Log.i(TAG, "High-priority BLE interval accepted=" + accepted);
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
