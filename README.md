# Very-Small-Linux

A very tiny GNU Linux distro img to launch a binary after boot.

About 14MB, the image will be about 40MB for extra padding, sometimes required for proper booting.

The script fetches Linux kernel, a few required packages and creates a bootable .img for UEFI USB sticks.

When the .img is booted, a simple binary loads.

# Filesize

These figures are estimates, it varies upon build. Expect a small **stable** Linux ISO or IMG to be around 40MB.


| Range        | Purpose                                                                                                                                                                        |
| ------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| 0-1 MB       | Boot area: Reserved for the bootloader (BIOS/UEFI). Contains GRUB or Syslinux, El Torito structures, and initial boot code. Must be aligned, can't overlap files.              |
| 1-14 MB      | Minimal kernel: Compressed `vmlinuz` typically takes 10-14 MB. Needs to sit contiguously for the bootloader to load reliably.                                                  |
| 14-23 MB     | Initramfs / initrd: Compressed image around 9 MB, but during early boot, bootloader loads it into memory as if it were larger (uncompressed). Needs contiguous space.          |
| 23-32 MB     | Filesystem metadata + padding: ISO9660 / UDF / Rock Ridge directories, path tables, and file extents. Sector alignment inflates size.                                          |
| 32-40 MB     | Extra padding / alignment slack: Ensures sectors, partitions, and memory addresses meet bootloader and BIOS/UEFI expectations. Some firmware requires minimum size ranges.     |


Less padding might work on some (embedded) systems, but it might also fail. Especially below 32MB.

# Binary

The `reader` binary is a simple file reader that reads the USB stick. It is a custom made terminal to read and browse files. It simply serves as an example as to how you could write a binary that loads upon boot.

If you want to compile it yourself:

### Recompile as static binary (no dependencies!)

`gcc -static -Os -s reader.c -o reader`

### Verify it's truly static

`ldd reader`

The .sh script automatically copies it over into /root/reader (do not do this manually!)

# USB img

The .img **must** be placed on a USB stick with `Ventoy` installed.

Ventoy: https://www.ventoy.net/en/index.html

`E-USB.conf` **must** also be placed in the root of the USB stick. Linux init looks for this file: Currently, it simply looks for this file and does not read the config. But wihtout it, Linux will not run. Later on, we can read settings and so on without having to recompile the binary.

---

# Build Script Overview

### 1. Downloads & Compiles Linux Kernel (6.6.8)
   - Configured for UEFI boot support
   - Includes filesystem drivers: exFAT, VFAT, NTFS, ext4
   - Enables Ventoy compatibility (device-mapper support)
   - Removes unnecessary features (sound, wireless, etc.) to minimize size

### 2. Creates Custom Init System
   - Compiles a static C program that runs at boot
   - Automatically detects and mounts USB drives
   - Searches for `E-USB.conf` marker file
   - Launches the reader application when found

### 3. Builds Initial RAM Filesystem (initramfs)
   - Includes the reader binary
   - Creates minimal directory structure

### 4. Generates Bootable Image
   - Creates GPT partition table
   - Formats EFI system partition (FAT32)
   - Installs systemd-boot bootloader
   - Copies kernel and boot configuration

### 5. Output
   - Produces `.img` ready to flash to USB
   - Size: ~40MB (minimal footprint)
   - Boot time: ~3-5 seconds
     
---
```
╔═══════════════════════════════════════════════════╗
║                                                   ║
║          OFFICIAL NERD CERTIFICATION              ║
║                                                   ║
║  This certifies that the bearer has:              ║
║                                                   ║
║  Compiled a Linux kernel from source              ║
║  Debugged boot failures at 3 AM                   ║
║  Understood what "initramfs" actually means       ║
║  Fixed makedev() with sys/sysmacros.h             ║
║  Survived 107 reboots without rage-quitting       ║
║  Can now explain UEFI boot to mortals             ║
║                                                   ║
║  Level: KERNEL WIZARD                             ║
║  XP Gained: 12 hours                              ║
║                                                   ║
║  Signed: Linus Torvalds (in spirit)               ║
║  Date: Today                                      ║
║                                                   ║
╚═══════════════════════════════════════════════════╝
```
