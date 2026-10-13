#!/usr/bin/env bash
# Builds Pad2KbdPair.apk + hidctl.jar from pad2_src/ and packs the flashable module zip.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SRC=$ROOT
MOD=$ROOT/module
OUT=$ROOT/build
SDK=/usr/lib/android-sdk
JAVA_HOME=${JAVA_HOME:-/usr/lib/jvm/java-21-openjdk-amd64}
ANDROID_JAR=$(ls -d $SDK/platforms/android-3*/android.jar | sort -V | tail -n1)
BT=$(ls -d $SDK/build-tools/3* | sort -V | tail -n1)
D8=$BT/d8
# Personal signing key: not in the repo (.gitignore). Created on first build if missing.
# Keep a copy: app updates must be signed with the same key to install over the old app.
KEYSTORE=${KEYSTORE:-$ROOT/tools/pad2kbd-release.jks}
KS_PASS=${KS_PASS:?set KS_PASS to the keystore password}
VERSION=$(grep '^version=' $MOD/module.prop | cut -d= -f2)

echo "javac: $($JAVA_HOME/bin/javac -version 2>&1)  android.jar: $ANDROID_JAR  d8: $D8"
rm -rf "$OUT"; mkdir -p "$OUT"/{app/classes,app/dex,hid/classes,hid/dex}

# --- PogoPair app ---
$JAVA_HOME/bin/javac --release 11 -Xlint:-options -classpath "$ANDROID_JAR" \
    -d "$OUT/app/classes" $(find "$SRC/PogoPair/src" -name '*.java')
$D8 --release --min-api 23 --lib "$ANDROID_JAR" --output "$OUT/app/dex" \
    $(find "$OUT/app/classes" -name '*.class')
aapt2 link -o "$OUT/app/unsigned.apk" -I "$ANDROID_JAR" \
    --manifest "$SRC/PogoPair/AndroidManifest.xml" --min-sdk-version 23 --target-sdk-version 28
(cd "$OUT/app/dex" && zip -q -j "$OUT/app/unsigned.apk" classes.dex)
zipalign -f -p 4 "$OUT/app/unsigned.apk" "$OUT/app/aligned.apk"
if [ ! -f "$KEYSTORE" ]; then
    keytool -genkeypair -keystore "$KEYSTORE" -storepass "$KS_PASS" -keypass "$KS_PASS" -alias pad2kbd \
        -keyalg RSA -keysize 3072 -validity 10000 -dname "CN=pad2kbd personal" >/dev/null 2>&1
fi
apksigner sign --ks "$KEYSTORE" --ks-pass env:KS_PASS --key-pass env:KS_PASS \
    --out "$OUT/Pad2KbdPair.apk" "$OUT/app/aligned.apk"
apksigner verify "$OUT/Pad2KbdPair.apk"

# --- hidctl.jar (dex inside a jar, run by app_process) ---
$JAVA_HOME/bin/javac --release 11 -Xlint:-options -classpath "$ANDROID_JAR" \
    -d "$OUT/hid/classes" $(find "$SRC/HidCtl/src" -name '*.java')
$D8 --release --min-api 23 --lib "$ANDROID_JAR" --output "$OUT/hid/dex" \
    $(find "$OUT/hid/classes" -name '*.class')
(cd "$OUT/hid/dex" && zip -q "$OUT/hidctl.jar" classes.dex)

# --- module tree (staged copy; the repo keeps no build output) ---
STAGE=$OUT/stage; rm -rf "$STAGE"; cp -r "$MOD" "$STAGE"
mkdir -p "$STAGE/system/priv-app/Pad2KbdPair"
cp "$OUT/Pad2KbdPair.apk" "$STAGE/system/priv-app/Pad2KbdPair/Pad2KbdPair.apk"
cp "$OUT/hidctl.jar" "$STAGE/hidctl.jar"

# --- zip: module.prop at root, LF endings, scripts 0755 inside the archive ---
ZIP=$OUT/OnePlus_Pad2_Keyboard_BLE-v$VERSION.zip
find "$STAGE" -name '*.sh' -exec sed -i 's/\r$//' {} + -exec chmod 0755 {} +
find "$STAGE" -type f ! -name '*.sh' -exec chmod 0644 {} +
find "$STAGE" -type d -exec chmod 0755 {} +
chmod 0755 "$STAGE/META-INF/com/google/android/update-binary"
rm -f "$ZIP"; (cd "$STAGE" && zip -q -r -X "$ZIP" .)
echo "built $ZIP"
