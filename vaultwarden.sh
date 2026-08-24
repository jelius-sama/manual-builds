#!/bin/bash

# Enable strict error handling
set -euo pipefail

echo "======================================================"
echo " Starting Submodule Compilation on Amazon Linux 2023  "
echo "======================================================"

# Install System Dependencies
echo "🛠️ Installing AL2023 OS dependencies..."
dnf install -y gcc openssl-devel tar gzip git pkgconfig

# Verify the payload environment variable exists
if [ -z "${TARGET_REF:-}" ]; then
    echo "❌ ERROR: TARGET_REF environment variable is not set."
    echo "Ensure the workflow passes the payload value to Docker."
    exit 1
fi

echo "📂 Target submodule directory: $TARGET_REF"

# Prepare the Git workspace
# Tell Git it's safe to operate in the mounted directory and the submodule
git config --global --add safe.directory /workspace
git config --global --add safe.directory "/workspace/$TARGET_REF"

# Navigate into the submodule
if [ ! -d "$TARGET_REF" ]; then
    echo "❌ ERROR: Submodule directory '$TARGET_REF' not found!"
    echo "Did the checkout action clone the submodules?"
    exit 1
fi

cd "$TARGET_REF"

# Install Rust
echo "🦀 Installing Rust via rustup..."
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
source "$HOME/.cargo/env"

# Compile Vaultwarden
echo "🏗️ Starting cargo build (sqlite, release) inside $TARGET_REF..."
echo "⏳ This may take a while..."
cargo build --features 'sqlite' --release

# Process the Output
echo "✅ Build completed! Moving binary to output folder..."
# Create the output directory in the parent folder (the repository root)
mkdir -p ../output_binaries

# Verify the binary actually exists before trying to move it
if [ -f "target/release/vaultwarden" ]; then
    cp target/release/vaultwarden ../output_binaries/

    # Make it executable
    chmod +x ../output_binaries/vaultwarden 

    echo "🎉 Success! Binary saved to output_binaries/vaultwarden"
else
    echo "❌ ERROR: target/release/vaultwarden not found!"
    echo "The build might have failed silently or output to a different path."
    exit 1
fi
