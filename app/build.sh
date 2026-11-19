#!/bin/sh
# Build the G25 Profiles APK without Gradle: JDK + ../tools (build-tools 35.0.1, android-35 android.jar).
set -e
cd "$(dirname "$0")"
BT=../tools/android-15
JAR=../tools/platform/android.jar
PASS=g25profiles

rm -rf build && mkdir -p build/classes
javac --release 11 -cp "$JAR" -d build/classes src/com/holman/g25/ProfileTile.java
"$BT/d8" --release --min-api 29 --lib "$JAR" --output build build/classes/com/holman/g25/*.class
"$BT/aapt2" link -o build/unsigned.apk -I "$JAR" --manifest AndroidManifest.xml
(cd build && zip -q unsigned.apk classes.dex)
"$BT/zipalign" -f -p 4 build/unsigned.apk build/aligned.apk
# Keep g25.keystore: updates must be signed with the same key.
[ -f g25.keystore ] || keytool -genkeypair -keystore g25.keystore -storepass $PASS -keypass $PASS \
    -alias g25 -keyalg RSA -keysize 2048 -validity 36500 -dname "CN=holman"
"$BT/apksigner" sign --ks g25.keystore --ks-pass pass:$PASS --key-pass pass:$PASS \
    --out g25profiles.apk build/aligned.apk
"$BT/apksigner" verify g25profiles.apk
echo "OK: $(pwd)/g25profiles.apk"
