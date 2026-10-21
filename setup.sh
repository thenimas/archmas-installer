#!/bin/bash

if [[ $EUID -ne 0 ]]; then
   echo "ERROR: This script must be run as root!"
   exit 1
fi

## STAGE 1

echo "Verifying required packages..."
pacman -Sy
pacman -S --noconfirm --needed util-linux bc rsync btrfs-progs tar wget lshw smartmontools cryptsetup arch-install-scripts dosfstools jq

clear

echo "Welcome to the Archmas installer!"
echo "Please select an installation option:"
echo " "

MODE="$1"
if [[ "$MODE" == "--iso" ]]; then
    echo "1. Install Arch Linux to disk formatted with LUKS encryption (recommended)"
    echo "2. Install Arch Linux without encryption"
else
    echo "1. Install Arch Linux to disk formatted with LUKS encryption (recommended)"
    echo "2. Install Arch Linux without encryption"
    echo "3. Manual install to /target (advanced)"
fi


echo " "

INSTALL_TYPE="0"

CRYPT_UUID=""
ROOT_UUID=""
CRYPT_NAME=""
crypttab_entry=""

CHASSIS="$(hostnamectl chassis)"
IS_LAPTOP=0
if [[ "$CHASSIS" == "laptop" || "$CHASSIS" == "tablet" ]]; then
    IS_LAPTOP=1
fi

BOOT_TYPE="BIOS"
if [ -d /sys/firmware/efi ]; then
    BOOT_TYPE="UEFI"
fi

if [[ "$MODE" == "--iso" ]]; then
    until [ "$INSTALL_TYPE" -ge 1 ] && [ "$INSTALL_TYPE" -le 2 ]; do
        read -p "(1,2): " INSTALL_TYPE
    done
else
    until [ "$INSTALL_TYPE" -ge 1 ] && [ "$INSTALL_TYPE" -le 3 ]; do
        read -p "(1,2,3): " INSTALL_TYPE
    done
fi

clear

read -p "Enter new username: " USER_NAME
echo " "

read -p "Enter new name for your PC (hostname): " HOST_NAME

clear

encryptPass=""

if [ "$INSTALL_TYPE" == 1 ]; then
    echo "WARNING: If you lose this password, there is 100% NO way to recover it and you will lose access to all of your data."
    echo " "
    while true; do
        read -s -p "Please enter encryption passphrase: " encryptPass
        echo
        read -s -p "Confirm passphrase: " encryptPass2
        echo
        [ "$encryptPass" = "$encryptPass2" ] && break
        echo "Passphrases do not match"
    done
    echo " "
fi 

DESKTOP_TYPE="-1"
until [ "$DESKTOP_TYPE" -ge 1 ] && [ "$DESKTOP_TYPE" -le 7 ]; do
    DESKTOP_TYPE="-1"
    clear
    echo "Select desktop type:"
    echo " "

    echo "1. Headless (no desktop)"
    echo "2. i3"
    echo "3. KDE Plasma"
    echo "4. Cinnamon"
    echo "5. GNOME"
    echo "6. MATE"
    echo "7. LXQT"

    echo " "
    read -p "(1-7): " DESKTOP_TYPE
done

if [ "$INSTALL_TYPE" == 3 ]; then
    if ! cat /proc/mounts | grep -q "/target " ; then
        echo "ERROR: /target not mounted!"
        exit 1
    fi
else
     availableDisks="$(lsblk -d | grep disk | cut -d' ' -f1)"

    confirm=" "
    installDisk="x"
    
    until [ "$confirm" == "YES" ]; do
        clear

        echo "Disks available to install to:"
        lsblk -d | grep disk | awk '{print $1" "$4}'

        echo " "

        installDisk="x"
        until echo "$availableDisks" | grep -q "$installDisk" && [ -b /dev/$installDisk ] ; do
            read -p "Please type a selection from this list to install to: " installDisk
            installDisk="${installDisk// /}"
        done

        clear

        echo "Selected disk /dev/${installDisk}"

        echo " "

        diskinfo="$(smartctl -a /dev/${installDisk})"

        echo "$diskinfo" | grep Model
        echo "$diskinfo" | grep Capacity
        echo "$diskinfo" | grep Rotation
        echo "$diskinfo" | grep "Version is:"
        echo "$diskinfo" | grep "Version:"
        echo "$diskinfo" | grep overall-health
        echo " "

        echo "REALLY INSTALL TO THIS DISK? THIS WILL OVERWRITE ALL DATA."
        
        read -p "Type YES in all capital letters to continue: " confirm
        echo " "
    done

    # if [ "$INSTALL_TYPE" == 1 ]; then
    #     echo "Would you like to write random data to disk? This will improve encryption strength, but may take time depending on disk speed. If you have done this step before repeating it is likely unecessary."
    #     echo " "
    #     willWriteRandom=" "
    #     until [ "$willWriteRandom" == "Y" ] || [ "$willWriteRandom" == "N" ]; do
    #         read -p "(Y,N): " willWriteRandom
    #     done
    # fi

    IS_HDD="$(cat /sys/block/$installDisk/queue/rotational)"

    echo "Beginning installation..."

    dd if=/dev/zero of=/dev/$installDisk bs=4M count=1

    EFI_PART=""
    BOOT_PART=""
    ROOT_PART=""

    if [ "$BOOT_TYPE" == "UEFI" ]; then

        fdisk /dev/$installDisk <<EEOF
g
n


+128M
t
1
n


+1G
t
2
142
n



t
3
23
w
EEOF

        sleep 0.5

        EFI_PART="$(lsblk -J "/dev/$installDisk" | jq -r --argjson part "0" '.blockdevices[0].children[$part].name')"
        BOOT_PART="$(lsblk -J "/dev/$installDisk" | jq -r --argjson part "1" '.blockdevices[0].children[$part].name')"
        ROOT_PART="$(lsblk -J "/dev/$installDisk" | jq -r --argjson part "2" '.blockdevices[0].children[$part].name')"

        dd if=/dev/zero of=/dev/$EFI_PART bs=4M count=1

        sleep 0.5
        mkfs.vfat -F 32 /dev/$EFI_PART
    else

        fdisk /dev/$installDisk <<EEOF
o
n
p


+1G
n
p



w
EEOF

    BOOT_PART="$(lsblk -J "/dev/$installDisk" | jq -r --argjson part "0" '.blockdevices[0].children[$part].name')"
    ROOT_PART="$(lsblk -J "/dev/$installDisk" | jq -r --argjson part "1" '.blockdevices[0].children[$part].name')"

    fi

    dd if=/dev/zero of=/dev/$BOOT_PART bs=4M count=1
    dd if=/dev/zero of=/dev/$ROOT_PART bs=4M count=1

    sleep 0.5

    mkfs.ext4 /dev/$BOOT_PART
    

    CRYPT_UUID=""
    ROOT_UUID=""

    if [ "$INSTALL_TYPE" == 1 ]; then
        cryptsetup luksFormat -q --verify-passphrase --type luks2 /dev/$ROOT_PART <<EEOF
$encryptPass
$encryptPass
EEOF

        echo $encryptPass | cryptsetup open /dev/$ROOT_PART "$ROOT_PART"_crypt

        CRYPT_NAME="$ROOT_PART"_crypt;
        CRYPT_UUID="$(lsblk -no UUID /dev/$ROOT_PART)"

        dd if=/dev/zero of=/dev/mapper/"$ROOT_PART"_crypt bs=4M status=progress

        mkfs.btrfs /dev/mapper/"$ROOT_PART"_crypt;
        sleep 0.5
        ROOT_UUID="$(lsblk -no UUID /dev/mapper/"$ROOT_PART"_crypt)"
    else
        mkfs.btrfs /dev/$ROOT_PART
        sleep 0.5
        ROOT_UUID="$(lsblk -no UUID /dev/$ROOT_PART)"
    fi

    sleep 0.5

    EFI_UUID="$(lsblk -no UUID /dev/$EFI_PART)"
    BOOT_UUID="$(lsblk -no UUID /dev/$BOOT_PART)"

    mkdir -p /target
    echo "$ROOT_UUID"
    mount /dev/disk/by-uuid/$ROOT_UUID /target

    btrfs subvol create /target/@
    btrfs subvol create /target/@home
    btrfs subvol create /target/@swap
    umount /target

    if [ "$IS_HDD" == 0 ]; then
        mount /dev/disk/by-uuid/$ROOT_UUID /target -o subvol=/@,space_cache=v2,ssd,compress=zstd:1,discard=async
        mkdir -p /target/home
        mkdir -p /target/etc
        mkdir -p /target/swap
        mount /dev/disk/by-uuid/$ROOT_UUID /target/home -o subvol=/@home,space_cache=v2,ssd,compress=zstd:1,discard=async
        mount /dev/disk/by-uuid/$ROOT_UUID /target/swap -o subvol=/@swap,space_cache=v2,ssd,compress=zstd:1,discard=async

        touch /target/etc/fstab

        echo "UUID=$ROOT_UUID / btrfs subvol=/@,space_cache=v2,ssd,compress=zstd:1,discard=async 0 0" >> /target/etc/fstab
        echo "UUID=$ROOT_UUID /home btrfs subvol=/@home,space_cache=v2,ssd,compress=zstd:1,discard=async 0 0" >> /target/etc/fstab
        echo "UUID=$ROOT_UUID /swap btrfs subvol=/@swap,space_cache=v2,ssd,compress=zstd:1,discard=async 0 0" >> /target/etc/fstab
    else
        mount /dev/disk/by-uuid/$ROOT_UUID /target -o subvol=/@,space_cache=v2,compress=zstd:3,autodefrag
        mkdir -p /target/home
        mkdir -p /target/etc
        mkdir -p /target/swap
        mount /dev/disk/by-uuid/$ROOT_UUID /target/home -o subvol=/@home,space_cache=v2,compress=zstd:3,autodefrag
        mount /dev/disk/by-uuid/$ROOT_UUID /target/swap -o subvol=/@swap,space_cache=v2,compress=zstd:3,autodefrag

        touch /target/etc/fstab

        echo "UUID=$ROOT_UUID / btrfs subvol=/@,space_cache=v2,compress=zstd:3,autodefrag 0 0" >> /target/etc/fstab
        echo "UUID=$ROOT_UUID /home btrfs subvol=/@home,space_cache=v2,compress=zstd:3,autodefrag 0 0" >> /target/etc/fstab
        echo "UUID=$ROOT_UUID /swap btrfs subvol=/@swap,space_cache=v2,compress=zstd:3,autodefrag 0 0" >> /target/etc/fstab
    fi

    echo "" >> /target/etc/fstab

    # setting up swap
    truncate -s 0 /target/swap/swapfile
    chattr +C /target/swap/swapfile
    
    mem="$( grep MemTotal /proc/meminfo | tr -s ' ' | cut -d ' ' -f2 )"
    sw_chunk="$(echo "scale=0 ; sqrt(($mem/1000000) + 1) / 4" | bc)"
    sw_size="$(echo "scale=0 ; $sw_chunk*4 + 4" | bc)"
    sw_size="$(echo "scale=0 ; $sw_size*1024" | bc)"

    dd if=/dev/zero of=/target/swap/swapfile bs=1M count=$sw_size status=progress
    chmod 0600 /target/swap/swapfile
    btrfs balance start -v -dconvert=single /target/swap 
    mkswap /target/swap/swapfile
    swapon /target/swap/swapfile

    echo "tmpfs /tmp tmpfs rw,nodev,nosuid,size=2G 0 0" >> /target/etc/fstab
    echo "tmpfs /var/tmp tmpfs rw,nodev,nosuid,size=2G 0 0" >> /target/etc/fstab

    echo "" >> /target/etc/fstab

    echo "/swap/swapfile none swap nofail,pri=0 0 0" >> /target/etc/fstab

    mkdir -p /target/boot

    sleep 0.5

    mount /dev/disk/by-uuid/$BOOT_UUID /target/boot
    if [ "$BOOT_TYPE" == "UEFI" ]; then
        mkdir -p /target/boot/efi

        sleep 0.5
        mount /dev/disk/by-uuid/$EFI_UUID /target/boot/efi
    fi

    echo "" >> /target/etc/fstab
    echo "UUID=$BOOT_UUID /boot ext4 nofail 0 2" >> /target/etc/fstab
    if [ "$BOOT_TYPE" == "UEFI" ]; then
        echo "UUID=$EFI_UUID /boot/efi vfat nofail 0 1" >> /target/etc/fstab
    fi

    if [ "$INSTALL_TYPE" == 1 ]; then
        touch /target/etc/crypttab
        crypttab_entry="$CRYPT_NAME UUID=$CRYPT_UUID none luks"
        if [ "$IS_HDD" == 0 ]; then
            crypttab_entry="$CRYPT_NAME UUID=$CRYPT_UUID none luks,discard"
        fi
    fi

    mkdir -p /target/boot
fi

## STAGE 2

mkdir -p /target/etc/default
touch /target/etc/default/keyboard

echo "KEYMAP=us" > /target/etc/vconsole.conf

pacstrap -K /target base linux-lts linux-firmware sudo nano btrfs-progs wget dbus zstd rsync mkinitcpio

PKGLIST="accountsservice base-devel bc dosfstools fail2ban fastfetch flatpak gdb git grub linux lshw man-db ufw cryptsetup timeshift ntp lynis rkhunter avahi linux-headers linux-lts-headers"

if [ "$DESKTOP_TYPE" != 1 ]; then
    PKGLIST="${PKGLIST} gamemode jdk-openjdk pipewire pipewire-alsa pipewire-audio pipewire-jack pipewire-pulse plymouth redshift python syncthing vlc virt-manager wget dnsmasq github-cli qemu-desktop noto-fonts noto-fonts-cjk noto-fonts-emoji noto-fonts-extra"
fi
if [ "$DESKTOP_TYPE" == 2 ]; then
    PKGLIST="${PKGLIST} ark bluez cantarell-fonts dex dmenu gnome-software gnome-themes-extra gvfs i3-wm i3blocks i3lock i3status ibus kate lightdm lightdm-gtk-greeter lxappearance lxinput maim network-manager-applet nodejs pavucontrol playerctl rxvt-unicode sox systemsettings thunar thunar-archive-plugin thunar-media-tags-plugin thunar-shares-plugin ttf-inconsolata ttf-liberation xclip xdg-desktop-portal xdotool xwallpaper geeqie ffmpegthumbnailer system-config-printer tumbler ffmpegthumbnailer lxqt-policykit"
fi
if [ "$DESKTOP_TYPE" == 3 ]; then
    PKGLIST="${PKGLIST} plasma"
fi
if [ "$DESKTOP_TYPE" == 4 ]; then
    PKGLIST="${PKGLIST} cinnamon"
fi
if [ "$DESKTOP_TYPE" == 5 ]; then
    PKGLIST="${PKGLIST} gnome"
fi
if [ "$DESKTOP_TYPE" == 6 ]; then
    PKGLIST="${PKGLIST} mate"
fi
if [ "$DESKTOP_TYPE" == 7 ]; then
    PKGLIST="${PKGLIST} lxqt oxygen-icons"
fi

wget https://github.com/thenimas/archmas-installer/raw/chooser-bios/configs/keyboard -O /target/etc/default/keyboard
wget https://github.com/thenimas/archmas-installer/raw/chooser-bios/configs/mirrorlist -O /target/etc/pacman.d/mirrorlist
wget https://github.com/thenimas/archmas-installer/raw/chooser-bios/configs/locale.conf -O /target/etc/locale.conf
wget https://github.com/thenimas/archmas-installer/raw/chooser-bios/configs/grub -O /target/etc/default/grub

arch-chroot /target /bin/bash << EOT

sleep 0.5

mount -a

# adding data we specified
ln -sf /usr/share/zoneinfo/Canada/Eastern /etc/localtime
echo "$HOST_NAME" > /etc/hostname
hwclock --systohc

# adding locale
echo "en_CA.UTF-8 UTF-8" >> /etc/locale.gen
echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen

export LC_CTYPE=en_CA.UTF-8
export LC_ALL=en_CA.UTF-8

mkdir -p /boot/grub
wget https://raw.githubusercontent.com/thenimas/archmas-installer/chooser-bios/assets/grub-full.png -O /boot/grub/grub-full.png
wget https://raw.githubusercontent.com/thenimas/archmas-installer/chooser-bios/assets/grub-wide.png -O /boot/grub/grub-wide.png

pacman -Syu --noconfirm

pacman -S --noconfirm --needed $PKGLIST

wget https://github.com/thenimas/archmas-installer/raw/chooser-bios/configs/timeshift.json -O /etc/timeshift/timeshift.json
wget https://github.com/thenimas/archmas-installer/raw/chooser-bios/configs/jail.local -O /etc/fail2ban/jail.local



echo "%wheel      ALL=(ALL:ALL) ALL" >> /etc/sudoers

sed -i 's/HOOKS=(.*)/HOOKS=(base systemd autodetect microcode modconf kms keyboard keymap sd-vconsole block filesystems fsck keymap sd-encrypt plymouth)/g' /etc/mkinitcpio.conf

mkinitcpio -P

# setup grub

if [ "$BOOT_TYPE" == "BIOS" ]; then
    grub-install --target=i386-pc --modules="luks" /dev/"$installDisk"
else
    pacman -S --noconfirm efibootmgr
    grub-install --target=x86_64-efi --modules="tpm luks"
    grub-install --target=x86_64-efi --modules="tpm luks" --removable
fi

grub-mkconfig -o /boot/grub/grub.cfg

passwd -d root
passwd -l root

systemctl enable lightdm
systemctl enable fail2ban
systemctl enable NetworkManager
systemctl enable cronie
systemctl enable ufw
systemctl enable ntpd
systemctl enable avahi-daemon

# add firewall rules
ufw default deny incoming
ufw default allow outgoing
ufw allow 80
ufw allow 443
ufw allow syncthing
ufw enable

chattr +C /var/lib/libvirt/images
sudo systemctl enable libvirtd.service
sudo systemctl enable libvirtd.socket
virsh net-autostart default

rkhunter --propupd

EOT


sed -i 's/ROOT_UUID/${ROOT_UUID}/g' /target/etc/timeshift/timeshift.json

sed -i 's/CRYPT_UUID/${CRYPT_UUID}/g' /target/etc/timeshift/timeshift.json

if [ "$INSTALL_TYPE" == 1 ]; then
    crypttab_entry="$CRYPT_NAME UUID=$CRYPT_UUID none luks"
    if [ "$IS_HDD" == 0 ]; then
        crypttab_entry="$CRYPT_NAME UUID=$CRYPT_UUID none luks,discard"
    fi

    echo "# <target name> <source device> <key file> <options>" > /target/etc/crypttab
    echo "$crypttab_entry" | tr -d '\n'  >> /target/etc/crypttab
    echo "" >> /target/etc/crypttab

    sed -i 's/quiet splash/quiet splash rd.luks.name=${CRYPT_UUID}=${CRYPT_NAME}/g' /target/etc/default/grub

    arch-chroot /target /bin/bash << EOT
grub-mkconfig -o /boot/grub/grub.cfg
mkinitcpio -P
EOT
fi

## STAGE 3

arch-chroot /target /bin/bash << EOT
# make user
useradd -m -s /bin/bash "$USER_NAME"
usermod -aG wheel "$USER_NAME"
usermod -aG libvirt "$USER_NAME"

if [ "$DESKTOP_TYPE" == 2 ]; then

    wget https://github.com/thenimas/archmas-installer/raw/chooser-bios/user.tar -O user.tar
    tar -xf user.tar
    rsync -a ./user/* /home/"$USER_NAME"/
    rsync -a ./user/.* /home/"$USER_NAME"/
    rm -r user
    rm user.tar

    runuser "$USER_NAME" -c 'xdg-mime default thunar.desktop inode/directory application/x-gnome-saved-search'
fi

passwd -d "$USER_NAME"
passwd -e "$USER_NAME"

cd /home/"$USER_NAME"/

if [ "$DESKTOP_TYPE" != 1 ]; then
    runuser "$USER_NAME" -c 'flatpak remote-add --user --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo'
    # runuser "$USER_NAME" -c 'flatpak install --user net.waterfox.waterfox -y'

    runuser "$USER_NAME" -c 'systemctl --user enable syncthing'
    runuser "$USER_NAME" -c 'systemctl --user enable redshift-gtk'
fi

git clone https://aur.archlinux.org/yay-bin.git

chown "$USER_NAME":"$USER_NAME" /home/"$USER_NAME" -R

cd yay-bin
runuser "$USER_NAME" -c 'makepkg' 
pacman -U --noconfirm /home/"$USER_NAME"/yay-bin/*.pkg.tar.zst
EOT

arch-chroot /target /bin/bash << EOT
echo "$USER_NAME ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

cd /home/"$USER_NAME"/yay-bin

runuser "$USER_NAME" -c 'yay -Y --gendb'

if [ "$DESKTOP_TYPE" != 1 ]; then
    runuser "$USER_NAME" -c 'yay -S --noconfirm qdirstat vscodium-bin'
fi

if [ "$DESKTOP_TYPE" == 2 ]; then
    runuser "$USER_NAME" -c 'yay -S --noconfirm gnome-icon-theme xcursor-breeze'
fi

rm -r /home/"$USER_NAME"/yay-bin/
EOT

arch-chroot /target /bin/bash << EOT
runuser "$USER_NAME" -c 'yes | yay -Scc'
EOT

if [ "$IS_LAPTOP" == 1 ]; then
    sed -i 's/# bindsym XF86MonBrightness/bindsym XF86MonBrightness/g' /target/home/"$USER_NAME"/.config/i3/config
    sed -i 's/# order += "battery all"/order += "battery all"/g' /target/home/"$USER_NAME"/.config/i3/i3status.conf

    arch-chroot /target /bin/bash << EOT
pacman -S --noconfirm bluez bluez-utils iw powertop wpa_supplicant brightnessctl
EOT

#     arch-chroot /target /bin/bash << EOT
# runuser "$USER_NAME" -c 'yay -S --noconfirm batsignal'
# runuser "$USER_NAME" -c 'systemctl --user enable batsignal'
# EOT
fi

arch-chroot /target /bin/bash << EOT
yes | yay -Ycc
timeshift --check
EOT

sed -i '/NOPASSWD/d' /target/etc/sudoers

echo ""
echo "Installation complete! Your system is ready to reboot."
exit 0
