#!/usr/bin/env bash
#
# Pixel Canary pif.json generator (plain Linux, unprivileged)
# Rewrite of autopif4.sh by osm0sis @ xda-developers
#
# Requires: bash, curl, GNU coreutils (date, tac, mktemp), grep, sed

set -u

DEVICE="bluejay"
OUT="pif.json"
UNICA=1
RANDOM_DEVICE=0

usage() {
  cat <<EOF
Usage: $0 [options]

  -o, --output FILE   Output file (default: pif.json); parent dirs are created
  -d, --device NAME   Pixel codename to use (default: bluejay)
  -r, --random        Pick a random Pixel Beta device instead of --device
  -u, --unica         UN1CA format: only FINGERPRINT, SECURITY_PATCH,
                      DEVICE_INITIAL_SDK_INT and VERSION (YYYYMMDD)  [default]
      --no-unica      Full format: MANUFACTURER, MODEL, FINGERPRINT, PRODUCT,
                      DEVICE, SECURITY_PATCH, DEVICE_INITIAL_SDK_INT
  -h, --help          Show this help
EOF
}

item() { printf '\n- %s\n' "$*"; }
warn() { printf '\nWarning: %s!\n' "$*" >&2; }
die()  { printf '\nError: %s!\n' "$*" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help|help) usage; exit 0;;
    -o|--output)
      [ $# -ge 2 ] || die "$1 needs an argument"
      OUT="$2"; shift 2;;
    -d|--device)
      [ $# -ge 2 ] || die "$1 needs an argument"
      DEVICE="$2"; shift 2;;
    -r|--random|random) RANDOM_DEVICE=1; shift;;
    -u|-unica|--unica|unica) UNICA=1; shift;;
    --no-unica) UNICA=0; shift;;
    *) usage >&2; die "unknown option: $1";;
  esac
done

echo "Pixel Canary pif.json generator script"
echo "  by osm0sis @ xda-developers"

for cmd in curl tac grep sed date mktemp; do
  command -v "$cmd" >/dev/null 2>&1 || die "missing required command: $cmd"
done
date -u -d '2000-01-01 +1 week' +%F >/dev/null 2>&1 || die "GNU date required"

TMP="$(mktemp -d)" || die "cannot create temp dir"
trap 'rm -rf "$TMP"' EXIT

fetch() { # fetch URL DEST
  curl -fsSL --retry 2 --max-time 30 -o "$2" "$1" || die "download failed: $1"
}

DEVICE="${DEVICE%_beta}"

model_for() {
  case "$1" in
    bluejay) echo "Pixel 6a";;
    panther) echo "Pixel 7";;
    cheetah) echo "Pixel 7 Pro";;
    lynx) echo "Pixel 7a";;
    felix) echo "Pixel Fold";;
    tangorpro) echo "Pixel Tablet";;
    shiba) echo "Pixel 8";;
    husky) echo "Pixel 8 Pro";;
    akita) echo "Pixel 8a";;
    tokay) echo "Pixel 9";;
    caiman) echo "Pixel 9 Pro";;
    komodo) echo "Pixel 9 Pro XL";;
    comet) echo "Pixel 9 Pro Fold";;
    tegu) echo "Pixel 9a";;
    frankel) echo "Pixel 10";;
    blazer) echo "Pixel 10 Pro";;
    mustang) echo "Pixel 10 Pro XL";;
    rango) echo "Pixel 10 Pro Fold";;
    stallion) echo "Pixel 10a";;
  esac
}

# Fills $TMP/models.txt and $TMP/products.txt (one entry per line, same order)
crawl_devices() {
  item "Crawling Android Developers for latest Pixel Beta device list ..."
  local latest fi_path ota_path src
  fetch "https://developer.android.com/about/versions" "$TMP/versions.html"
  latest="$(grep -B4 -A2 'data-icon="preview' "$TMP/versions.html" | grep -o 'href="/about/versions/.*[0-9]"' | cut -d'"' -f2 | head -n1)"
  [ "$latest" ] || latest="$(grep -oE 'href="/about/versions/[0-9]{2}"' "$TMP/versions.html" | cut -d'"' -f2 | sort -ru | head -n1)"
  [ "$latest" ] || die "Failed to find latest Android beta page"
  fetch "https://developer.android.com$latest" "$TMP/latest.html"
  fi_path="$(grep -o 'href=".*download.*"' "$TMP/latest.html" | grep -v 'ota' | cut -d'"' -f2 | sort -ru | head -n1)"
  ota_path="$(grep -o 'href=".*download-ota.*"' "$TMP/latest.html" | cut -d'"' -f2 | sort -ru | head -n1)"
  fetch "https://developer.android.com$fi_path" "$TMP/fi.html"
  fetch "https://developer.android.com$ota_path" "$TMP/ota.html"
  src=fi
  [ "$(grep -c 'tr id=' "$TMP/fi.html")" -lt "$(grep -c 'tr id=' "$TMP/ota.html")" ] && src=ota
  grep -A1 'tr id=' "$TMP/$src.html" | grep 'td' | sed 's;.*<td>\(.*\)</td>.*;\1;' > "$TMP/models.txt"
  grep 'tr id=' "$TMP/$src.html" | sed 's;.*<tr id="\(.*\)">.*;\1_beta;' > "$TMP/products.txt"
  [ -s "$TMP/products.txt" ] || die "Failed to parse Pixel Beta device list"
  wc -l < "$TMP/products.txt"
}

item "Selecting Pixel Beta device ..."
MODEL=""
if [ "$RANDOM_DEVICE" = 1 ]; then
  crawl_devices
  idx=$(( RANDOM % $(wc -l < "$TMP/products.txt") + 1 ))
  PRODUCT="$(sed -n "${idx}p" "$TMP/products.txt")"
  MODEL="$(sed -n "${idx}p" "$TMP/models.txt")"
  DEVICE="${PRODUCT%_beta}"
else
  PRODUCT="${DEVICE}_beta"
  if [ "$UNICA" = 0 ]; then # MODEL is only needed for the full format
    MODEL="$(model_for "$DEVICE")"
    if [ -z "$MODEL" ]; then
      crawl_devices
      idx="$(grep -nxF "$PRODUCT" "$TMP/products.txt" | head -n1 | cut -d: -f1)"
      [ "$idx" ] || die "$PRODUCT not found in the Pixel Beta device list"
      MODEL="$(sed -n "${idx}p" "$TMP/models.txt")"
    fi
  fi
fi
echo "${MODEL:+$MODEL }($PRODUCT)"

item "Crawling Android Flash Tool for latest Pixel Canary build info ..."
fetch "https://flash.android.com/" "$TMP/flash.html"
API_KEY="$(grep -o '<body data-client-config=.*' "$TMP/flash.html" | cut -d';' -f2 | cut -d'&' -f1)"
[ "$API_KEY" ] || die "Failed to extract Flash Tool API key"
curl -fsSL --retry 2 --max-time 30 -H "Referer: https://flash.android.com" \
  -o "$TMP/station.json" \
  "https://content-flashstation-pa.googleapis.com/v1/builds?product=$PRODUCT&key=$API_KEY" \
  || die "Flash Station request failed for $PRODUCT"
tac "$TMP/station.json" | grep -m1 -A13 '"canary": true' > "$TMP/canary.json"
ID="$(grep 'releaseCandidateName' "$TMP/canary.json" | cut -d'"' -f4)"
INCREMENTAL="$(grep 'buildId' "$TMP/canary.json" | cut -d'"' -f4)"
[ -z "$ID" ] || [ -z "$INCREMENTAL" ] && die "Failed to extract build info from JSON for $PRODUCT"
echo "Android $(grep 'releaseTrackVersionName' "$TMP/canary.json" | cut -d'"' -f4)"

FI="$(grep 'factoryImageDownloadUrl' "$TMP/canary.json" | cut -d'"' -f4)"
LAST_MOD=""
if [ -n "$FI" ]; then
  LAST_MOD="$(curl -sIL --max-time 20 "$FI" | tr -d '\r' | grep -i -m1 '^last-modified:' | cut -d' ' -f2-)"
else
  warn "Failed to extract Factory Image URL from JSON"
fi
if [ -n "$LAST_MOD" ] && REL="$(date -u -d "$LAST_MOD" +%F 2>/dev/null)"; then
  echo "Canary Released: $REL"
  echo "Estimated Expiry: $(date -u -d "$REL + 6 weeks" +%F)"
else
  warn "Failed to determine Release Date from HTTP headers"
fi

item "Crawling Pixel Update Bulletins for corresponding security patch level ..."
CANARY_ID="$(grep '"id"' "$TMP/canary.json" | sed -e 's;.*canary-\(.*\)".*;\1;' -e 's;^\(.\{4\}\);\1-;')"
[ -z "$CANARY_ID" ] && die "Failed to extract canary id from JSON"
fetch "https://source.android.com/docs/security/bulletin/pixel" "$TMP/secbull.html"
SECURITY_PATCH="$(grep "<td>$CANARY_ID" "$TMP/secbull.html" | sed 's;.*<td>\([^<]*\)</td>.*;\1;' | head -n1)"
if [ -z "$SECURITY_PATCH" ]; then
  warn "Failed to determine exact security patch level from Pixel Update Bulletins"
  item "Assuming probable security patch level from Canary build info ..."
  SECURITY_PATCH="${CANARY_ID}-05"
fi
echo "$SECURITY_PATCH"

item "Adding corresponding first API level ..."
case "$DEVICE" in
  bluejay) DEVICE_INITIAL_SDK_INT=32;; # Pixel 6a
  panther|cheetah) DEVICE_INITIAL_SDK_INT=33;; # Pixel 7 Series
  lynx) DEVICE_INITIAL_SDK_INT=33;; # Pixel 7a
  felix) DEVICE_INITIAL_SDK_INT=33;; # Pixel Fold
  tangorpro) DEVICE_INITIAL_SDK_INT=33;; # Pixel Tablet
  shiba|husky) DEVICE_INITIAL_SDK_INT=34;; # Pixel 8 Series
  akita) DEVICE_INITIAL_SDK_INT=34;; # Pixel 8a
  tokay|caiman|komodo|comet) DEVICE_INITIAL_SDK_INT=34;; # Pixel 9 Series
  tegu) DEVICE_INITIAL_SDK_INT=35;; # Pixel 9a
  frankel|blazer|mustang|rango) DEVICE_INITIAL_SDK_INT=36;; # Pixel 10 Series
  stallion) DEVICE_INITIAL_SDK_INT=35;; # Pixel 10a; Actual 36
  cubs|grizzly|kodiak|yogi) DEVICE_INITIAL_SDK_INT=37;; # Pixel 11 Series
  *) DEVICE_INITIAL_SDK_INT=37;;
esac
echo "$DEVICE_INITIAL_SDK_INT"
[ "$DEVICE_INITIAL_SDK_INT" -gt 35 ] && warn "First API level 36 and greater may require an RKP keybox to pass"

FINGERPRINT="google/$PRODUCT/$DEVICE:CANARY/$ID/$INCREMENTAL:user/release-keys"
VERSION="$(date -u +%Y%m%d)"

item "Writing $OUT ..."
mkdir -p "$(dirname "$OUT")" || die "cannot create output directory"
if [ "$UNICA" = 1 ]; then
  cat > "$TMP/out.json" <<EOF
{
  "FINGERPRINT": "$FINGERPRINT",
  "SECURITY_PATCH": "$SECURITY_PATCH",
  "DEVICE_INITIAL_SDK_INT": "$DEVICE_INITIAL_SDK_INT",
  "VERSION": "$VERSION"
}
EOF
else
  [ -n "$MODEL" ] || die "Model name unknown"
  cat > "$TMP/out.json" <<EOF
{
  "VERSION": "20261112",
  "MANUFACTURER": "Google",
  "MODEL": "$MODEL",
  "FINGERPRINT": "$FINGERPRINT",
  "PRODUCT": "$PRODUCT",
  "DEVICE": "$DEVICE",
  "SECURITY_PATCH": "$SECURITY_PATCH",
  "DEVICE_INITIAL_SDK_INT": "$DEVICE_INITIAL_SDK_INT"
}
EOF
fi
cat "$TMP/out.json" > "$OUT" || die "cannot write $OUT"
cat "$OUT"
