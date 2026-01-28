#!/bin/bash

set -e
trap 'echo "ERROR at line $LINENO: Command failed"' ERR

# Configuration
WORK_DIR="$HOME/image"
SRC_DIR="$WORK_DIR/source"
ROOTFS="$WORK_DIR/rootfs"
USB_IMAGE="$WORK_DIR/Very-Small-Linux.img"
KERNEL_VERSION="6.6.8"
KERNEL_URL="https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-${KERNEL_VERSION}.tar.xz"
# Your binary that open when the ISO loads.
READER_BINARY="$HOME/reader" 

NUM_JOBS=$(nproc)

echo "============================================"
echo "Creating directories"
echo "============================================"
mkdir -p "$WORK_DIR" "$SRC_DIR" "$ROOTFS"/{root,dev,proc,sys}

echo "============================================"
echo "Installing dependencies"
echo "============================================"
sudo apt-get update
sudo apt-get install -y \
    wget build-essential bc flex bison \
    libelf-dev gcc libssl-dev parted dosfstools \
    cpio gzip grub-efi-amd64-bin grub-common

echo "============================================"
echo "Downloading kernel"
echo "============================================"
cd "$SRC_DIR"
if [ ! -f "linux-${KERNEL_VERSION}.tar.xz" ]; then
    wget -c "$KERNEL_URL"
fi

cd "$WORK_DIR"
if [ ! -d "linux-${KERNEL_VERSION}" ]; then
    tar -xf "$SRC_DIR/linux-${KERNEL_VERSION}.tar.xz"
fi

echo "============================================"
echo "Creating init program"
echo "============================================"

cat > "$WORK_DIR/init.c" << 'INITEOF'
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <sys/mount.h>
#include <sys/reboot.h>
#include <sys/sysmacros.h>
#include <linux/reboot.h>
#include <fcntl.h>
#include <string.h>
#include <errno.h>
#include <dirent.h>
#include <sys/stat.h>

void flush_output() {
    fflush(stdout);
    fflush(stderr);
    sync();
}

void show_mounts() {
    printf("\nCurrent mounts:\n");
    FILE *f = fopen("/proc/mounts", "r");
    if (f) {
        char line[256];
        while (fgets(line, sizeof(line), f)) {
            printf("%s", line);
        }
        fclose(f);
    }
    flush_output();
}

void show_devices() {
    printf("\nAvailable block devices:\n");
    DIR *dir = opendir("/dev");
    if (dir) {
        struct dirent *entry;
        while ((entry = readdir(dir)) != NULL) {
            if (strncmp(entry->d_name, "sd", 2) == 0 || 
                strncmp(entry->d_name, "dm-", 3) == 0) {
                printf("/dev/%s\n", entry->d_name);
            }
        }
        closedir(dir);
    }
    flush_output();
}

void show_directory(const char *path) {
    printf("\nContents of %s:\n", path);
    DIR *dir = opendir(path);
    if (dir) {
        struct dirent *entry;
        int count = 0;
        while ((entry = readdir(dir)) != NULL && count++ < 15) {
            printf("%s\n", entry->d_name);
        }
        closedir(dir);
    }
    flush_output();
}

int try_mount_device(const char *device, const char *mount_point) {
    const char *fstypes[] = {"exfat", "vfat", "ntfs", "ext4", "ext3", "ext2", NULL};
    
    for (int i = 0; fstypes[i] != NULL; i++) {
        if (mount(device, mount_point, fstypes[i], MS_RDONLY, NULL) == 0) {
            printf("Mounted %s as %s\n", device, fstypes[i]);
            flush_output();
            return 1;
        }
    }
    return 0;
}

int main() {
    // Make output unbuffered
    setvbuf(stdout, NULL, _IONBF, 0);
    setvbuf(stderr, NULL, _IONBF, 0);
    
    mount("proc", "/proc", "proc", 0, NULL);
    mount("sysfs", "/sys", "sysfs", 0, NULL);
    mount("devtmpfs", "/dev", "devtmpfs", 0, NULL);
    
    printf("\n");
    printf("==========================================\n");
    printf("VERY SMALL LINUX BOOT SYSTEM v1.0\n");
    printf("==========================================\n");
    flush_output();
    
    printf("\n[1/5] Waiting for devices...\n");
    flush_output();
    sleep(5);
    
    printf("\n[2/5] Scanning for block devices...\n");
    show_devices();
    
    mkdir("/mnt", 0755);
    
    printf("\n[3/5] Searching for E-USB.conf marker...\n");
    flush_output();
    
    char device[32];
    int found = 0;
    
    // First try device mapper devices (Ventoy uses these!)
    for (int i = 0; i <= 5 && !found; i++) {
        snprintf(device, sizeof(device), "/dev/dm-%d", i);
        
        if (access(device, F_OK) != 0) continue;
        
        printf("\n  Trying %s (Ventoy/dm)...\n", device);
        flush_output();
        
        if (try_mount_device(device, "/mnt")) {
            show_directory("/mnt");
            
            if (access("/mnt/E-USB.conf", F_OK) == 0) {
                printf("\nFOUND E-USB.conf on %s!\n", device);
                flush_output();
                found = 1;
                break;
            }
            printf("No E-USB.conf, unmounting...\n");
            flush_output();
            umount("/mnt");
        }
    }
    
    // If not found, try regular partitions
    if (!found) {
        const char *drives[] = {"sda", "sdb", "sdc", "vda", "hda", NULL};
        
        for (int d = 0; drives[d] != NULL && !found; d++) {
            for (int part = 1; part <= 4 && !found; part++) {
                snprintf(device, sizeof(device), "/dev/%s%d", drives[d], part);
                
                if (access(device, F_OK) != 0) continue;
                
                printf("\n  Trying %s...\n", device);
                flush_output();
                
                if (try_mount_device(device, "/mnt")) {
                    show_directory("/mnt");
                    
                    if (access("/mnt/E-USB.conf", F_OK) == 0) {
                        printf("\nFOUND E-USB.conf on %s!\n", device);
                        flush_output();
                        found = 1;
                        break;
                    }
                    printf("No E-USB.conf, unmounting...\n");
                    flush_output();
                    umount("/mnt");
                }
            }
        }
    }
    
    if (!found) {
        printf("\n");
        printf("==========================================\n");
        printf(" ERROR: E-USB.conf NOT FOUND\n");
        printf("==========================================\n");
        show_mounts();
        show_devices();
        printf("\nSystem will power off in 60 seconds...\n");
        printf("Press Ctrl+Alt+Del to reboot now.\n");
        flush_output();
        sleep(60);
        reboot(LINUX_REBOOT_CMD_POWER_OFF);
        return 1;
    }
    
    printf("\n[4/5] Starting reader application...\n");
    flush_output();
    
    // Set up environment for reader
    setenv("TERM", "linux", 1);
    setenv("HOME", "/root", 1);
    setenv("PATH", "/bin:/sbin:/usr/bin:/usr/sbin", 1);
    
    // Create terminal devices if they don't exist
    if (access("/dev/tty", F_OK) != 0) {
        mknod("/dev/tty", S_IFCHR | 0666, makedev(5, 0));
    }
    if (access("/dev/console", F_OK) != 0) {
        mknod("/dev/console", S_IFCHR | 0600, makedev(5, 1));
    }
    
    printf("\n=== READER DEBUG INFO ===\n");
    
    // Check 1: Binary exists
    printf("1. Binary exists: ");
    flush_output();
    if (access("/root/reader", F_OK) == 0) {
        printf("YES\n");
    } else {
        printf("NO - FATAL ERROR\n");
        printf("\nContents of /root:\n");
        show_directory("/root");
        printf("\nPowering off in 30 seconds...\n");
        flush_output();
        sleep(30);
        reboot(LINUX_REBOOT_CMD_POWER_OFF);
        return 1;
    }
    
    // Check 2: Binary executable
    printf("2. Binary executable: ");
    flush_output();
    if (access("/root/reader", X_OK) == 0) {
        printf("YES\n");
    } else {
        printf("NO - Fixing permissions...\n");
        chmod("/root/reader", 0755);
        if (access("/root/reader", X_OK) == 0) {
            printf("Fixed successfully\n");
        } else {
            printf("FAILED to fix\n");
        }
    }
    
    // Check 3: Binary type
    printf("3. Binary info:\n");
    flush_output();
    
    FILE *fp = popen("file /root/reader 2>&1", "r");
    if (fp) {
        char line[256];
        while (fgets(line, sizeof(line), fp)) {
            printf("%s", line);
        }
        pclose(fp);
    }
    
    struct stat st;
    if (stat("/root/reader", &st) == 0) {
        printf("Size: %ld bytes\n", st.st_size);
        printf("Mode: %o\n", st.st_mode & 0777);
    }
    
    // Check 4: Dynamic linking
    printf("4. Checking dependencies:\n");
    flush_output();
    
    fp = popen("ldd /root/reader 2>&1", "r");
    if (fp) {
        char line[256];
        int has_libs = 0;
        while (fgets(line, sizeof(line), fp)) {
            printf("%s", line);
            if (strstr(line, "=>") && !strstr(line, "statically linked")) {
                has_libs = 1;
            }
        }
        pclose(fp);
        if (has_libs) {
            printf("WARNING: Binary appears to be dynamically linked!\n");
        }
    }
    
    // Check 5: Mount point accessible
    printf("5. Mount point accessible: ");
    flush_output();
    if (access("/mnt", R_OK) == 0) {
        printf("YES\n");
        show_directory("/mnt");
    } else {
        printf("NO - FATAL ERROR\n");
        flush_output();
        sleep(30);
        reboot(LINUX_REBOOT_CMD_POWER_OFF);
        return 1;
    }
    
    // Check 6: Environment
    printf("6. Environment variables:\n");
    printf("TERM=%s\n", getenv("TERM"));
    printf("HOME=%s\n", getenv("HOME"));
    printf("PATH=%s\n", getenv("PATH"));
    
    printf("\n=== ATTEMPTING EXECUTION ===\n");
    printf("Command: /root/reader /mnt\n");
    printf("Working directory: /root\n");
    flush_output();
    sleep(2);
    
    chdir("/root");
    char *args[] = { "/root/reader", "/mnt", NULL };
    char *envp[] = { 
        "TERM=linux", 
        "HOME=/root", 
        "PATH=/bin:/sbin:/usr/bin:/usr/sbin",
        NULL 
    };
    
    execve("/root/reader", args, envp);
    
    // If we reach here, exec failed
    printf("\n");
    printf("==========================================\n");
    printf("EXECUTION FAILED\n");
    printf("==========================================\n");
    printf("\n");
    printf("Error number: %d\n", errno);
    printf("Error message: %s\n", strerror(errno));
    printf("\nCommon error codes:\n");
    printf("2  = ENOENT (No such file)\n");
    printf("8  = ENOEXEC (Invalid binary format)\n");
    printf("13 = EACCES (Permission denied)\n");
    
    printf("\nBinary header (first 128 bytes):\n");
    flush_output();
    
    fp = popen("hexdump -C /root/reader 2>&1 | head -8", "r");
    if (fp) {
        char line[256];
        while (fgets(line, sizeof(line), fp)) {
            printf("%s", line);
        }
        pclose(fp);
    }
    
    printf("\n==========================================\n");
    printf("Keeping system alive for 2 minutes...\n");
    printf("Press Ctrl+Alt+Del to reboot.\n");
    printf("==========================================\n");
    flush_output();
    
    sleep(120);
    reboot(LINUX_REBOOT_CMD_POWER_OFF);
    return 1;
}
INITEOF

gcc -static "$WORK_DIR/init.c" -o "$ROOTFS/init"
chmod +x "$ROOTFS/init"

echo "============================================"
echo "Copying your reader binary"
echo "============================================"

if [ -f "$READER_BINARY" ]; then
    sudo cp "$READER_BINARY" "$ROOTFS/root/reader"
    sudo chmod +x "$ROOTFS/root/reader"
    echo "Reader binary copied"
else
    echo "Reader binary not found at: $READER_BINARY"
    echo "Using placeholder instead"
fi

echo "============================================"
echo "Creating initramfs"
echo "============================================"
cd "$ROOTFS"
find . | cpio -H newc -o | gzip -9 > "$WORK_DIR/initramfs.cpio.gz"
echo "Initramfs size: $(du -h $WORK_DIR/initramfs.cpio.gz | cut -f1)"

echo "============================================"
echo "Configuring kernel WITH EFI SUPPORT"
echo "============================================"
cd "$WORK_DIR/linux-${KERNEL_VERSION}"

# Force clean build
make mrproper

# Create config file directly
cat > .config << 'KCONFIG'
CONFIG_64BIT=y
CONFIG_X86_64=y
CONFIG_SMP=y

# EFI SUPPORT
CONFIG_EFI=y
CONFIG_EFI_STUB=y
CONFIG_EFI_MIXED=y
CONFIG_EFI_VARS=y
CONFIG_FB_EFI=y
CONFIG_FRAMEBUFFER_CONSOLE=y

# Basic system
CONFIG_BINFMT_ELF=y
CONFIG_BINFMT_SCRIPT=y
CONFIG_SYSFS=y
CONFIG_PROC_FS=y
CONFIG_DEVTMPFS=y
CONFIG_DEVTMPFS_MOUNT=y
CONFIG_TMPFS=y

# TTY and console
CONFIG_TTY=y
CONFIG_VT=y
CONFIG_VT_CONSOLE=y
CONFIG_HW_CONSOLE=y
CONFIG_UNIX98_PTYS=y
CONFIG_SERIAL_8250=y
CONFIG_SERIAL_8250_CONSOLE=y

# Framebuffer
CONFIG_FB=y
CONFIG_DUMMY_CONSOLE=y

# Block layer - CRITICAL!
CONFIG_BLOCK=y
CONFIG_BLK_DEV=y
CONFIG_BLK_DEV_LOOP=y
CONFIG_BLK_DEV_INITRD=y
CONFIG_RD_GZIP=y

# SCSI support - REQUIRED for USB storage!
CONFIG_SCSI=y
CONFIG_SCSI_MOD=y
CONFIG_BLK_DEV_SD=y
CONFIG_BLK_DEV_SR=y
CONFIG_CHR_DEV_SG=y

# ATA/SATA support - REQUIRED for hard drives!
CONFIG_ATA=y
CONFIG_ATA_ACPI=y
CONFIG_SATA_AHCI=y
CONFIG_ATA_PIIX=y
CONFIG_PATA_AMD=y
CONFIG_ATA_GENERIC=y

# USB support
CONFIG_USB_SUPPORT=y
CONFIG_USB=y
CONFIG_USB_ANNOUNCE_NEW_DEVICES=y
CONFIG_USB_PCI=y
CONFIG_USB_XHCI_HCD=y
CONFIG_USB_XHCI_PCI=y
CONFIG_USB_EHCI_HCD=y
CONFIG_USB_EHCI_PCI=y
CONFIG_USB_OHCI_HCD=y
CONFIG_USB_OHCI_HCD_PCI=y
CONFIG_USB_UHCI_HCD=y
CONFIG_USB_STORAGE=y

# Partition tables - REQUIRED!
CONFIG_PARTITION_ADVANCED=y
CONFIG_MSDOS_PARTITION=y
CONFIG_EFI_PARTITION=y
CONFIG_LDM_PARTITION=y

# Filesystems - REQUIRED!
CONFIG_EXT4_FS=y
CONFIG_EXT4_USE_FOR_EXT2=y
CONFIG_VFAT_FS=y
CONFIG_FAT_FS=y
CONFIG_FAT_DEFAULT_CODEPAGE=437
CONFIG_FAT_DEFAULT_IOCHARSET="iso8859-1"
CONFIG_EXFAT_FS=y
CONFIG_NTFS_FS=y
CONFIG_NTFS_RW=y
CONFIG_ISO9660_FS=y
CONFIG_JOLIET=y

# Character sets
CONFIG_NLS=y
CONFIG_NLS_DEFAULT="utf8"
CONFIG_NLS_CODEPAGE_437=y
CONFIG_NLS_ASCII=y
CONFIG_NLS_ISO8859_1=y
CONFIG_NLS_UTF8=y

# PCI
CONFIG_PCI=y
CONFIG_PCIEPORTBUS=y

# File locking
CONFIG_FILE_LOCKING=y

# Printk
CONFIG_PRINTK=y
CONFIG_EARLY_PRINTK=y

# Disable modules
CONFIG_MODULES=n
KCONFIG

make olddefconfig

echo ""
echo "============================================"
echo "VERIFYING EFI CONFIGURATION:"
echo "============================================"
if grep -q "CONFIG_EFI_STUB=y" .config; then
    echo "CONFIG_EFI_STUB=y (GOOD)"
else
    echo "CONFIG_EFI_STUB missing (BAD)"
    exit 1
fi

if grep -q "CONFIG_EFI=y" .config; then
    echo "CONFIG_EFI=y (GOOD)"
else
    echo "CONFIG_EFI missing (BAD)"
    exit 1
fi

echo "============================================"
echo ""

echo "Building kernel (5-10 minutes)..."
make -j"$NUM_JOBS" bzImage

if [ ! -f "arch/x86/boot/bzImage" ]; then
    echo "ERROR: Kernel build failed!"
    exit 1
fi

KERNEL_PATH="$WORK_DIR/linux-${KERNEL_VERSION}/arch/x86/boot/bzImage"
echo "Kernel size: $(du -h $KERNEL_PATH | cut -f1)"

echo "============================================"
echo "Creating bootable USB image"
echo "============================================"
dd if=/dev/zero of="$USB_IMAGE" bs=1M count=40
parted -s "$USB_IMAGE" mklabel gpt
parted -s "$USB_IMAGE" mkpart ESP fat32 1MiB 39MiB
parted -s "$USB_IMAGE" set 1 esp on

LOOP_DEV=$(sudo losetup --find --show --partscan "$USB_IMAGE")
sudo mkfs.vfat -F32 "${LOOP_DEV}p1"

MOUNT_DIR=$(mktemp -d)
sudo mount "${LOOP_DEV}p1" "$MOUNT_DIR"

echo "============================================"
echo "Installing GRUB and kernel"
echo "============================================"
sudo mkdir -p "$MOUNT_DIR/boot/grub"
sudo mkdir -p "$MOUNT_DIR/EFI/BOOT"

# Copy files to boot directory
sudo cp "$KERNEL_PATH" "$MOUNT_DIR/boot/vmlinuz"
sudo cp "$WORK_DIR/initramfs.cpio.gz" "$MOUNT_DIR/boot/initramfs.gz"

# Create a temporary directory for grub-mkstandalone
GRUB_TEMP=$(mktemp -d)

# Copy files to temp directory for embedding
mkdir -p "$GRUB_TEMP/boot/grub"
mkdir -p "$GRUB_TEMP/boot"
cp "$KERNEL_PATH" "$GRUB_TEMP/boot/vmlinuz"
cp "$WORK_DIR/initramfs.cpio.gz" "$GRUB_TEMP/boot/initramfs.gz"

# Create GRUB config
cat > "$GRUB_TEMP/boot/grub/grub.cfg" << 'GRUBEOF'
set timeout=1
set default=0

menuentry "VERY SMALL Linux" {
    linux (memdisk)/boot/vmlinuz quiet console=ttyS0 console=tty0
    initrd (memdisk)/boot/initramfs.gz
}
GRUBEOF

# Build GRUB with embedded files
sudo grub-mkstandalone \
    --format=x86_64-efi \
    --output="$MOUNT_DIR/EFI/BOOT/BOOTX64.EFI" \
    --locales="" \
    --fonts="" \
    --compress=xz \
    "boot/grub/grub.cfg=$GRUB_TEMP/boot/grub/grub.cfg" \
    "boot/vmlinuz=$GRUB_TEMP/boot/vmlinuz" \
    "boot/initramfs.gz=$GRUB_TEMP/boot/initramfs.gz"

# Cleanup temp directory
rm -rf "$GRUB_TEMP"

echo ""
echo "Verifying installation:"
sudo ls -lh "$MOUNT_DIR/boot/" || echo "boot dir empty (files embedded in GRUB)"
sudo ls -lh "$MOUNT_DIR/EFI/BOOT/"

sudo umount "$MOUNT_DIR"
sudo losetup -d "$LOOP_DEV"
rmdir "$MOUNT_DIR"

echo ""
echo "============================================"
echo "BUILD COMPLETE!"
echo "============================================"
echo "Image: $USB_IMAGE"
echo "Size: $(du -h $USB_IMAGE | cut -f1)"
echo ""
echo "Test: qemu-system-x86_64 -bios /usr/share/ovmf/OVMF.fd -drive file=$USB_IMAGE,format=raw -m 256M"
echo "============================================"
