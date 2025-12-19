#!/bin/bash
set -e

DISK=/dev/sda
EFI_PART=${DISK}1
SWAP_PART=${DISK}2
ROOT_PART=${DISK}3
HOSTNAME=gentoo
TIMEZONE=UTC
ROOT_PASSWORD=gentoo

echo "[WARNING] ALL DATA ON $DISK WILL BE ERASED!"
read -p "Continue? (yes): " ok
[ "$ok" = "yes" ] || { echo "Aborted."; exit 1; }

echo ">>> Checking UEFI"
if [ ! -d /sys/firmware/efi ]; then
    echo "[ERROR] UEFI not found. Script is designed for UEFI. Enable EFI and reboot the live ISO."
    exit 1
fi

echo ">>> Partitioning the disk"
wipefs -a $DISK
parted -s $DISK mklabel gpt
parted -s $DISK mkpart primary fat32 1MiB 1025MiB
parted -s $DISK set 1 esp on
parted -s $DISK mkpart primary linux-swap 1025MiB 5121MiB
parted -s $DISK mkpart primary ext4 5121MiB 100%

echo ">>> Formatting partitions"
mkfs.fat -F32 $EFI_PART
mkswap $SWAP_PART
swapon $SWAP_PART
mkfs.ext4 $ROOT_PART

echo ">>> Mounting partitions"
mount $ROOT_PART /mnt/gentoo
mkdir -p /mnt/gentoo/boot/efi
mount $EFI_PART /mnt/gentoo/boot/efi

echo ">>> Downloading and extracting Stage3"
cd /mnt/gentoo
STAGE3=$(curl -s https://www.gentoo.org/downloads/ | grep -o 'stage3-amd64-systemd-.*\.tar\.xz' | head -n1)
wget https://distfiles.gentoo.org/releases/amd64/autobuilds/current-stage3-amd64-systemd/$STAGE3
tar xpvf $STAGE3 --xattrs-include='*.*' --numeric-owner

echo ">>> Configuring make.conf"
cat <<EOF >> /mnt/gentoo/etc/portage/make.conf
COMMON_FLAGS="-O2 -pipe"
CFLAGS="\${COMMON_FLAGS}"
CXXFLAGS="\${COMMON_FLAGS}"
MAKEOPTS="-j$(nproc)"
USE="systemd"
EOF

echo ">>> Setting DNS"
cp --dereference /etc/resolv.conf /mnt/gentoo/etc/

mount --types proc /proc /mnt/gentoo/proc
mount --rbind /sys /mnt/gentoo/sys
mount --make-rslave /mnt/gentoo/sys
mount --rbind /dev /mnt/gentoo/dev
mount --make-rslave /mnt/gentoo/dev

echo ">>> Chroot and base installation"
chroot /mnt/gentoo /bin/bash <<EOF
source /etc/profile
export PS1="(gentoo) \$PS1"

echo ">>> Sync Portage"
emerge --sync

echo ">>> Setting profile"
eselect profile set default/linux/amd64/17.1/systemd

echo ">>> Setting timezone"
echo "$TIMEZONE" > /etc/timezone
emerge --config sys-libs/timezone-data

echo ">>> Setting locale"
echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
locale-gen
eselect locale set en_US.utf8
env-update && source /etc/profile

echo ">>> Installing kernel"
emerge sys-kernel/gentoo-kernel-bin

echo ">>> Configuring fstab"
cat <<FSTAB > /etc/fstab
$ROOT_PART  /          ext4  noatime  0 1
$EFI_PART   /boot/efi  vfat  defaults 0 2
$SWAP_PART  none       swap  sw       0 0
FSTAB

echo ">>> Installing network manager"
emerge net-misc/networkmanager
systemctl enable NetworkManager

echo ">>> Installing GRUB (UEFI)"
emerge sys-boot/grub:2
grub-install --target=x86_64-efi --efi-directory=/boot/efi
grub-mkconfig -o /boot/grub/grub.cfg

echo ">>> Setting root password"
echo "root:$ROOT_PASSWORD" | chpasswd

echo "[DONE] Installation complete"
EOF

echo "[DONE] Installation complete!"
echo "Root password: $ROOT_PASSWORD"
echo "You can reboot the system now."
