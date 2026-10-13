package local.penprobe;

import android.app.Activity;
import android.bluetooth.BluetoothAdapter;
import android.bluetooth.BluetoothDevice;
import android.bluetooth.BluetoothGatt;
import android.bluetooth.BluetoothGattCallback;
import android.bluetooth.BluetoothGattCharacteristic;
import android.bluetooth.BluetoothGattDescriptor;
import android.bluetooth.BluetoothGattService;
import android.bluetooth.BluetoothProfile;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.os.SystemClock;
import android.util.Log;
import android.widget.ScrollView;
import android.widget.TextView;
import java.text.SimpleDateFormat;
import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.Date;
import java.util.List;
import java.util.Locale;
import java.util.UUID;

/**
 * Read-mostly GATT probe for the OnePlus Stylo 2: subscribes to every notify/indicate characteristic
 * of the vendor services, reads their readable characteristics, and logs every notification.
 * Its only writes are CCC descriptors, which it disables again on exit.
 */
public final class ProbeActivity extends Activity {
    private static final String TAG = "PenProbe";
    private static final UUID CCC = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb");
    private static final String SIG_BASE = "-0000-1000-8000-00805f9b34fb";

    private final Handler handler = new Handler(Looper.getMainLooper());
    private final ArrayDeque<Runnable> ops = new ArrayDeque<>();
    private final List<BluetoothGattDescriptor> enabled = new ArrayList<>();
    private boolean busy;
    private BluetoothGatt gatt;
    private boolean disableMode;
    private TextView view;
    private ScrollView scroll;
    private final StringBuilder text = new StringBuilder();
    private final SimpleDateFormat fmt = new SimpleDateFormat("HH:mm:ss.SSS", Locale.US);

    private static boolean isVendor(UUID u) {
        return !u.toString().endsWith(SIG_BASE);
    }

    private static String hex(byte[] v) {
        if (v == null) return "null";
        StringBuilder sb = new StringBuilder();
        for (byte b : v) sb.append(String.format("%02x", b));
        return sb.toString();
    }

    private void out(String s) {
        String line = fmt.format(new Date()) + " " + s;
        Log.i(TAG, line);
        handler.post(() -> {
            text.append(line).append('\n');
            view.setText(text);
            scroll.post(() -> scroll.fullScroll(ScrollView.FOCUS_DOWN));
        });
    }

    private void queue(Runnable r) {
        ops.addLast(r);
        next();
    }

    private void next() {
        if (busy || ops.isEmpty()) return;
        busy = true;
        handler.post(ops.removeFirst());
    }

    private void done() {
        busy = false;
        next();
    }

    private final BluetoothGattCallback cb = new BluetoothGattCallback() {
        @Override public void onConnectionStateChange(BluetoothGatt g, int status, int state) {
            out("connection state=" + state + " status=" + status);
            if (state == BluetoothProfile.STATE_CONNECTED) g.discoverServices();
        }

        @Override public void onServicesDiscovered(BluetoothGatt g, int status) {
            out("services discovered status=" + status);
            for (BluetoothGattService s : g.getServices()) {
                if (!isVendor(s.getUuid())) continue;
                out("SERVICE " + s.getUuid());
                for (BluetoothGattCharacteristic c : s.getCharacteristics()) {
                    int p = c.getProperties();
                    out("  CHAR " + c.getUuid() + " props=0x" + Integer.toHexString(p));
                    if (!disableMode && (p & BluetoothGattCharacteristic.PROPERTY_READ) != 0) {
                        queue(() -> { if (!g.readCharacteristic(c)) { out("read failed " + c.getUuid()); done(); } });
                    }
                    if ((p & (BluetoothGattCharacteristic.PROPERTY_NOTIFY | BluetoothGattCharacteristic.PROPERTY_INDICATE)) != 0) {
                        BluetoothGattDescriptor d = c.getDescriptor(CCC);
                        if (d == null) continue;
                        boolean indicate = (p & BluetoothGattCharacteristic.PROPERTY_NOTIFY) == 0;
                        queue(() -> {
                            g.setCharacteristicNotification(c, !disableMode);
                            d.setValue(disableMode ? BluetoothGattDescriptor.DISABLE_NOTIFICATION_VALUE
                                     : indicate ? BluetoothGattDescriptor.ENABLE_INDICATION_VALUE
                                                : BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE);
                            if (!g.writeDescriptor(d)) { out("CCC write failed " + c.getUuid()); done(); }
                        });
                    }
                }
            }
            if (disableMode) {
                queue(() -> { out("=== all vendor notifications disabled; closing ==="); done(); finish(); });
            } else {
                queue(() -> { out("=== READY: use the pen button now ==="); done(); });
            }
        }

        @Override public void onCharacteristicRead(BluetoothGatt g, BluetoothGattCharacteristic c, int status) {
            out("READ " + c.getUuid() + " status=" + status + " value=" + hex(c.getValue()));
            done();
        }

        @Override public void onDescriptorWrite(BluetoothGatt g, BluetoothGattDescriptor d, int status) {
            out("subscribe " + d.getCharacteristic().getUuid() + " value=" + hex(d.getValue()) + " status=" + status);
            if (status == BluetoothGatt.GATT_SUCCESS && d.getValue() != null && d.getValue()[0] != 0) enabled.add(d);
            done();
        }

        @Override public void onCharacteristicChanged(BluetoothGatt g, BluetoothGattCharacteristic c) {
            out("NOTIFY " + c.getUuid() + " t=" + SystemClock.uptimeMillis() + " " + hex(c.getValue()));
        }
    };

    @Override protected void onCreate(Bundle state) {
        super.onCreate(state);
        view = new TextView(this);
        view.setTextSize(12);
        view.setTypeface(android.graphics.Typeface.MONOSPACE);
        scroll = new ScrollView(this);
        scroll.addView(view);
        setContentView(scroll);
        String mac = getIntent().getStringExtra("mac");
        disableMode = getIntent().getBooleanExtra("disable", false);
        if (mac == null || !BluetoothAdapter.checkBluetoothAddress(mac)) {
            out("start with --es mac XX:XX:XX:XX:XX:XX");
            return;
        }
        BluetoothDevice dev = BluetoothAdapter.getDefaultAdapter().getRemoteDevice(mac);
        out("connecting to " + mac + " bond=" + dev.getBondState());
        gatt = dev.connectGatt(this, false, cb, BluetoothDevice.TRANSPORT_LE);
    }

    @Override protected void onDestroy() {
        // Restore the pen's notification flags before leaving.
        BluetoothGatt g = gatt;
        if (g != null) {
            for (BluetoothGattDescriptor d : enabled) {
                g.setCharacteristicNotification(d.getCharacteristic(), false);
                d.setValue(BluetoothGattDescriptor.DISABLE_NOTIFICATION_VALUE);
                g.writeDescriptor(d);
                SystemClock.sleep(150);
            }
            Log.i(TAG, "disabled " + enabled.size() + " subscriptions; closing");
            g.close();
        }
        super.onDestroy();
    }
}
