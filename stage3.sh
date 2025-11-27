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

chown "$USER_NAME":"$USER_NAME" /home/"$USER_NAME" -R

passwd -d "$USER_NAME"
passwd -e "$USER_NAME"

cd /home/"$USER_NAME"/

runuser -u "$USER_NAME" git clone https://aur.archlinux.org/yay-bin.git; cd yay-bin; makepkg -si
runuser -u "$USER_NAME" yay -Y --gendb
runuser -u "$USER_NAME" yes | lang=C yay -S gnome-icon-theme nitrogen qdirstat-bin ttf-comic-neue ttf-courier-prime 1.203-5 ttf-league-spartan ttf-symbola vscodium-bin xcursor-breeze

cd /
rm -rf /home/"$USER_NAME"/yay/

EOT