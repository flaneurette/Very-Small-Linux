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
