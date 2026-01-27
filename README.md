# Very-Small-Linux

A very tiny linux img to launch a binary after boot

About 14MB, the image will be about 40MB for extra padding, sometimes required for proper booting.

The script fetches Linux kernel, a few required packages and creates a bootable .img for UEFI USB sticks.

When the .img is booted, a simple binary loads.

# Binary

The `reader` binary is a simple file reader that reads the USB stick.

If you want to compile it yourself:

### Recompile as static binary (no dependencies!)

`gcc -static -Os -s reader.c -o reader`

### Verify it's truly static

`ldd reader`

The .sh script automatically copies it over into /root/reader (do not do this manually!)

# USB img

The .img **must** be placed an a USB stick with `Ventoy` installed.

Ventoy: https://www.ventoy.net/en/index.html

---

# Build Script Overview

### 1. **Downloads & Compiles Linux Kernel (6.6.8)**
   - Configured for UEFI boot support
   - Includes filesystem drivers: exFAT, VFAT, NTFS, ext4
   - Enables Ventoy compatibility (device-mapper support)
   - Removes unnecessary features (sound, wireless, etc.) to minimize size

### 2. **Creates Custom Init System**
   - Compiles a static C program that runs at boot
   - Automatically detects and mounts USB drives
   - Searches for `E-USB.conf` marker file
   - Launches the reader application when found

### 3. **Builds Initial RAM Filesystem (initramfs)**
   - Includes the reader binary
   - Creates minimal directory structure

### 4. **Generates Bootable Image**
   - Creates GPT partition table
   - Formats EFI system partition (FAT32)
   - Installs systemd-boot bootloader
   - Copies kernel and boot configuration

### 5. **Output**
   - Produces `.img` ready to flash to USB
   - Size: ~40MB (minimal footprint)
   - Boot time: ~5-10 seconds
     
---
