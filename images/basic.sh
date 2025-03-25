#!/bin/bash
set -x
# shellcheck disable=SC2034,SC2154
IMAGE_NAME="Arch-Linux-x86_64-basic-${build_version}.qcow2"
# It is meant for local usage so the disk should be "big enough".
DISK_SIZE="40G"
PACKAGES=(fio sysstat curl iperf3 open-iscsi curl inetutils)
SERVICES=(myrc)

function pre1() {
  sed -Ei 's/^(GRUB_CMDLINE_LINUX_DEFAULT=.*)"$/\1 transparent_hugepage=never noibrs noibpb nopti nospectre_v2 nospectre_v1 l1tf=off nospec_store_bypass_disable no_stf_barrier mds=off tsx=on tsx_async_abort=off mitigations=off spec_rstack_overflow=off console=tty0 console=ttyS0,115200 ignore_loglevel debug"/' "${MOUNT}/etc/default/grub"
  echo 'GRUB_TERMINAL="serial console"' >>"${MOUNT}/etc/default/grub"
  echo 'GRUB_SERIAL_COMMAND="serial --speed=115200"' >>"${MOUNT}/etc/default/grub"
  arch-chroot "${MOUNT}" /usr/bin/grub-mkconfig -o /boot/grub/grub.cfg

  sed -Ei 's/ExecStart=.*/ExecStart=\/sbin\/agetty --autologin root -8 --keep-baud 115200,38400,9600 %I $TERM/g' "${MOUNT}/usr/lib/systemd/system/serial-getty@.service"
  sed -Ei 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/g' "${MOUNT}/etc/ssh/sshd_config"

  # reduce the size
  rm -rf "${MOUNT}/usr/share/{man,doc,info,locale}"
  echo -e "arch\narch" | arch-chroot "${MOUNT}" /usr/bin/passwd "root"
}

function pre2() {
  cp ${ORIG_PWD}/rc.local "${MOUNT}/usr/bin/myrc.local"
  cat <<EOF >"${MOUNT}/etc/systemd/system/myrc.service"
[Unit]
Description=My Startup Script
After=network.target

[Service]
Type=oneshot
RemainAfterExit=no
ExecStart=/usr/bin/myrc.local
User=root
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

}

function pre() {
  local NEWUSER="arch"
  arch-chroot "${MOUNT}" /usr/bin/useradd -m -U "${NEWUSER}"
  echo -e "${NEWUSER}\n${NEWUSER}" | arch-chroot "${MOUNT}" /usr/bin/passwd "${NEWUSER}"
  echo "${NEWUSER} ALL=(ALL) NOPASSWD: ALL" >"${MOUNT}/etc/sudoers.d/${NEWUSER}"

  cat <<EOF >"${MOUNT}/etc/systemd/network/80-dhcp.network"
[Match]
Name=en*
Name=eth*

[Link]
RequiredForOnline=routable

[Network]
DHCP=yes
EOF
  pre1
  pre2
}

function post() {
  qemu-img convert -c -f raw -O qcow2 "${1}" "${2}"
  rm "${1}"
}
