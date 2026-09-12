FROM debian:bookworm-slim
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    live-build debootstrap ca-certificates xorriso isolinux syslinux-common squashfs-tools \
    grub-pc-bin grub-efi-amd64-bin mtools dosfstools qemu-system-x86 ovmf python3 \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /build
