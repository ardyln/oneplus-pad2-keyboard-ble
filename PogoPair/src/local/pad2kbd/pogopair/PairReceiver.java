package local.pad2kbd.pogopair;

import android.bluetooth.BluetoothAdapter;
import android.bluetooth.BluetoothDevice;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.util.Log;
import java.lang.reflect.Method;

/**
 * Bonds with the keyboard, or starts the latency helper when already bonded
 * (with "pair" = false: only starts the latency helper).
 * Not exported: only root/system (the module scripts) can send it the PAIR broadcast.
 * The MAC comes from the "mac" extra; nothing is hardcoded.
 */
public final class PairReceiver extends BroadcastReceiver {
    static final String TAG = "pad2kbd";

    @Override public void onReceive(Context context, Intent intent) {
        String mac = intent.getStringExtra("mac");
        if (mac == null || !BluetoothAdapter.checkBluetoothAddress(mac)) {
            Log.w(TAG, "PAIR without a valid mac extra: " + mac);
            return;
        }
        try {
            BluetoothAdapter adapter = BluetoothAdapter.getDefaultAdapter();
            if (adapter == null || !adapter.isEnabled()) {
                Log.w(TAG, "Bluetooth is unavailable or disabled; skipping pair request");
                return;
            }
            BluetoothDevice device = adapter.getRemoteDevice(mac);
            int state = device.getBondState();
            // pair=false: the ROM pairs the keyboard itself; only start the latency helper,
            // which waits for the bond if the ROM is still pairing.
            if (!intent.getBooleanExtra("pair", true)) {
                Log.i(TAG, "Latency only (ROM handles pairing), bond state " + state + ": " + mac);
                context.startService(new Intent(context, LatencyService.class).putExtra("mac", mac));
                return;
            }
            if (state == BluetoothDevice.BOND_BONDED) {
                Log.i(TAG, "Keyboard already bonded: " + mac);
                context.startService(new Intent(context, LatencyService.class).putExtra("mac", mac));
                return;
            }
            if (state == BluetoothDevice.BOND_BONDING) {
                Log.i(TAG, "Keyboard bonding already in progress: " + mac);
                return;
            }
            adapter.cancelDiscovery();
            Log.i(TAG, "Keyboard LE bond request started=" + createLeBond(device) + ": " + mac);
        } catch (Throwable t) {
            Log.e(TAG, "Keyboard pairing failed", t);
        }
    }

    static boolean createLeBond(BluetoothDevice device) {
        try {
            // Force LE: after a Bluetooth reset Android no longer knows the address is LE-only.
            Method createBond = BluetoothDevice.class.getMethod("createBond", int.class);
            return (Boolean) createBond.invoke(device, BluetoothDevice.TRANSPORT_LE);
        } catch (Throwable hiddenApiFailure) {
            Log.w(TAG, "createBond(LE) unavailable, using automatic transport", hiddenApiFailure);
            return device.createBond();
        }
    }
}
