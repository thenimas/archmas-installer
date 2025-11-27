#!/bin/bash

if [[ $EUID -ne 0 ]]; then
   echo "ERROR: This script must be run as root!"
   exit 1
fi

read -p "Enter new name for your PC (hostname): " HOST_NAME
echo " "

mkdir -p /target/etc/default
touch /target/etc/default/keyboard

echo "KEYMAP=us" > /target/etc/vconsole.conf

pacstrap -K /target base linux-lts linux-firmware efibootmgr sudo nano btrfs-progs wget dbus

arch-chroot /target /bin/bash << EOT

mount -a

# adding data we specified
ln -sf /usr/share/zoneinfo/Canada/Eastern /etc/localtime
echo "$HOST_NAME" > /etc/hostname
hwclock --systohc

# adding locale
echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen

export LC_CTYPE=en_US.UTF-8
export LC_ALL=en_US.UTF-8

wget https://github.com/thenimas/archmas-installer/raw/dev/configs/keyboard -O /etc/default/keyboard
wget https://github.com/thenimas/archmas-installer/raw/dev/configs/mirrorlist -O /etc/pacman.d/mirrorlist
wget https://github.com/thenimas/archmas-installer/raw/dev/configs/locale.conf -O /etc/locale.conf
wget https://github.com/thenimas/archmas-installer/raw/dev/configs/zram-generator.conf -O /etc/systemd/zram-generator.conf

mkdir -p /boot/grub
wget https://raw.githubusercontent.com/thenimas/archmas-installer/dev/assets/grub-full.png -O /boot/grub/grub-full.png
wget https://raw.githubusercontent.com/thenimas/archmas-installer/dev/assets/grub-wide.png -O /boot/grub/grub-wide.png

pacman -Syu --noconfirm

pacman -S --noconfirm --needed accountsservice ark base-devel bc bluez cantarell-fonts dex dmenu dosfstools fail2ban fastfetch flatpak gamemode gdb git gnome-software gnome-themes-extra grub gvfs i3-wm i3blocks i3lock i3status ibus jdk-openjdk kate lightdm lightdm-gtk-greeter linux lshw lxappearance lxinput maim man-db network-manager-applet nodejs noto-fonts noto-fonts-cjk noto-fonts-emoji noto-fonts-extra pavucontrol pipewire pipewire-alsa pipewire-audio pipewire-jack pipewire-pulse playerctl plymouth python redshift rxvt-unicode sox syncthing systemsettings thunar thunar-archive-plugin thunar-media-tags-plugin thunar-shares-plugin timeshift ttf-inconsolata ttf-liberation ufw virt-manager vlc wget xclip xdg-desktop-portal xdotool zram-generator cryptsetup systemd-cryptsetup-generator

cd ~

# git clone https://aur.archlinux.org/yay-bin.git
# cd yay-bin
# makepkg -si

# yes | lang=C yay -S gnome-icon-theme nitrogen qdirstat-bin ttf-comic-neue ttf-courier-prime 1.203-5 ttf-league-spartan ttf-symbola vscodium-bin xcursor-breeze

# yay -Y --gendb

cd ~
rm -rf ~/*
rm -rf ~/.*

# add firewall rules
ufw default deny incoming
ufw default allow outgoing
ufw allow 80
ufw allow 443
ufw allow syncthing
ufw enable

echo "%wheel      ALL=(ALL:ALL) ALL" >> /etc/sudoers

sed -i 's/HOOKS=(.*)/HOOKS=(base systemd autodetect microcode modconf kms keyboard keymap sd-vconsole block filesystems fsck keymap sd-encrypt plymouth)/g' /etc/mkinitcpio.conf

mkinitcpio -P
grub-install --target=x86_64-efi --modules="tpm luks"
grub-install --target=x86_64-efi --modules="tpm luks" --removable
grub-mkconfig -o /boot/grub/grub.cfg

passwd -d root
passwd -l root

systemctl enable lightdm
systemctl enable fail2ban

EOT

echo ""
echo "Stage 2 finished"