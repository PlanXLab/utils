#!/bin/sh
set -eu

INSTALL_ROOT="${1:-$HOME}"

select_release() {
python3 - <<'PY'
import json
import platform
import urllib.request

api_url = "https://api.github.com/repos/nanomq/nanomq/releases/latest"
release = json.load(urllib.request.urlopen(api_url))
system = platform.system().lower()
arch = platform.machine().lower()

if arch in ("arm64", "aarch64"):
    want_arch = ("arm64", "aarch64")
elif arch.startswith("arm") or arch in ("armv7l", "armv6l"):
    want_arch = ("armv7", "armhf", "arm")
else:
    want_arch = ("amd64", "x86_64", "x64")

if system == "darwin":
    want_os = ("macos", "darwin", "mac")
    reject_os = ("linux", "windows", "win32", "win64")
    os_name = "macOS"
elif system == "linux":
    want_os = ("linux",)
    reject_os = ("macos", "darwin", "windows", "win32", "win64")
    os_name = "Linux"
else:
    raise SystemExit("Unsupported operating system: " + system)

assets = []
for asset in release["assets"]:
    name = asset["name"].lower()
    if (
        any(x in name for x in want_os)
        and not any(x in name for x in reject_os)
        and (name.endswith(".zip") or name.endswith(".tar.gz"))
    ):
        assets.append(asset)

if not assets:
    raise SystemExit("NanoMQ " + os_name + " asset was not found in the latest release.")

selected = None
for asset in assets:
    name = asset["name"].lower()
    if any(x in name for x in want_arch):
        selected = asset
        break

if selected is None:
    selected = assets[0]

print(release["tag_name"].lstrip("v"))
print(selected["browser_download_url"])
PY
}

version_eq() {
  awk -v a="$1" -v b="$2" 'BEGIN {
    split(a, A, "."); split(b, B, ".");
    for (i = 1; i <= 4; i++) {
      if ((A[i] + 0) != (B[i] + 0)) exit 1;
    }
    exit 0;
  }'
}

version_lt() {
  awk -v a="$1" -v b="$2" 'BEGIN {
    split(a, A, "."); split(b, B, ".");
    for (i = 1; i <= 4; i++) {
      av = A[i] + 0; bv = B[i] + 0;
      if (av < bv) exit 0;
      if (av > bv) exit 1;
    }
    exit 1;
  }'
}

version_gt() {
  awk -v a="$1" -v b="$2" 'BEGIN {
    split(a, A, "."); split(b, B, ".");
    for (i = 1; i <= 4; i++) {
      av = A[i] + 0; bv = B[i] + 0;
      if (av > bv) exit 0;
      if (av < bv) exit 1;
    }
    exit 1;
  }'
}

echo "Fetching latest NanoMQ release information..."
RELEASE_INFO="$(select_release)"
VERSION="$(printf "%s\n" "$RELEASE_INFO" | sed -n '1p')"
URL="$(printf "%s\n" "$RELEASE_INFO" | sed -n '2p')"
INSTALL_DIR="$INSTALL_ROOT/nanomq-$VERSION"
LEGACY_DIR="$INSTALL_ROOT/NanoMQ"

SAME_DIR=""
NEWER_DIR=""
for dir in "$INSTALL_ROOT"/nanomq-*; do
  [ -d "$dir" ] || continue
  installed_version="$(basename "$dir" | sed 's/^nanomq-//')"
  if version_eq "$installed_version" "$VERSION"; then
    SAME_DIR="$dir"
  elif version_gt "$installed_version" "$VERSION"; then
    NEWER_DIR="$dir"
  fi
done

if [ -d "$LEGACY_DIR" ]; then
  echo "Removing legacy NanoMQ installation: $LEGACY_DIR"
  rm -rf "$LEGACY_DIR"
fi

if [ -n "$NEWER_DIR" ]; then
  echo "A newer NanoMQ folder already exists: $NEWER_DIR"
  echo "No installation was changed."
  exit 0
fi

if [ -n "$SAME_DIR" ]; then
  echo "NanoMQ $VERSION is already installed in: $SAME_DIR"
  echo "Run it with:"
  echo "  cd \"$SAME_DIR\""
  echo "  ./run"
  exit 0
fi

for dir in "$INSTALL_ROOT"/nanomq-*; do
  [ -d "$dir" ] || continue
  old_version="$(basename "$dir" | sed 's/^nanomq-//')"
  if version_lt "$old_version" "$VERSION"; then
    echo "Removing older NanoMQ installation: $dir"
    rm -rf "$dir"
  fi
done

WORK_DIR="$(mktemp -d)"
ARCHIVE="$WORK_DIR/$(basename "$URL")"
EXTRACT_DIR="$WORK_DIR/extract"
mkdir -p "$EXTRACT_DIR" "$INSTALL_DIR"

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT INT TERM

echo "Selected asset: $(basename "$URL")"
echo "Downloading NanoMQ $VERSION..."
curl -L "$URL" -o "$ARCHIVE"

echo "Extracting NanoMQ..."
case "$ARCHIVE" in
  *.zip) unzip -q "$ARCHIVE" -d "$EXTRACT_DIR" ;;
  *.tar.gz) tar -xzf "$ARCHIVE" -C "$EXTRACT_DIR" ;;
  *) echo "Unsupported archive type: $ARCHIVE" >&2; exit 1 ;;
esac

BIN="$(find "$EXTRACT_DIR" -type f -name nanomq | head -n 1)"
if [ -z "$BIN" ]; then
  echo "nanomq binary was not found after extraction." >&2
  exit 1
fi

RUNTIME_ROOT="$(dirname "$BIN")"
DIST_ROOT="$RUNTIME_ROOT"
if [ "$(basename "$RUNTIME_ROOT")" = "bin" ]; then
  DIST_ROOT="$(dirname "$RUNTIME_ROOT")"
fi

cp "$BIN" "$INSTALL_DIR/nanomq"
chmod +x "$INSTALL_DIR/nanomq"

find "$RUNTIME_ROOT" -maxdepth 1 -type f \( -name "*.so" -o -name "*.so.*" -o -name "*.dylib" \) -exec cp {} "$INSTALL_DIR/" \;
if [ -d "$DIST_ROOT/lib" ]; then
  cp -R "$DIST_ROOT/lib" "$INSTALL_DIR/lib"
fi

cat > "$INSTALL_DIR/nanomq.conf" <<'EOF'
listeners.tcp {
  bind = "0.0.0.0:1883"
}

listeners.ws {
  bind = "127.0.0.1:8083/mqtt"
}
EOF

cat > "$INSTALL_DIR/run" <<'EOF'
#!/bin/sh
START_DIR=$(pwd)
BASE_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$BASE_DIR"
export NANOMQ_CONF_PATH="$BASE_DIR/nanomq.conf"
ERR_FILE="$BASE_DIR/nanomq.err.tmp"

cleanup_run() {
  if [ -f "$ERR_FILE" ]; then
    grep -v '^Abort finding default config path$' "$ERR_FILE" >&2 || true
    rm -f "$ERR_FILE"
  fi
  cd "$START_DIR"
}
trap cleanup_run EXIT INT TERM

./nanomq start --conf "$NANOMQ_CONF_PATH" 2> "$ERR_FILE"
EOF
chmod +x "$INSTALL_DIR/run"

echo
echo "NanoMQ $VERSION is installed in: $INSTALL_DIR"
echo "Run it with:"
echo "  cd \"$INSTALL_DIR\""
echo "  ./run"
