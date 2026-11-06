#!/usr/bin/env bash
set -euo pipefail

IN="$1"
OUT="$2"
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"
W=$(mktemp -d)

SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
BT=""
if [ -n "$SDK" ]; then
  BT=$(ls -d "${SDK}"/build-tools/* 2>/dev/null | sort -V | tail -1 || true)
fi
if [ -n "$BT" ] && [ -x "$BT/zipalign" ] && [ -x "$BT/apksigner" ]; then
  ZIPALIGN="$BT/zipalign"
  APKSIGNER="$BT/apksigner"
else
  ZIPALIGN="$(command -v zipalign)"
  APKSIGNER="$(command -v apksigner)"
fi
echo "zipalign:  $ZIPALIGN"
echo "apksigner: $APKSIGNER"

KEYSTORE="$W/k.jks"
keytool -genkeypair -v -keystore "$KEYSTORE" -storepass android \
  -keypass android -alias k -keyalg RSA -keysize 2048 \
  -validity 10000 -dname "CN=repack"

TARGETS=(
  "assets/bin/Data/Managed/Metadata/global-metadata.dat"
  "lib/arm64-v8a/libil2cpp.so"
  "lib/armeabi-v7a/libil2cpp.so"
)

patch_one() {
  local apk="$1" d changed_f
  d="$W/$(basename "$apk").d"
  changed_f="$d.changed"
  : > "$changed_f"
  mkdir -p "$d"

  local have=()
  for t in "${TARGETS[@]}"; do
    if unzip -l "$apk" "$t" >/dev/null 2>&1; then have+=("$t"); fi
  done
  if [ ${#have[@]} -eq 0 ]; then
    echo "  no patch targets in $(basename "$apk")"
    return 0
  fi

  ( cd "$d" && unzip -o -q "$apk" "${have[@]}" )
  python3 tools/patch.py "$d" patches.txt "$changed_f"

  local changed=()
  while IFS= read -r line; do
    [ -n "$line" ] && [ -f "$d/$line" ] && changed+=("$line")
  done < "$changed_f"

  if [ ${#changed[@]} -eq 0 ]; then
    echo "  nothing patched in $(basename "$apk")"
    return 0
  fi

  touch "${changed[@]/#/$d/}"
  ( cd "$d" && zip -0 -q "$apk" "${changed[@]}" )

  "$ZIPALIGN" -P 16 -f 4 "$apk" "$apk.aligned"
  mv "$apk.aligned" "$apk"

  "$APKSIGNER" sign --ks "$KEYSTORE" --ks-pass pass:android \
    --key-pass pass:android --out "$apk.signed" "$apk"
  mv "$apk.signed" "$apk"

  echo "  patched + signed $(basename "$apk")"
}

if unzip -l "$IN" 2>/dev/null | grep -q '\.apk$'; then
  echo "== XAPK detected =="
  mkdir -p "$W/x"
  unzip -o -q "$IN" -d "$W/x"
  while IFS= read -r -d '' a; do
    patch_one "$a"
  done < <(find "$W/x" -name '*.apk' -print0)
  ( cd "$W/x" && zip -0 -q -r "$OUT/modded.xapk" . )
  echo "OUTPUT: $OUT/modded.xapk"
else
  echo "== APK =="
  cp "$IN" "$W/base.apk"
  patch_one "$W/base.apk"
  cp "$W/base.apk" "$OUT/modded.apk"
  echo "OUTPUT: $OUT/modded.apk"
fi

ls -lh "$OUT"
