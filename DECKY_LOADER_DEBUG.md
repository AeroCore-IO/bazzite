# Decky Loader Service Debug Guide

## Issue Description
User reported that the `decky-install.service` file was not appearing in `/usr/lib/systemd/system/` during testing.

## How to Verify the Fix

### 1. Check File Exists After Build
After building the container, verify the service file is present:
```bash
podman run --rm -it localhost/your-image:tag ls -la /usr/lib/systemd/system/decky-install.service
```

### 2. Check Service is Enabled
Verify the symlink for service enablement exists:
```bash
podman run --rm -it localhost/your-image:tag ls -la /etc/systemd/system/multi-user.target.wants/decky-install.service
```

## Build Process Enhancements

The following enhancements were added to make the build process more robust:

### 1. File Existence Verification
- Build now checks that `decky-install.service` exists before creating symlink
- Fails with clear error message if file is missing

### 2. Enhanced Error Reporting
- Detailed error messages when files are missing
- Directory listings for debugging
- Clear indication of what step failed

### 3. Inline installer execution
- `decky-install.service` now runs the upstream Decky installer scripts directly
  via `curl` instead of relying on pre-copied helper files.

## Expected Build Output

With the enhanced error checking, you should see output like:
```
==> Configure Decky Loader installation service
Found decky-install.service, presetting service
Successfully processed decky-install.service preset
[file and symlink details]
```

## Troubleshooting

If the build fails with Decky installation errors:

1. **Check source files exist:**
   ```bash
   ls -la system_files/shared/usr/lib/systemd/system/decky-install.service
   ```

2. **Verify file copying worked:**
   Look for the error messages in build output that show directory contents

3. **Check build target:**
   Ensure you're building the correct target that includes decky-loader support

## Files Modified
- `Containerfile`: Added error checking and debugging output
- Updated decky-install.service to inline upstream installer execution
