# Prebuilt Harbour-for-Android static libraries (arm64-v8a)

These `.a` files are **built from the official Harbour: https://github.com/harbour/core**
(commit `0f28a7b`, 2026-02-28, sources unmodified), cross-compiled with Android
NDK r26d clang for `arm64-v8a` via `../build-android.sh`.

They are the link inputs for `../../build-apk.sh`. The app links the
multi-thread VM `libhbvmmt.a` (not the single-thread `libhbvm.a`).

License: Harbour's (see https://github.com/harbour/core `LICENSE.txt` /
`COPYING.txt`). These are unmodified build artifacts of that project.
