# HarbourAndroid (build dependency)

This folder documents how the prebuilt **Harbour for Android** static libraries
that `../build-apk.sh` links against are produced. It is NOT the Harbour source
itself.

## Steps

1. Clone the official Harbour into `C:\HarbourAndroid\harbour-core`:

   `git clone https://github.com/harbour/core C:\HarbourAndroid\harbour-core`

   (Verified against commit `0f28a7b`, 2026-02-28, unmodified.)

2. Install Android NDK r26+ and a native Windows Harbour bootstrap (`C:\harbour`).

3. From MSYS2 bash run `build-android.sh` (see header for ABI/NDK overrides). It
   cross-compiles core + RTL + VM with the NDK clang and emits the static libs
   under `harbour-core/lib/android/clang-android-<ABI>/`.

4. Crucially, the app links the **multi-thread** VM (`libhbvmmt.a`) ? the single
   thread `libhbvm.a` ships an `hb_threadStart` no-op stub, so multiple agents
   would never spawn.

No changes are made to the Harbour sources; only generated libraries are consumed.
