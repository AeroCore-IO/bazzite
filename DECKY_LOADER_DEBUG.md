# Decky Loader Service Debug Guide

## Issue Description
User reported that the `decky-loader.service` file was not appearing in `/usr/lib/systemd/user/` during testing.

## How to Verify the Fix

### 1. Check File Exists After Build
After building the container, verify the service file is present:
```bash
podman run --rm -it localhost/your-image:tag ls -la /usr/lib/systemd/user/decky-loader.service
```

### 2. Check Service is Enabled
Verify the symlink for service enablement exists:
```bash
podman run --rm -it localhost/your-image:tag ls -la /etc/systemd/user/gamescope-session.target.wants/decky-loader.service
```

### 3. Check Decky Installer Scripts
Verify the installer scripts are present and executable:
```bash
podman run --rm -it localhost/your-image:tag ls -la /usr/share/decky-installer/
```

## Build Process Enhancements

The following enhancements were added to make the build process more robust:

### 1. File Existence Verification
- Build now checks that `decky-loader.service` exists before creating symlink
- Fails with clear error message if file is missing

### 2. Enhanced Error Reporting
- Detailed error messages when files are missing
- Directory listings for debugging
- Clear indication of what step failed

### 3. Improved Script Setup
- Verification that decky-installer directory exists
- Better error handling for script permission setup

## Expected Build Output

With the enhanced error checking, you should see output like:
```
==> Setting up Decky Installer scripts
Found decky-installer directory, making scripts executable
[listing of executable scripts]
Decky installer scripts setup complete

==> Enable Decky Loader auto-installer
Found decky-loader.service, creating symlink to enable service
Successfully enabled decky-loader.service
[file and symlink details]
```

## Troubleshooting

If the build fails with decky-loader errors:

1. **Check source files exist:**
   ```bash
   ls -la system_files/shared/usr/lib/systemd/user/decky-loader.service
   ls -la system_files/shared/usr/share/decky-installer/
   ```

2. **Verify file copying worked:**
   Look for the error messages in build output that show directory contents

3. **Check build target:**
   Ensure you're building the correct target that includes decky-loader support

## Files Modified
- `Containerfile`: Added error checking and debugging output
- Enhanced both decky-installer script setup and service enablement sections