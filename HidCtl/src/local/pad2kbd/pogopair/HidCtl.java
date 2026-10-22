package local.pad2kbd.pogopair;

import android.bluetooth.BluetoothAdapter;
import android.bluetooth.BluetoothDevice;
import android.bluetooth.BluetoothProfile;
import android.content.Context;
import android.os.Handler;
import android.os.IBinder;
import android.os.Looper;
import android.util.Log;
import java.lang.reflect.Constructor;
import java.lang.reflect.Method;

/**
 * Root helper run via app_process:
 *   suspend MAC  policy FORBIDDEN + disconnect   (keyboard on the pogo pins)
 *   resume  MAC  policy ALLOWED + connect        (keyboard detached)
 *   allow   MAC  policy ALLOWED only             (uninstall)
 *   status  MAC  print policy, connection and bond state
 *   tune    MAC  apply the keyboard's preferred BLE connection parameters (see LinkTuner)
 */
public final class HidCtl {
    private static final String TAG = "pad2kbd";
    private static final int HID_HOST = 4;

    public static void main(String[] args) throws Exception {
        final String cmd = args.length == 2 ? args[0] : "";
        if (!cmd.matches("suspend|resume|allow|status|tune") || !BluetoothAdapter.checkBluetoothAddress(args[1])) {
            System.err.println("usage: HidCtl suspend|resume|allow|status|tune MAC");
            System.exit(2);
        }
        Looper.prepareMainLooper();
        Class<?> atClass = Class.forName("android.app.ActivityThread");
        Object at = atClass.getMethod("systemMain").invoke(null);
        Context context = (Context) atClass.getMethod("getSystemContext").invoke(at);

        // system_server normally performs this framework bootstrap. A standalone
        // app_process has to do it before BluetoothHidHost can query adapter state.
        Class<?> serviceManagerClass = Class.forName("android.os.BluetoothServiceManager");
        Object serviceManager = serviceManagerClass.getConstructor().newInstance();
        Class<?> initializerClass = Class.forName("android.bluetooth.BluetoothFrameworkInitializer");
        try {
            initializerClass.getMethod("setBluetoothServiceManager", serviceManagerClass)
                    .invoke(null, serviceManager);
        } catch (java.lang.reflect.InvocationTargetException alreadySet) {
            // Thrown if the framework already initialized it; harmless.
        }

        // app_process does not initialize BluetoothAdapter's process singleton.
        // Build the adapter from the system bluetooth_manager binder instead.
        Class<?> smClass = Class.forName("android.os.ServiceManager");
        IBinder binder = (IBinder) smClass.getMethod("getService", String.class)
                .invoke(null, "bluetooth_manager");
        if (binder == null) throw new IllegalStateException("bluetooth_manager unavailable");
        Class<?> managerClass = Class.forName("android.bluetooth.IBluetoothManager");
        Class<?> stubClass = Class.forName("android.bluetooth.IBluetoothManager$Stub");
        Object manager = stubClass.getMethod("asInterface", IBinder.class).invoke(null, binder);
        Constructor<BluetoothAdapter> constructor = BluetoothAdapter.class
                .getDeclaredConstructor(managerClass, Context.class);
        constructor.setAccessible(true);
        final BluetoothAdapter adapter = constructor.newInstance(manager, context);
        final BluetoothDevice device = adapter.getRemoteDevice(args[1]);
        if ("tune".equals(cmd)) {
            new LinkTuner(context, device).run();   // exits the process itself
            return;
        }
        new Handler(Looper.getMainLooper()).postDelayed(() -> {
            System.out.println(cmd + ": timeout waiting for HID_HOST proxy");
            System.exit(3);
        }, 7000);
        boolean requested = adapter.getProfileProxy(context, new BluetoothProfile.ServiceListener() {
            @Override public void onServiceConnected(int profile, BluetoothProfile proxy) {
                int code = 0;
                try {
                    Class<?> c = proxy.getClass();
                    String result;
                    if ("status".equals(cmd)) {
                        Object policy = c.getMethod("getConnectionPolicy", BluetoothDevice.class).invoke(proxy, device);
                        Object state = c.getMethod("getConnectionState", BluetoothDevice.class).invoke(proxy, device);
                        result = "policy=" + policy + " hid_state=" + state + " bond=" + device.getBondState()
                                + " (policy 100=allowed 0=forbidden; state 2=connected; bond 12=bonded)";
                    } else {
                        boolean suspend = "suspend".equals(cmd);
                        boolean policy = (Boolean) c.getMethod("setConnectionPolicy", BluetoothDevice.class, int.class)
                                .invoke(proxy, device, suspend ? 0 : 100);
                        String transition = "none";
                        if (!"allow".equals(cmd)) {
                            transition = String.valueOf(c.getMethod(suspend ? "disconnect" : "connect", BluetoothDevice.class)
                                    .invoke(proxy, device));
                        }
                        result = "policy=" + policy + " transition=" + transition;
                        if (!policy) code = 4;
                    }
                    Log.i(TAG, "HidCtl " + cmd + ": " + result);
                    System.out.println(cmd + ": " + result);
                    adapter.closeProfileProxy(profile, proxy);
                } catch (Throwable t) {
                    Log.e(TAG, "HidCtl " + cmd + " failed", t);
                    System.out.println(cmd + ": failed: " + t);
                    code = 5;
                }
                System.exit(code);
            }
            @Override public void onServiceDisconnected(int profile) {}
        }, HID_HOST);
        if (!requested) {
            System.out.println(cmd + ": getProfileProxy refused");
            System.exit(6);
        }
        Looper.loop();
    }
}
