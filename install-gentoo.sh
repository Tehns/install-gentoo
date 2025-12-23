#!/bin/bash
set -e

DISK=/dev/sda
EFI=${DISK}1
SWAP=${DISK}2
ROOT=${DISK}3

echo "[WARNING] ALL DATA ON $DISK WILL BE ERASED"
read -p "Type yes to continue: " ok
[ "$ok" = "yes" ] || exit 1

echo "Enter username:"
read USERNAME

echo "Enter password:"
read -s USER_PASS
echo
echo "Confirm password:"
read -s USER_PASS2
echo

[ "$USER_PASS" = "$USER_PASS2" ] || exit 1

echo "Checking UEFI"
[ -d /sys/firmware/efi ] || { echo "UEFI not found"; exit 1; }

echo "Partitioning disk"
wipefs -a $DISK
parted -s $DISK mklabel gpt
parted -s $DISK mkpart primary fat32 1MiB 1025MiB
parted -s $DISK set 1 esp on
parted -s $DISK mkpart primary linux-swap 1025MiB 5121MiB
parted -s $DISK mkpart primary ext4 5121MiB 100%

mkfs.fat -F32 $EFI
mkswap $SWAP
swapon $SWAP
mkfs.ext4 $ROOT

mount $ROOT /mnt/gentoo
mkdir -p /mnt/gentoo/boot/efi
mount $EFI /mnt/gentoo/boot/efi

cd /mnt/gentoo

echo "Downloading stage3 list"
STAGE_URL="https://distfiles.gentoo.org/releases/amd64/autobuilds/current-stage3-amd64-openrc"
wget -O stage3.txt ${STAGE_URL}/latest-stage3-amd64-openrc.txt

STAGE_FILE=$(grep ".tar.xz" stage3.txt | tail -n 1 | awk '{print $1}')
STAGE_NAME=$(basename "$STAGE_FILE")

echo "Downloading $STAGE_NAME"
wget ${STAGE_URL}/${STAGE_FILE}

echo "Extracting stage3"
tar xpvf ${STAGE_NAME} --xattrs-include='*.*' --numeric-owner

echo "Basic config"
cp /etc/resolv.conf /mnt/gentoo/etc/

mount --types proc /proc /mnt/gentoo/proc
mount --rbind /sys /mnt/gentoo/sys
mount --make-rslave /mnt/gentoo/sys
mount --rbind /dev /mnt/gentoo/dev
mount --make-rslave /mnt/gentoo/dev

chroot /mnt/gentoo /bin/bash <<EOF
source /etc/profile

emerge --sync
eselect profile set default/linux/amd64/17.1

echo "UTC" > /etc/timezone
emerge --config sys-libs/timezone-data

echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
locale-gen
eselect locale set en_US.utf8
env-update
source /etc/profile

emerge sys-kernel/gentoo-kernel-bin
emerge net-misc/dhcpcd app-admin/sudo sys-boot/grub:2

rc-update add dhcpcd default

cat <<FSTAB > /etc/fstab
${ROOT} / ext4 noatime 0 1
${EFI} /boot/efi vfat defaults 0 2
${SWAP} none swap sw 0 0
FSTAB

grub-install --target=x86_64-efi --efi-directory=/boot/efi
grub-mkconfig -o /boot/grub/grub.cfg

echo "root:gentoo" | chpasswd
useradd -m -G wheel,audio,video ${USERNAME}
echo "${USERNAME}:${USER_PASS}" | chpasswd
sed -i 's/^# %wheel ALL=(ALL) ALL/%wheel ALL=(ALL) ALL/' /etc/sudoers

echo "INSTALL DONE"
EOF

echo "Reboot now"
