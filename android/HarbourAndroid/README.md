# Harbour for Android — build from Windows

First attempt at cross-compiling `libharbour.a` for Android using the official
`harbour/core` repo and the Android NDK's Clang toolchain.

## Layout

    C:\HarbourAndroid\
      harbour-core\      # clone of https://github.com/harbour/core
      build-android.sh   # driver script (run from MSYS2 bash)

## Prerequisites

1. **Android NDK r26+** — download from https://developer.android.com/ndk/downloads
   Default expected path: `C:\Android\ndk\26.2.11394342\`
   Override with `NDK_ROOT=...`
2. **Native Windows Harbour** already built (bootstrap hbmk2/hbpp).
   Default: `C:\HarbourBuilder\harbour\`
   Override with `HARBOUR_HOST=...`
3. **MSYS2** with `make` and `git` installed.

## Usage

From MSYS2 bash:

    cd /c/HarbourAndroid
    ./build-android.sh                  # arm64-v8a (default)
    ABI=armeabi-v7a ./build-android.sh
    ABI=x86_64     ./build-android.sh
    CLEAN=1        ./build-android.sh

## What the script does

- Sets `HB_PLATFORM=android`, `HB_COMPILER=clang`
- Points `HB_CC`/`HB_CXX` at the NDK's triple-prefixed Clang
  (e.g. `aarch64-linux-android24-clang`)
- Uses `llvm-ar` / `llvm-ranlib` / `llvm-strip` from the NDK
- Builds **core + RTL + VM only** (`HB_BUILD_CONTRIBS=no`) as a first milestone
- Produces static libs under `harbour-core/lib/android/clang-android-<ABI>/`

## Expected issues (first run)

1. `config/linux/clang.mk` may hardcode `clang` / `clang++` without honoring
   `HB_CC` — patch if needed.
2. Any contrib library enabled by default pulling in POSIX features bionic
   doesn't have (`crypt`, `nsl`, etc.).
3. `hbmk2` must run from the **host** build, not the cross one. The script
   puts the Windows `hbmk2.exe` first in PATH.

## Next steps after a green build

1. Add `arm64-v8a` + `armeabi-v7a` + `x86_64` (loop script).
2. Build a shared `libharbour.so` (PIC, `HB_BUILD_DYN=yes`).
3. Minimal JNI bridge that calls `hb_vmInit()` + runs a bundled PRG.
4. Package as `.apk` via Gradle or manual aapt2/d8/apksigner pipeline.
5. Wire into HarbourBuilder IDE as the Android tab.
