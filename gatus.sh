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

echo "📦 Target branch and submodule: $TARGET_REF"

# Prepare the Git workspace
git config --global --add safe.directory /workspace

# Fetch branches and checkout the target branch
echo "🔄 Fetching repository and checking out branch '$TARGET_REF'..."
git fetch --all --tags
git checkout "$TARGET_REF"

# Initialize and pull the submodule code now that we are on the correct branch
echo "📥 Initializing and updating submodules..."
git submodule update --init --recursive

# Mark the newly created submodule directory as safe
git config --global --add safe.directory "/workspace/$TARGET_REF"

# Navigate into the submodule
if [ ! -d "$TARGET_REF" ]; then
    echo "❌ ERROR: Submodule directory '$TARGET_REF' not found after checkout!"
    exit 1
fi

cd "$TARGET_REF"

# Install Golang
dnf -y install golang

# Compile gatus
GOOS=linux GOARCH=amd64 make install

# Process the Output
echo "✅ Build completed! Moving binary to output folder..."
# Create the output directory in the parent folder (the repository root)
mkdir -p ../output_binaries

# Verify the binary actually exists before trying to move it
if [ -f "gatus" ]; then
    cp gatus ../output_binaries/

    # Make it executable
    chmod +x ../output_binaries/gatus

    echo "🎉 Success! Binary saved to output_binaries/gatus"
else
    echo "❌ ERROR: gatus not found!"
    echo "The build might have failed silently or output to a different path."
    exit 1
fi
