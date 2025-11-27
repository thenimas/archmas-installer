#!/bin/bash

if [[ $EUID -ne 0 ]]; then
   echo "ERROR: This script must be run as root!"
   exit 1
fi

read -p "Enter new username: " USER_NAME
echo " "

arch-chroot /target /bin/bash << EOT
# make user
useradd -m -s /bin/bash "$USER_NAME"
usermod -aG wheel "$USER_NAME"
usermod -aG libvirt "$USER_NAME"

wget https://github.com/thenimas/archmas-installer/raw/dev/user.tar -O user.tar
tar -xf user.tar
rsync -a ./user/* /home/"$USER_NAME"/
rsync -a ./user/.* /home/"$USER_NAME"/
rm -r user
rm user.tar

sed -i 's/USER_NAME/$USER_NAME/g' /home/"$USER_NAME"/.config/nitrogen/nitrogen.cfg
sed -i 's/USER_NAME/$USER_NAME/g' /home/"$USER_NAME"/.config/nitrogen/bg-saved.cfg

passwd -d "$USER_NAME"
passwd -e "$USER_NAME"

cd /home/"$USER_NAME"/

git clone https://aur.archlinux.org/yay-bin.git

chown "$USER_NAME":"$USER_NAME" /home/"$USER_NAME" -R

cd yay-bin
runuser "$USER_NAME" -c 'makepkg' 
pacman -U /home/"$USER_NAME"/yay-bin/*.pkg.tar.zst
EOT

arch-chroot /target /bin/bash << EOT
echo "$USER_NAME ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

cd /home/"$USER_NAME"/yay-bin

runuser "$USER_NAME" -c 'yes | yay -Y --gendb'
runuser "$USER_NAME" -c 'yes | yay -S --noconfirm gnome-icon-theme qdirstat-bin ttf-comic-neue ttf-courier-prime ttf-league-spartan ttf-symbola vscodium-bin xcursor-breeze'

rm -r /home/"$USER_NAME"/yay-bin/
sed -i '/NOPASSWD/d' /etc/sudoers
EOT

arch-chroot /target /bin/bash << EOT
runuser "$USER_NAME" -c 'yes | yay -Scc'
EOT