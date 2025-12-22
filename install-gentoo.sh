#!/bin/bash
set -e

DISK=/dev/sda
EFI=${DISK}1
SWAP=${DISK}2
ROOT=${DISK}3

TIMEZONE=UTC
ROOT_PASS=gentoo

echo "[WARNING] ALL DATA ON $DISK WILL BE ERASED"
read -p "Type yes to continue: " ok
[ "$ok" = "yes" ] || exit 1

echo "Checking UEFI"
[ -d /sys/firmware/efi ] || { echo "UEFI not found"; exit 1; }

echo "Partitioning disk"
wipefs -a $DISK
parted -s $DISK mklabel gpt
parted -s $DISK mkpart primary fat32 1MiB 1025MiB
parted -s $DISK set 1 esp on
parted -s $DISK mkpart primary linux-swap 1025MiB 5121MiB
parted -s $DISK mkpart primary ext4 5121MiB 100%

echo "Formatting"
mkfs.fat -F32 $EFI
mkswap $SWAP
swapon $SWAP
mkfs.ext4 $ROOT

echo "Mounting"
mount $ROOT /mnt/gentoo
mkdir -p /mnt/gentoo/boot/efi
mount $EFI /mnt/gentoo/boot/efi

echo "Downloading stage3"
cd /mnt/gentoo
wget https://distfiles.gentoo.org/releases/amd64/autobuilds/current-stage3-amd64-openrc/stage3-amd64-openrc.tar.xz
tar xpvf stage3-amd64-openrc.tar.xz --xattrs-include='*.*' --numeric-owner

echo "Configuring make.conf"
cat <<EOF >> /mnt/gentoo/etc/portage/make.conf
COMMON_FLAGS="-O2 -pipe"
CFLAGS="\${COMMON_FLAGS}"
CXXFLAGS="\${COMMON_FLAGS}"
MAKEOPTS="-j$(nproc)"
EOF

cp /etc/resolv.conf /mnt/gentoo/etc/

mount --types proc /proc /mnt/gentoo/proc
mount --rbind /sys /mnt/gentoo/sys
mount --make-rslave /mnt/gentoo/sys
mount --rbind /dev /mnt/gentoo/dev
mount --make-rslave /mnt/gentoo/dev

chroot /mnt/gentoo /bin/bash <<EOF
source /etc/profile

echo "Syncing portage"
emerge --sync

eselect profile set default/linux/amd64/17.1

echo "$TIMEZONE" > /etc/timezone
emerge --config sys-libs/timezone-data

echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
locale-gen
eselect locale set en_US.utf8
env-update && source /etc/profile

emerge sys-kernel/gentoo-kernel-bin

cat <<FSTAB > /etc/fstab
$ROOT  /          ext4  noatime  0 1
$EFI   /boot/efi  vfat  defaults 0 2
$SWAP  none       swap  sw       0 0
FSTAB

emerge net-misc/dhcpcd
rc-update add dhcpcd default

emerge sys-boot/grub:2
grub-install --target=x86_64-efi --efi-directory=/boot/efi
grub-mkconfig -o /boot/grub/grub.cfg

echo "root:$ROOT_PASS" | chpasswd

echo "INSTALL DONE"
EOF

echo "DONE - reboot system"
