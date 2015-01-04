#!/bin/bash

# Automated arch install script

# TODO make constant variables optionally interactive?
DEV=/dev/sda
hooks='base udev encrypt btrfs modconf block net keyboard fsck filesystems usr'
hostname='gorilla'

partition_drive () {
    
    # small boot partition and rest is encrypted btrfs
    
    echo "Partitioning Device"
    
    parted --script --align optimal -- $DEV mklabel gpt
    echo "Made GPT Partition Table"
    
    parted --script --align optimal -- $DEV mkpart primary ext2 1% 2% 
    echo "Made boot partition"
    
    parted --script --align optimal -- $DEV mkpart primary ext4 2% 99%
    echo "Made root partition"
    
    parted --script toggle 1 boot
    echo "Set boot bootable"
    
    make_filesystems
}

make_filesystems () {

    mkfs.ext2 /dev/sda1
    echo "Created filesystem on /boot"

    cryptsetup --cipher aes-xts-plain64 --hash sha512 --use-random --verify-passphrase luksFormat /dev/sda2
    echo "Created encrypted partition"

    cryptsetup luksOpen /dev/sda2 root
    echo "Opened encrypted partition"

    mkfs.btrfs /dev/mapper/root
    echo "Made root filesystem"

    mount /dev/mapper/root /mnt
    echo "Mounted root"

    cd /mnt
    btrfs subvolume create __active
    btrfs subvolume create __active/rootvol
    btrfs subvolume create __active/home
    btrfs subvolume create __active/var
    btrfs subvolume create __snapshots
    echo "Created btrfs subvolumes"

    cd
    umount /mnt
    mount -o subvol=__active/rootvol /dev/mapper/root /mnt
    mkdir /mnt/{home,var}
    mount -o subvol=__active/home /dev/mapper/root /mnt/home
    mount -o subvol=__active/var /dev/mapper/root /mnt/var
    echo "Mounted subvolumes"

    mkdir /mnt/boot
    mount /dev/sda1 /mnt/boot
    echo "Mounted /boot"

    install_arch
}

install_arch () {
    
    # Installs arch linux to drive

    pacstrap /mnt base base-devel btrfs-progs
    echo "Arch installed"

    genfstab -p /mnt >> /mnt/etc/fstab

    arch-chroot /mnt /bin/bash <<EOF
    echo "In chroot"

    sed -i '/^HOOKS="/ c\HOOKS="'"$hooks"'"' /etc/mkinitcpio.conf

    echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
    locale-gen

    echo LANG=en_US.UTF-8 > /etc/locale.conf
    export LANG=en_US.UTF-8

    ln -s /usr/share/zoneinfo/America/New_York /etc/localtime

    hwclock --systohc --utc

    echo $hostname > /etc/hostname
    systemctl enable dhcpcd@enp0s7.service

    mkinitcpio -p linux

    pacman -S syslinux gptfdisk

    syslinux-install_update -iam
    nano /boot/syslinux/syslinux.cfg

    EOF

    umount /mnt/{home,var,boot}
    umount /mnt

    reboot
}

main () {
    partition_drive
    make_filesystems
    install_arch
}
