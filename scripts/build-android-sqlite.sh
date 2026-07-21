#!/bin/sh
set -eu

ABI="${1:-arm64-v8a}"
API_LEVEL="${ANDROID_API_LEVEL:-28}"
SQLITE_VERSION="3470200"
SQLITE_SHA256="aa73d8748095808471deaa8e6f34aa700e37f2f787f4425744f53fdd15a89c40"
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
OUTPUT_DIR="$REPO_ROOT/AndroidApp/.native/sqlite/$ABI"
ARCHIVE="$OUTPUT_DIR/sqlite-amalgamation-$SQLITE_VERSION.zip"
SOURCE_DIR="$OUTPUT_DIR/sqlite-amalgamation-$SQLITE_VERSION"
SDK_ROOT="${SWIFT_ANDROID_SDK_ROOT:-$HOME/Library/org.swift.swiftpm/swift-sdks/swift-6.3.3-RELEASE_android.artifactbundle/swift-android}"
NDK_BIN="$SDK_ROOT/android-ndk-r27d/toolchains/llvm/prebuilt/darwin-x86_64/bin"

case "$ABI" in
    arm64-v8a) COMPILER="aarch64-linux-android${API_LEVEL}-clang" ;;
    x86_64) COMPILER="x86_64-linux-android${API_LEVEL}-clang" ;;
    armeabi-v7a) COMPILER="armv7a-linux-androideabi${API_LEVEL}-clang" ;;
    *) echo "Unsupported Android ABI: $ABI" >&2; exit 2 ;;
esac

mkdir -p "$OUTPUT_DIR"
if [ ! -f "$ARCHIVE" ]; then
    curl -fSL -o "$ARCHIVE" "https://www.sqlite.org/2024/sqlite-amalgamation-$SQLITE_VERSION.zip"
fi

ACTUAL_SHA256="$(shasum -a 256 "$ARCHIVE" | awk '{print $1}')"
if [ "$ACTUAL_SHA256" != "$SQLITE_SHA256" ]; then
    echo "SQLite archive checksum mismatch: $ACTUAL_SHA256" >&2
    exit 3
fi

if [ ! -f "$SOURCE_DIR/sqlite3.c" ]; then
    unzip -qo "$ARCHIVE" -d "$OUTPUT_DIR"
fi

"$NDK_BIN/$COMPILER" \
    -c "$SOURCE_DIR/sqlite3.c" \
    -o "$OUTPUT_DIR/sqlite3.o" \
    -O2 -fPIC \
    -DSQLITE_THREADSAFE=1 \
    -DSQLITE_ENABLE_FTS5 \
    -DSQLITE_ENABLE_RTREE \
    -DSQLITE_ENABLE_COLUMN_METADATA \
    -DSQLITE_ENABLE_SNAPSHOT
"$NDK_BIN/llvm-ar" rcs "$OUTPUT_DIR/libsqlite3.a" "$OUTPUT_DIR/sqlite3.o"

echo "$OUTPUT_DIR"
