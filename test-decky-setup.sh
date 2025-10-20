#!/bin/bash
# Test script to validate decky-install.service setup
# This script tests the file copying and service enablement logic

set -e

echo "==> Testing decky-install.service setup logic"

# Create test environment
TEST_ROOT="/tmp/bazzite-decky-test"
rm -rf "$TEST_ROOT"
mkdir -p "$TEST_ROOT"

echo "==> Copying system files (simulating Containerfile COPY operations)"

# Get the project root
PROJECT_ROOT="$(git rev-parse --show-toplevel)"

# Copy shared files (first COPY in Containerfile)
rsync -av "$PROJECT_ROOT/system_files/shared/" "$TEST_ROOT/"

# Copy desktop shared files (second part of first COPY)
rsync -av "$PROJECT_ROOT/system_files/desktop/shared/" "$TEST_ROOT/"

cd "$TEST_ROOT"

echo "==> Verifying decky-install.service uses ujust wrapper"
if grep -q "ujust setup-decky" usr/lib/systemd/system/decky-install.service; then
    echo "✓ decky-install.service invokes ujust setup-decky"
else
    echo "✗ ERROR: decky-install.service is not configured to use ujust"
    exit 1
fi

echo "==> Testing decky-install.service preset"

# Test service preset logic
if [ -f usr/lib/systemd/system/decky-install.service ]; then
    echo "✓ Found decky-install.service, creating symlink to enable service"
    mkdir -p etc/systemd/system/multi-user.target.wants
    ln -s /usr/lib/systemd/system/decky-install.service \
              etc/systemd/system/multi-user.target.wants/decky-install.service
    echo "✓ Successfully enabled decky-install.service"
    echo "Service file:"
    ls -la usr/lib/systemd/system/decky-install.service
    echo "Enablement symlink:"
    ls -la etc/systemd/system/multi-user.target.wants/decky-install.service
    mkdir -p var/lib
    touch var/lib/decky-installed
    echo "✓ Created /var/lib/decky-installed marker"
else
    echo "✗ ERROR: decky-install.service not found at usr/lib/systemd/system/decky-install.service"
    echo "Listing contents of usr/lib/systemd/system/:"
    ls -la usr/lib/systemd/system/
    exit 1
fi

echo "==> Testing deck variant (simulating deck COPY)"
# Copy deck files (simulating deck build stage)
rsync -av "$PROJECT_ROOT/system_files/deck/shared/" "$TEST_ROOT/"

# Verify decky-install.service still exists after deck copy
if [ -f usr/lib/systemd/system/decky-install.service ]; then
    echo "✓ decky-install.service still present after deck files copy"
else
    echo "✗ ERROR: decky-install.service missing after deck files copy"
    exit 1
fi

echo "==> All tests passed! ✓"
echo "The decky-install.service setup should work correctly in the build."

# Cleanup
rm -rf "$TEST_ROOT"
echo "==> Cleanup completed"