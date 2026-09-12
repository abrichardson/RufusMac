FROM debian:bookworm-slim
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    qemu-system-x86 ovmf xorriso mtools dosfstools python3 squashfs-tools pci.ids \
    && rm -rf /var/lib/apt/lists/*
