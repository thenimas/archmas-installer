#!/bin/bash

if [[ $EUID -ne 0 ]]; then
   echo "ERROR: This script must be run as root!"
   exit 1
fi

echo "Verifying required packages..."
pacman -Sy
pacman -S --needed util-linux bc rsync btrfs-progs tar wget lshw smartmontools cryptsetup arch-install-scripts dosfstools jq

echo " "

echo "Welcome to the Archmas installer!"
echo "Please select an installation option:"
echo " "

echo "1. Install Arch to disk formatted with LUKS encryption (recommended)"
echo "2. Install Arch without encryption"
echo "3. Manual install to /target (advanced)"

echo " "

INSTALL_TYPE="0"

CRYPT_NAME=""
crypttab_entry=""

until [ "$INSTALL_TYPE" -ge 1 ] && [ "$INSTALL_TYPE" -le 3 ]; do
    read -p "(1,2,3): " INSTALL_TYPE
done

echo " "

willWriteRandom="N"

if [ "$INSTALL_TYPE" == 1 ]; then
    echo "IMPORTANT WARNING:"
    echo " "
    echo "After the partitioning is complete, you will be prompted to set up an encryption password. If you lose this password, there is 100% NO way to recover it and you will lose access to all of your data."
    echo " "
    confirm=" "
    read -p "Type YES in all capital letters to continue: " confirm
    if [ ! $confirm = "YES" ]; then
        echo "Aborting."
        exit 0
    fi
    echo " "
fi 

if [ "$INSTALL_TYPE" == 3 ]; then
    if ! cat /proc/mounts | grep -q "/target " ; then
        echo "ERROR: /target not mounted!"
        exit 1
    fi
    if ! cat /proc/mounts | grep -q "/target/boot/efi " ; then
        echo "ERROR: /target/boot/efi not mounted!"
        exit 1
    fi
else
    availableDisks="$(lsblk -d | grep disk | cut -d' ' -f1)"

    echo "Disks available to install to:"
    lsblk -d | grep disk | awk '{print $1" "$4}'

    echo " "

    installDisk="x"

    until echo "$availableDisks" | grep -q "$installDisk" && [ -b /dev/$installDisk ] ; do
        read -p "Please type a selection from this list to install to: " installDisk
        installDisk="${installDisk// /}"
    done

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
    confirm=" "
    read -p "Type YES in all capital letters to continue: " confirm
    echo " "

    if [ ! $confirm = "YES" ]; then
        echo "Aborting."
        exit 0
    fi

    if [ "$INSTALL_TYPE" == 1 ]; then
        echo "Would you like to write random data to disk? This will improve encryption strength, but may take time depending on disk speed. If you have done this step before repeating it is likely unecessary."
        echo " "
        willWriteRandom=" "
        until [ "$willWriteRandom" == "Y" ] || [ "$willWriteRandom" == "N" ]; do
            read -p "(Y,N): " willWriteRandom
        done
    fi

    IS_HDD="$(cat /sys/block/$installDisk/queue/rotational)"

    echo "Beginning installation..."

    if [ "$willWriteRandom" == "Y" ]; then
        dd if=/dev/urandom of=/dev/$installDisk bs=4M status=progress
    else
        dd if=/dev/zero of=/dev/$installDisk bs=4M count=1
    fi

    fdisk /dev/$installDisk <<EEOF
g
n


+128M
t
1
n


+1G
n



w
EEOF

    sleep 0.5

    EFI_PART="$(lsblk -J "/dev/$installDisk" | jq -r --argjson part "0" '.blockdevices[0].children[$part].name')"
    BOOT_PART="$(lsblk -J "/dev/$installDisk" | jq -r --argjson part "1" '.blockdevices[0].children[$part].name')"
    ROOT_PART="$(lsblk -J "/dev/$installDisk" | jq -r --argjson part "2" '.blockdevices[0].children[$part].name')"

    dd if=/dev/zero of=/dev/$EFI_PART bs=4M count=1
    dd if=/dev/zero of=/dev/$BOOT_PART bs=4M count=1
    dd if=/dev/zero of=/dev/$ROOT_PART bs=4M count=1

    sleep 0.5

    mkfs.vfat -F 32 /dev/$EFI_PART
    mkfs.ext4 /dev/$BOOT_PART
    

    CRYPT_UUID=""
    ROOT_UUID=""

    if [ "$INSTALL_TYPE" == 1 ]; then
        until cryptsetup luksFormat -q --verify-passphrase --type luks2 /dev/$ROOT_PART; do
            echo "Try again"
        done
        until cryptsetup open /dev/$ROOT_PART "$ROOT_PART"_crypt; do
            echo "Try again"
        done

        CRYPT_NAME="$ROOT_PART"_crypt;
        CRYPT_UUID="$(lsblk -no UUID /dev/$ROOT_PART)"
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
    btrfs subvol create /target/@var-log
    btrfs subvol create /target/@swap
    umount /target

    if [ "$IS_HDD" == 0 ]; then
        mount /dev/disk/by-uuid/$ROOT_UUID /target -o subvol=/@,space_cache=v2,ssd,compress=zstd:1,discard=async
        mkdir -p /target/home
        mkdir -p /target/var/log
        mkdir -p /target/etc
        mkdir -p /target/swap
        mount /dev/disk/by-uuid/$ROOT_UUID /target/home -o subvol=/@home,space_cache=v2,ssd,compress=zstd:1,discard=async
        mount /dev/disk/by-uuid/$ROOT_UUID /target/var/log -o subvol=/@var-log,space_cache=v2,ssd,compress=zstd:1,discard=async
        mount /dev/disk/by-uuid/$ROOT_UUID /target/swap -o subvol=/@swap,space_cache=v2,ssd,compress=zstd:1,discard=async

        touch /target/etc/fstab

        echo "UUID=$ROOT_UUID / btrfs subvol=/@,space_cache=v2,ssd,compress=zstd:1,discard=async 0 0" >> /target/etc/fstab
        echo "UUID=$ROOT_UUID /home btrfs subvol=/@home,space_cache=v2,ssd,compress=zstd:1,discard=async 0 0" >> /target/etc/fstab
        echo "UUID=$ROOT_UUID /var/log btrfs subvol=/@var-log,space_cache=v2,ssd,compress=zstd:1,discard=async 0 0" >> /target/etc/fstab
        echo "UUID=$ROOT_UUID /swap btrfs subvol=/@swap,space_cache=v2,ssd,compress=zstd:1,discard=async 0 0" >> /target/etc/fstab
    else
        mount /dev/disk/by-uuid/$ROOT_UUID /target -o subvol=/@,space_cache=v2,compress=zstd:3,autodefrag
        mkdir -p /target/home
        mkdir -p /target/var/log
        mkdir -p /target/etc
        mkdir -p /target/swap
        mount /dev/disk/by-uuid/$ROOT_UUID /target/home -o subvol=/@home,space_cache=v2,compress=zstd:3,autodefrag
        mount /dev/disk/by-uuid/$ROOT_UUID /target/var/log -o subvol=/@var-log,space_cache=v2,compress=zstd:3,autodefrag
        mount /dev/disk/by-uuid/$ROOT_UUID /target/swap -o subvol=/@swap,space_cache=v2,compress=zstd:3,autodefrag

        touch /target/etc/fstab

        echo "UUID=$ROOT_UUID / btrfs subvol=/@,space_cache=v2,compress=zstd:3,autodefrag 0 0" >> /target/etc/fstab
        echo "UUID=$ROOT_UUID /home btrfs subvol=/@home,space_cache=v2,compress=zstd:3,autodefrag 0 0" >> /target/etc/fstab
        echo "UUID=$ROOT_UUID /var/log btrfs subvol=/@var-log,space_cache=v2,compress=zstd:3,autodefrag 0 0" >> /target/etc/fstab
        echo "UUID=$ROOT_UUID /swap btrfs subvol=/@swap,space_cache=v2,compress=zstd:3,autodefrag 0 0" >> /target/etc/fstab
    fi

    echo "" >> /target/etc/fstab

    # setting up swap
    truncate -s 0 /target/swap/swapfile
    chattr +C /target/swap/swapfile
    
    mem="$( grep MemTotal /proc/meminfo | tr -s ' ' | cut -d ' ' -f2 )"
    sw_chunk="$(echo "scale=0 ; sqrt(($mem/1000000) + 1) / 4" | bc)"
    sw_size="$(echo "scale=0 ; $sw_chunk*4 + 4" | bc)"

    dd if=/dev/zero of=/target/swap/swapfile bs=1G count=$sw_size status=progress
    chmod 0600 /target/swap/swapfile
    btrfs balance start -v -dconvert=single /target/swap 
    mkswap /target/swap/swapfile
    swapon /target/swap/swapfile

    echo "tmpfs /tmp tmpfs rw,nodev,nosuid,size=2G 0 0" >> /target/etc/fstab
    echo "tmpfs /var/tmp tmpfs rw,nodev,nosuid,size=2G 0 0" >> /target/etc/fstab
    echo "tmpfs /var/cache tmpfs rw,nodev,nosuid,size=2G 0 0" >> /target/etc/fstab

    echo "" >> /target/etc/fstab

    echo "/swap/swapfile none swap nofail,pri=0 0 0" >> /target/etc/fstab

    mkdir -p /target/boot

    sleep 0.5

    mount /dev/disk/by-uuid/$BOOT_UUID /target/boot
    mkdir -p /target/boot/efi

    sleep 0.5
    mount /dev/disk/by-uuid/$EFI_UUID /target/boot/efi

    echo "" >> /target/etc/fstab
    echo "UUID=$BOOT_UUID /boot ext4 nofail 0 2" >> /target/etc/fstab
    echo "UUID=$EFI_UUID /boot/efi vfat nofail 0 1" >> /target/etc/fstab

    mkdir -p /target/etc/default
    wget https://github.com/thenimas/archmas-installer/raw/dev/configs/grub -O /target/etc/default/grub

    if [ "$INSTALL_TYPE" == 1 ]; then
        touch /target/etc/crypttab
        crypttab_entry="$CRYPT_NAME UUID=$CRYPT_UUID none luks"
        if [ "$IS_HDD" == 0 ]; then
            crypttab_entry="$CRYPT_NAME UUID=$CRYPT_UUID none luks,discard"
        fi

        echo "# <target name> <source device> <key file> <options>" > /target/etc/crypttab
        echo "$crypttab_entry" | tr -d '\n'  >> /target/etc/crypttab
        echo "" >> /target/etc/crypttab

        sed -i ' s/quiet splash/quiet splash rd.luks.name='"$CRYPT_UUID"'='"$CRYPT_NAME"'' /target/etc/default/grub
    fi

    mkdir -p /target/boot
fi

echo ""
echo "Stage 1 finished"