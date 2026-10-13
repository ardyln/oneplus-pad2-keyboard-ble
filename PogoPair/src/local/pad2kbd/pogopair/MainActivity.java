package local.pad2kbd.pogopair;

import android.app.Activity;
import android.bluetooth.BluetoothAdapter;
import android.bluetooth.BluetoothDevice;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.os.Bundle;
import android.util.Log;
import android.widget.TextView;

/**
 * Manual pairing screen, for debugging only (no launcher icon, not exported):
 *   su -c am start -n local.pad2kbd.pogopair/.MainActivity --es mac XX:XX:XX:XX:XX:XX
 */
public final class MainActivity extends Activity {
    private static final String TAG = PairReceiver.TAG;
    private TextView status;

    private final BroadcastReceiver receiver = new BroadcastReceiver() {
        @Override public void onReceive(Context context, Intent intent) {
            BluetoothDevice device = intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE);
            if (device == null) return;
            int state = intent.getIntExtra(BluetoothDevice.EXTRA_BOND_STATE, BluetoothDevice.ERROR);
            int previous = intent.getIntExtra(BluetoothDevice.EXTRA_PREVIOUS_BOND_STATE, BluetoothDevice.ERROR);
            String message = "Bond state " + previous + " -> " + state + " for " + device.getAddress();
            Log.i(TAG, message);
            status.setText(message);
        }
    };

    @Override protected void onCreate(Bundle state) {
        super.onCreate(state);
        status = new TextView(this);
        status.setTextSize(20);
        status.setPadding(48, 48, 48, 48);
        setContentView(status);
        registerReceiver(receiver, new IntentFilter(BluetoothDevice.ACTION_BOND_STATE_CHANGED));

        String mac = getIntent().getStringExtra("mac");
        if (mac == null || !BluetoothAdapter.checkBluetoothAddress(mac)) {
            status.setText("No valid MAC given. Start with: --es mac XX:XX:XX:XX:XX:XX");
            return;
        }
        try {
            BluetoothAdapter adapter = BluetoothAdapter.getDefaultAdapter();
            if (adapter == null || !adapter.isEnabled()) throw new IllegalStateException("Bluetooth is off");
            adapter.cancelDiscovery();
            BluetoothDevice device = adapter.getRemoteDevice(mac);
            boolean started = PairReceiver.createLeBond(device);
            String message = "createBond(" + mac + ")=" + started + ", state=" + device.getBondState();
            Log.i(TAG, message);
            status.setText(message);
        } catch (Throwable t) {
            Log.e(TAG, "Pairing failed", t);
            status.setText(Log.getStackTraceString(t));
        }
    }

    @Override protected void onDestroy() {
        try { unregisterReceiver(receiver); } catch (Throwable ignored) {}
        super.onDestroy();
    }
}
