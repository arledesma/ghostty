#!/usr/bin/env bash
#
# build-msix.sh -- Build an MSIX package for Ghostty on Windows.
#
# This script assembles the MSIX layout from the compiled ghostty.exe
# binary, the AppxManifest.xml, and placeholder assets, then invokes
# MakeAppx.exe to produce the .msix package. Optionally self-signs
# the package for sideloading.
#
# Usage:
#   ./build-msix.sh --binary /path/to/ghostty.exe [--output ghostty.msix] [--sign]
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STAGING_DIR="${SCRIPT_DIR}/_msix_staging"

# ---------- Defaults ----------
BINARY=""
OUTPUT="ghostty.msix"
SIGN=false

# ---------- Argument parsing ----------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --binary)
            BINARY="$2"
            shift 2
            ;;
        --output)
            OUTPUT="$2"
            shift 2
            ;;
        --sign)
            SIGN=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 --binary PATH [--output PATH] [--sign]"
            echo ""
            echo "  --binary PATH   Path to compiled ghostty.exe (required)"
            echo "  --output PATH   Output .msix file path (default: ghostty.msix)"
            echo "  --sign          Self-sign the package for sideloading"
            exit 0
            ;;
        *)
            echo "Error: Unknown option '$1'" >&2
            exit 1
            ;;
    esac
done

if [[ -z "$BINARY" ]]; then
    echo "Error: --binary PATH is required" >&2
    echo "Usage: $0 --binary PATH [--output PATH] [--sign]" >&2
    exit 1
fi

if [[ ! -f "$BINARY" ]]; then
    echo "Error: Binary not found at '$BINARY'" >&2
    exit 1
fi

# ---------- Locate Windows SDK tools ----------
find_sdk_tool() {
    local tool="$1"

    # Check if already in PATH
    if command -v "$tool" &>/dev/null; then
        echo "$tool"
        return 0
    fi

    # Search default Windows SDK install locations
    local sdk_base="C:/Program Files (x86)/Windows Kits/10/bin"
    if [[ -d "$sdk_base" ]]; then
        # Find the latest SDK version directory containing the tool
        local found
        found=$(find "$sdk_base" -maxdepth 2 -path "*/x64/${tool}" 2>/dev/null | sort -V | tail -1)
        if [[ -n "$found" ]]; then
            echo "$found"
            return 0
        fi
    fi

    echo "Error: ${tool} not found in PATH or Windows SDK directories" >&2
    echo "Install the Windows SDK or add its bin/x64 directory to PATH" >&2
    return 1
}

MAKEAPPX=$(find_sdk_tool "MakeAppx.exe")
echo "Using MakeAppx: ${MAKEAPPX}"

# ---------- Stage the package layout ----------
echo "Staging MSIX layout..."

# Clean any previous staging directory
rm -rf "$STAGING_DIR"
mkdir -p "${STAGING_DIR}/assets"

# Copy the compiled binary
cp "$BINARY" "${STAGING_DIR}/ghostty.exe"

# Copy the manifest
cp "${SCRIPT_DIR}/AppxManifest.xml" "${STAGING_DIR}/AppxManifest.xml"

# Copy assets
cp "${SCRIPT_DIR}"/assets/*.png "${STAGING_DIR}/assets/"

echo "Staged files:"
ls -la "${STAGING_DIR}/"
ls -la "${STAGING_DIR}/assets/"

# ---------- Create the MSIX package ----------
echo ""
echo "Creating MSIX package..."
"$MAKEAPPX" pack /d "$STAGING_DIR" /p "$OUTPUT" /o

echo "Package created: ${OUTPUT}"

# ---------- Optionally self-sign the package ----------
if [[ "$SIGN" == true ]]; then
    SIGNTOOL=$(find_sdk_tool "SignTool.exe")
    echo "Using SignTool: ${SIGNTOOL}"

    PFX_FILE="${SCRIPT_DIR}/ghostty-dev.pfx"

    # Generate a self-signed certificate if one doesn't exist
    if [[ ! -f "$PFX_FILE" ]]; then
        echo "Generating self-signed certificate..."
        powershell -Command "
            \$cert = New-SelfSignedCertificate \
                -Type Custom \
                -Subject 'CN=GhosttyDev' \
                -KeyUsage DigitalSignature \
                -FriendlyName 'Ghostty Dev' \
                -CertStoreLocation 'Cert:\CurrentUser\My' \
                -TextExtension @('2.5.29.37={text}1.3.6.1.5.5.7.3.3');
            Export-PfxCertificate \
                -Cert \$cert \
                -FilePath '${PFX_FILE}' \
                -Password (ConvertTo-SecureString -String 'ghostty' -Force -AsPlainText)
        "
        echo "Certificate created: ${PFX_FILE}"
    else
        echo "Using existing certificate: ${PFX_FILE}"
    fi

    # Sign the package
    echo "Signing package..."
    "$SIGNTOOL" sign /fd SHA256 /a /f "$PFX_FILE" /p ghostty "$OUTPUT"
    echo "Package signed successfully."
fi

# ---------- Cleanup ----------
echo ""
echo "Cleaning up staging directory..."
rm -rf "$STAGING_DIR"

# ---------- Report ----------
echo ""
echo "=== Build complete ==="
echo "Output: ${OUTPUT}"
if [[ -f "$OUTPUT" ]]; then
    SIZE=$(stat --printf="%s" "$OUTPUT" 2>/dev/null || stat -f%z "$OUTPUT" 2>/dev/null || echo "unknown")
    echo "Size:   ${SIZE} bytes"
fi
