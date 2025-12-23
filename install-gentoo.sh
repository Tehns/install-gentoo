#!/bin/bash
set -e

# Disk configuration
DISK=/dev/sda
EFI=${DISK}1
SWAP=${DISK}2
ROOT=${DISK}3

# System settings
TIMEZONE=UTC
ROOT_PASS=gentoo
PROFILE=default/linux/amd64/17.1

echo "[WARNING] ALL DATA ON $DISK WILL BE ERASED"
read -p "Type yes to continue: " ok
[ "$ok" = "yes" ] || exit 1

echo "Enter username:"
read USERNAME

echo "Enter password for user $USERNAME:"
read -s USER_PASS
echo
echo "Confirm password:"
read -s USER_PASS2
echo

if [ "$USER_PASS" != "$USER_PASS2" ]; then
    echo "Passwords do not match"
    exit 1
fi

echo "Checking UEFI"
if [ ! -d /sys/firmware/efi ]; then
    echo "UEFI not detected"
    exit 1
fi

echo "Partitioning disk"
wipefs -a $DISK
parted -s $DISK mklabel gpt
parted -s $DISK mkpart primary fat32 1MiB 1025MiB
parted -s $DISK set 1 esp on
parted -s $DISK mkpart primary linux-swap 1025MiB 5121MiB
parted -s $DISK mkpart primary ext4 5121MiB 100%

echo "Formatting partitions"
mkfs.fat -F32 $EFI
mkswap $SWAP
swapon $SWAP
mkfs.ext4 $ROOT

echo "Mounting partitions"
mount $ROOT /mnt/gentoo
mkdir -p /mnt/gentoo/boot/efi
mount $EFI /mnt/gentoo/boot/efi

echo "Downloading stage3"
cd /mnt/gentoo

STAGE3_BASE=https://distfiles.gentoo.org/releases/amd64/autobuilds/current-stage3-amd64-openrc

wget ${STAGE3_BASE}/latest-stage3-amd64-openrc.txt

STAGE3_PATH=$(grep '\.tar\.xz$' latest-stage3-amd64-openrc.txt | head -n 1)
STAGE3_FILE=$(basename "$STAGE3_PATH")

wget ${STAGE3_BASE}/${STAGE3_PATH}

echo "Extracting stage3"
tar xpvf ${STAGE3_FILE} --xattrs-include='*.*' --numeric-owner

echo "Configuring make.conf"
cat <<EOF >> /mnt/gentoo/etc/portage/make.conf
COMMON_FLAGS="-O2 -pipe"
CFLAGS="\${COMMON_FLAGS}"
CXXFLAGS="\${COMMON_FLAGS}"
MAKEOPTS="-j$(nproc)"
EOF

echo "Configuring DNS"
cp /etc/resolv.conf /mnt/gentoo/etc/

mount --types proc /proc /mnt/gentoo/proc
mount --rbind /sys /mnt/gentoo/sys
mount --make-rslave /mnt/gentoo/sys
mount --rbind /dev /mnt/gentoo/dev
mount --make-rslave /mnt/gentoo/dev

echo "Entering chroot"
chroot /mnt/gentoo /bin/bash <<EOF
source /etc/profile

echo "Syncing Portage"
emerge --sync

echo "Selecting profile"
eselect profile set ${PROFILE}

echo "Configuring timezone"
echo "${TIMEZONE}" > /etc/timezone
emerge --config sys-libs/timezone-data

echo "Configuring locale"
echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
locale-gen
eselect locale set en_US.utf8
env-update
source /etc/profile

echo "Installing kernel"
emerge sys-kernel/gentoo-kernel-bin

echo "Writing fstab"
cat <<FSTAB > /etc/fstab
${ROOT}  /          ext4  noatime  0 1
${EFI}   /boot/efi  vfat  defaults 0 2
${SWAP}  none       swap  sw       0 0
FSTAB

echo "Installing network"
emerge net-misc/dhcpcd
rc-update add dhcpcd default

echo "Installing sudo"
emerge app-admin/sudo

echo "Installing GRUB"
emerge sys-boot/grub:2
grub-install --target=x86_64-efi --efi-directory=/boot/efi
grub-mkconfig -o /boot/grub/grub.cfg

echo "Setting passwords"
echo "root:${ROOT_PASS}" | chpasswd
useradd -m -G wheel,audio,video ${USERNAME}
echo "${USERNAME}:${USER_PASS}" | chpasswd

sed -i 's/^# %wheel ALL=(ALL) ALL/%wheel ALL=(ALL) ALL/' /etc/sudoers

echo "INSTALL COMPLETE"
EOF

echo "DONE. Reboot system."
