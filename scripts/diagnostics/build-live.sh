#!/bin/bash
set -euo pipefail
cd /build
lb config --mode debian --distribution bookworm --architectures amd64 \
  --binary-images iso-hybrid --archive-areas 'main contrib non-free-firmware' \
  --debian-installer none --apt-recommends false --security true --updates true \
  --cache false --firmware-chroot false --firmware-binary false \
  --bootappend-live 'boot=live components quiet noeject nopersistence hostname=macus-diagnostics' \
  --iso-application 'Macus Diagnostics' --iso-volume 'MACUS_DIAG' \
  --iso-publisher 'SynapsEdge' --memtest none \
  --chroot-squashfs-compression-type xz
mkdir -p config/package-lists config/includes.chroot/opt/macus config/hooks/live
# Automatically enter diagnostics after a short opportunity to choose failsafe.
mkdir -p config/bootloaders/isolinux config/bootloaders/grub-pc
sed 's/timeout 0/timeout 20/' /usr/share/live/build/bootloaders/isolinux/isolinux.cfg > config/bootloaders/isolinux/isolinux.cfg
cat /usr/share/live/build/bootloaders/grub-pc/config.cfg > config/bootloaders/grub-pc/config.cfg
printf '\nset timeout=2\n' >> config/bootloaders/grub-pc/config.cfg
cat > config/package-lists/macus.list.chroot <<'PACKAGES'
linux-image-amd64
live-boot
systemd-sysv
python3
python3-tk
xserver-xorg
xinit
openbox
fonts-dejavu-core
smartmontools
dmidecode
pciutils
pci.ids
usbutils
iproute2
stress-ng
memtester
exfatprogs
ntfs-3g
util-linux
udev
firmware-iwlwifi
firmware-realtek
firmware-atheros
firmware-amd-graphics
firmware-misc-nonfree
firmware-sof-signed
firmware-intel-sound
firmware-linux-free
alsa-utils
PACKAGES
cp /src/Sources/MacusKit/Resources/InventoryToolkit/inventory.py config/includes.chroot/opt/macus/
cp /src/diagnostics/{app.py,storage.py} config/includes.chroot/opt/macus/
mkdir -p config/includes.chroot/etc/systemd/system/multi-user.target.wants
cat > config/includes.chroot/etc/systemd/system/macus-diagnostics.service <<'SERVICE'
[Unit]
Description=Macus Diagnostics
After=systemd-udev-settle.service
Wants=systemd-udev-settle.service
Conflicts=getty@tty1.service
[Service]
Type=simple
ExecStart=/opt/macus/launch.sh
Restart=on-failure
RestartSec=3
StandardInput=tty
TTYPath=/dev/tty1
TTYReset=yes
TTYVHangup=yes
[Install]
WantedBy=multi-user.target
SERVICE
ln -s ../macus-diagnostics.service config/includes.chroot/etc/systemd/system/multi-user.target.wants/macus-diagnostics.service
cat > config/includes.chroot/opt/macus/launch.sh <<'LAUNCH'
#!/bin/sh
if grep -q 'macus.selftest=1' /proc/cmdline; then
    exec >/dev/ttyS0 2>&1
fi
exec /usr/bin/xinit /opt/macus/session.sh -- :0 vt1 -nolisten tcp
LAUNCH
chmod +x config/includes.chroot/opt/macus/launch.sh
cat > config/includes.chroot/opt/macus/session.sh <<'SESSION'
#!/bin/sh
xset s off || true
xset -dpms || true
openbox &
exec python3 /opt/macus/app.py
SESSION
chmod +x config/includes.chroot/opt/macus/session.sh
cat > config/hooks/live/0900-macus.hook.chroot <<'HOOK'
#!/bin/sh
set -eu
# This appliance has no login or network service. Hardware access stays local.
systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target getty@tty1.service
systemctl disable apt-daily.timer apt-daily-upgrade.timer || true
HOOK
chmod +x config/hooks/live/0900-macus.hook.chroot
lb build
cp live-image-amd64.hybrid.iso /out/Macus-Diagnostics-amd64.iso
cp live-image-amd64.packages /out/packages.txt
cd /out
sha256sum Macus-Diagnostics-amd64.iso > Macus-Diagnostics-amd64.iso.sha256
