# Build environment for the msm89xx OpenWrt target - the only place the build
# dependencies are declared. Used by build.sh, locally and in CI; the OpenWrt
# checkout stays on the host and is mounted at /repo.
FROM ubuntu:22.04

LABEL maintainer="msm8916-openwrt"

# Dependencies for OpenWrt and lk2nd/qhypstub compilation: build essentials,
# ARM toolchains, development libraries and utilities.
RUN export DEBIAN_FRONTEND=noninteractive && \
    apt-get update && apt-get install -y --no-install-recommends \
        mkbootimg \
        asciidoc help2man xsltproc \
        bash bc binutils bzip2 make patch time \
        device-tree-compiler \
        e2fsprogs fdisk util-linux \
        flex gawk rsync swig \
        g++ gcc gcc-aarch64-linux-gnu gcc-arm-none-eabi \
        gettext intltool \
        git ccache \
        gzip tar unzip xz-utils zstd zip \
        libelf-dev libfdt-dev libncurses5-dev libssl-dev zlib1g-dev \
        nano sudo \
        perl perl-modules \
        python3-dev python3-setuptools python3-cryptography \
        wget \
    && rm -rf /var/lib/apt/lists/*

# OpenWrt refuses to build as root, so build.sh runs as the host user. uid 1000
# gets a real passwd entry; any other uid still gets a writable HOME.
RUN useradd --create-home --uid 1000 builder && chmod 0777 /home/builder

ENV HOME=/home/builder
WORKDIR /repo

CMD ["bash"]
