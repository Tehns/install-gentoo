#!/bin/bash
set -e

DISK=/dev/sda
HOSTNAME=gentoo
TIMEZONE=UTC

echo ">>> Проверка UEFI"
[ -d /sys/firmware/efi ] || { echo "НЕ UEFI"; exit 1; }

echo ">>> Синхронизация времени"
ntpd -q -g || true

echo ">>> Разметка диска"
wipefs -a $DISK
parted -s $DISK mklabel gpt
parted -s $DISK mkpart EFI fat32 1MiB 513MiB
parted -s $DISK set 1 esp on
parted -s $DISK mkpart ROOT ext4 513MiB 100%

mkfs.fat -F32 ${DISK}1
mkfs.ext4 ${DISK}2

mount ${DISK}2 /mnt/gentoo
mkdir -p /mnt/gentoo/boot/efi
mount ${DISK}1 /mnt/gentoo/boot/efi

cd /mnt/gentoo

echo ">>> Скачивание stage3"
wget https://distfiles.gentoo.org/releases/amd64/autobuilds/current-stage3-amd64-systemd/stage3-amd64-systemd-*.tar.xz
tar xpvf stage3-*.tar.xz --xattrs-include='*.*' --numeric-owner

echo ">>> Настройка make.conf"
cat <<EOF >> /mnt/gentoo/etc/portage/make.conf
COMMON_FLAGS="-O2 -pipe"
CFLAGS="\${COMMON_FLAGS}"
CXXFLAGS="\${COMMON_FLAGS}"
MAKEOPTS="-j$(nproc)"
USE="systemd"
EOF

echo ">>> DNS"
cp --dereference /etc/resolv.conf /mnt/gentoo/etc/

mount --types proc /proc /mnt/gentoo/proc
mount --rbind /sys /mnt/gentoo/sys
mount --make-rslave /mnt/gentoo/sys
mount --rbind /dev /mnt/gentoo/dev
mount --make-rslave /mnt/gentoo/dev

echo ">>> Chroot"
chroot /mnt/gentoo /bin/bash <<EOF
source /etc/profile
export PS1="(gentoo) \$PS1"

echo ">>> Sync"
emerge --sync

echo ">>> Profile"
eselect profile set default/linux/amd64/17.1/systemd

echo ">>> Timezone"
echo "$TIMEZONE" > /etc/timezone
emerge --config sys-libs/timezone-data

echo ">>> Locale"
echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
locale-gen
eselect locale set en_US.utf8
env-update && source /etc/profile

echo ">>> Kernel"
emerge sys-kernel/gentoo-kernel-bin

echo ">>> FSTAB"
cat <<FSTAB > /etc/fstab
${DISK}2  /          ext4  noatime  0 1
${DISK}1  /boot/efi  vfat  defaults 0 2
FSTAB

echo ">>> Network"
emerge net-misc/networkmanager
systemctl enable NetworkManager

echo ">>> Bootloader"
emerge sys-boot/grub:2
grub-install --target=x86_64-efi --efi-directory=/boot/efi
grub-mkconfig -o /boot/grub/grub.cfg

echo ">>> Root password"
echo "root:gentoo" | chpasswd

echo ">>> Done inside chroot"
EOF

echo ">>> Установка завершена"
echo "root пароль: gentoo"
echo "Можно reboot"
