#!/usr/bin/env bash
# Build the AgenticAI Android APK (arm64-v8a).
#
# Reuses the prebuilt Harbour-for-Android static libs from C:\HarbourAndroid and
# the ccharbour agent core. No hbcurl/openssl: the LLM HTTP transport is Java
# (MainActivity.httpPost), injected into ccharbour via hOpts["transport"].
set -eu

APP=/c/fwteam/samples/AgenticAI/Android
CC_SRC=/c/ccharbour/src

HB_SRC=/c/HarbourAndroid/harbour-core
HB_LIB=$HB_SRC/lib/android/clang-android-arm64-v8a
HB_INC=$HB_SRC/include
HOST_HB=/c/harbour/bin/win/bcc/harbour.exe

NDK=${NDK_ROOT:-/c/Android/android-ndk-r26d}
NDK_BIN=$NDK/toolchains/llvm/prebuilt/windows-x86_64/bin
CLANG=$NDK_BIN/clang.exe
TARGET=aarch64-linux-android24

SDK=/c/Android/Sdk
JDK=${JDK_ROOT:-/c/Android/jdk17/jdk-17.0.13+11}
BT=$SDK/build-tools/34.0.0
ANDROID_JAR=$SDK/platforms/android-34/android.jar

export PATH="$JDK/bin:$BT:$PATH"
export JAVA_HOME="$JDK"

OUT=$APP/build
rm -rf "$OUT"; mkdir -p "$OUT"/{obj,gen,jni-libs/arm64-v8a,apk,classes,res-compiled,payload/lib/arm64-v8a}

# ---- 1. PRG -> C (native host harbour.exe) ----
echo ">>> [1/8] harbour.exe (app + ccharbour core)"
PRGS="$APP/src/prg/agents.prg /c/fwteam/samples/AgenticAI/ccguistub.prg \
  $CC_SRC/ccconfig.prg $CC_SRC/ccsse.prg $CC_SRC/cchttp.prg $CC_SRC/ccapi.prg \
  $CC_SRC/ccagent.prg $CC_SRC/cctools.prg $CC_SRC/cctools_file.prg \
  $CC_SRC/cctools_search.prg $CC_SRC/cctools_shell.prg $CC_SRC/cctools_web.prg \
  $CC_SRC/cctools_memory.prg $CC_SRC/ccdiff.prg"
OBJS=""
for p in $PRGS; do
  b=$(basename "$p" .prg)
  "$HOST_HB" "$p" -n -q -I"$(cygpath -w $HB_INC)" -I"$(cygpath -w $CC_SRC)" -o"$(cygpath -w $OUT/obj/)"
  OBJS="$OBJS $OUT/obj/$b.o"
done

# ---- 2. cross-compile C ----
echo ">>> [2/8] cross-compile C"
CFLAGS="--target=$TARGET -fPIC -O2 -I$HB_INC"
for p in $PRGS; do
  b=$(basename "$p" .prg)
  "$CLANG" $CFLAGS -c "$OUT/obj/$b.c" -o "$OUT/obj/$b.o"
done
"$CLANG" $CFLAGS -c "$APP/src/cpp/android_webview.c" -o "$OUT/obj/android_webview.o"

# ---- 3. link libagenticai.so ----
echo ">>> [3/8] link libagenticai.so"
"$CLANG" --target=$TARGET -shared -fPIC \
  -Wl,-soname,libagenticai.so \
  -o "$OUT/jni-libs/arm64-v8a/libagenticai.so" \
  "$OUT/obj/android_webview.o" \
  -Wl,--whole-archive $OBJS -Wl,--no-whole-archive \
  -L"$HB_LIB" -Wl,--start-group \
  -lhbvmmt -lhbrtl -lhblang -lhbcpage -lhbrdd -lhbmacro -lhbpp -lhbcommon \
  -lhbpcre -lhbzlib -lhbnulrdd -lhbdebug -lhbcplr \
  -lrddntx -lrddcdx -lrddfpt -lrddnsx \
  -lgtstd -lgttrm -lgtcgi -lgtpca -lhbsix -lhbhsx \
  -Wl,--end-group -ldl -lm -llog
ls -lh "$OUT/jni-libs/arm64-v8a/libagenticai.so"

# ---- 4-5. resources ----
echo ">>> [4/8] aapt2 compile"; aapt2 compile --dir "$APP/src/res" -o "$OUT/res-compiled"
echo ">>> [5/8] aapt2 link"
aapt2 link -I "$ANDROID_JAR" --manifest "$APP/AndroidManifest.xml" \
  --java "$OUT/gen" -o "$OUT/apk/base.apk" $(ls "$OUT/res-compiled"/*.flat)

# ---- 6-7. java + dex ----
echo ">>> [6/8] javac"
javac -d "$OUT/classes" -source 1.8 -target 1.8 \
  -bootclasspath "$ANDROID_JAR" -classpath "$ANDROID_JAR" \
  "$APP/src/java/com/harbour/agenticai/MainActivity.java" \
  "$OUT/gen/com/harbour/agenticai/R.java"
echo ">>> [7/8] d8"
cd "$OUT/classes"; d8.bat --lib "$ANDROID_JAR" --min-api 24 --output "$OUT/apk/" $(find . -name "*.class")

# ---- 8. package + sign ----
echo ">>> [8/8] package & sign"
cp "$OUT/apk/base.apk" "$OUT/apk/unsigned.apk"
cp "$OUT/apk/classes.dex" "$OUT/payload/classes.dex"
cp "$OUT/jni-libs/arm64-v8a/libagenticai.so" "$OUT/payload/lib/arm64-v8a/libagenticai.so"
cd "$OUT/payload"; "$JDK/bin/jar.exe" uf "$OUT/apk/unsigned.apk" classes.dex lib/arm64-v8a/libagenticai.so
cd "$OUT"; zipalign.exe -f -p 4 "$OUT/apk/unsigned.apk" "$OUT/apk/aligned.apk"

KS="$APP/debug.keystore"
[ -f "$KS" ] || keytool -genkeypair -v -keystore "$KS" -alias agentic -keyalg RSA \
  -keysize 2048 -validity 10000 -storepass android -keypass android \
  -dname "CN=AgenticAI,O=FiveTech,C=ES"
apksigner.bat sign --ks "$KS" --ks-pass pass:android --key-pass pass:android \
  --out "$OUT/agents.apk" "$OUT/apk/aligned.apk"

echo "=============================================="
echo " APK ready: $OUT/agents.apk"
echo " Install:  adb install -r $OUT/agents.apk"
echo "=============================================="
