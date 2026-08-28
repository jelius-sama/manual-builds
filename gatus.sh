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
echo "🐹 Installing the latest Golang..."

# Determine system architecture
ARCH=$(uname -m)
if [ "$ARCH" = "x86_64" ]; then
    GO_ARCH="amd64"
elif [ "$ARCH" = "aarch64" ]; then
    GO_ARCH="arm64"
else
    echo "❌ ERROR: Unsupported architecture: $ARCH"
    exit 1
fi

# Fetch the latest Go version string (e.g., "go1.26.3")
GO_VERSION=$(curl -s https://go.dev/VERSION?m=text | head -n 1)
echo "⬇️ Downloading ${GO_VERSION} for linux-${GO_ARCH}..."

# Download the tarball
curl -O -L "https://go.dev/dl/${GO_VERSION}.linux-${GO_ARCH}.tar.gz"

# Remove any existing Go installation and extract the new one
rm -rf /usr/local/go
tar -C /usr/local -xzf "${GO_VERSION}.linux-${GO_ARCH}.tar.gz"

# Clean up the downloaded tarball
rm "${GO_VERSION}.linux-${GO_ARCH}.tar.gz"

# Add Go to the PATH for the remainder of this script
export PATH=$PATH:/usr/local/go/bin

# Verify the installation
if ! go version; then
    exit 1
fi

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

    echo "${TARGET_REF}-$(git rev-parse --short HEAD)" > ../output_binaries/release_tag.txt
    echo "🎉 Success! Binary saved to output_binaries/gatus"
else
    echo "❌ ERROR: gatus not found!"
    echo "The build might have failed silently or output to a different path."
    exit 1
fi
