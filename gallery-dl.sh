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

# Install python dependencies
echo "🐹 Installing dependencies..."
dnf install -y python3 python3-requests

# Checkout the branch/tag we need to build
git fetch origin && git checkout v1.32.12

# Stage the source
mkdir -p build-stage/gallery_dl
cp -a gallery_dl/. build-stage/gallery_dl/

# Create the point
cat << 'EOF' > build-stage/__main__.py
import sys
from gallery_dl import main
sys.exit(main())
EOF

python3 -m zipapp build-stage -p "/usr/bin/env python3" -o gallery-dl

# Process the Output
echo "✅ Build completed! Moving binary to output folder..."
# Create the output directory in the parent folder (the repository root)
mkdir -p ../output_binaries

# Verify the binary actually exists before trying to move it
if [ -f "gallery-dl" ]; then
    cp gallery-dl ../output_binaries/

    # Make it executable
    chmod +x ../output_binaries/gallery-dl

    echo "${TARGET_REF}-$(git rev-parse --short HEAD)" > ../output_binaries/release_tag.txt
    echo "🎉 Success! Binary saved to output_binaries/gallery-dl"
else
    echo "❌ ERROR: gallery-dl not found!"
    echo "The build might have failed silently or output to a different path."
    exit 1
fi
