#!/bin/bash
set -euo pipefail

build_from_image() {
    export TITLE
    TITLE=kernel-aarch64-${1//Image-/}
    echo "[+] title: $TITLE"

    export PATCH_LEVEL
    PATCH_LEVEL=$(echo "$1" | awk -F_ '{ print $2}')
    echo "[+] patch level: $PATCH_LEVEL"

    echo '[+] Download prebuilt ramdisk'
    GKI_URL=https://dl.google.com/android/gki/gki-certified-boot-android12-5.10-"${PATCH_LEVEL}"_r1.zip
    FALLBACK_URL=https://dl.google.com/android/gki/gki-certified-boot-android12-5.10-2023-01_r1.zip
    status=$(curl -sL -w "%{http_code}" "$GKI_URL" -o /dev/null)
    if [ "$status" = "200" ]; then
        curl -Lo gki-kernel.zip "$GKI_URL"
    else
        echo "[+] $GKI_URL not found, using $FALLBACK_URL"
        curl -Lo gki-kernel.zip "$FALLBACK_URL"
    fi
    unzip gki-kernel.zip && rm gki-kernel.zip

    echo '[+] Unpack prebuilt boot.img'
    BOOT_IMG=$(find . -maxdepth 1 -name "boot*.img")
    $UNPACK_BOOTIMG --boot_img="$BOOT_IMG"
    rm "$BOOT_IMG"

    echo '[+] Building Image.gz'
    $GZIP -n -k -f -9 Image >Image.gz

    # LXC 和 Docker 集成部分
    if [ "${ENABLE_LXC}" = "true" ]; then
        echo "[+] Enabling LXC integration"
        cd $GITHUB_WORKSPACE/kernel_workspace/android-kernel
        rm -rf utils
        git clone https://github.com/tomxi1997/lxc-docker-support-for-android.git utils
        echo 'source "utils/Kconfig"' >> "Kconfig"

        echo "CONFIG_LXC=y" >> arch/${ARCH}/configs/${KERNEL_CONFIG}
        echo "CONFIG_CGROUPS=y" >> arch/${ARCH}/configs/${KERNEL_CONFIG}
        echo "CONFIG_MEMCG=y" >> arch/${ARCH}/configs/${KERNEL_CONFIG}
        echo "CONFIG_DOCKER=y" >> arch/${ARCH}/configs/${KERNEL_CONFIG}

        sed -i '/CONFIG_ANDROID_PARANOID_NETWORK/d' arch/${ARCH}/configs/${KERNEL_CONFIG}
        echo "# CONFIG_ANDROID_PARANOID_NETWORK is not set" >> arch/${ARCH}/configs/${KERNEL_CONFIG}

        chmod +x utils/runcpatch.sh
        if [ -f kernel/cgroup/cgroup.c ]; then
            sh utils/runcpatch.sh kernel/cgroup/cgroup.c
        fi

        if [ -f kernel/cgroup.c ]; then
            sh utils/runcpatch.sh kernel/cgroup.c
        fi

        if [ -f net/netfilter/xt_qtaguid.c ]; then
            patch -p0 < utils/xt_qtaguid.patch
        fi
    fi

    if [ "${ENABLE_DOCKER}" = "true" ]; then
        echo "[+] Enabling Docker integration"
        # 在此处添加任何与 Docker 相关的额外配置或补丁
        # 例如，应用特定的 Docker 补丁
        # patch -p1 < utils/docker-patch.patch
    fi

    if [ "${ENABLE_LXC}" = "true" ] || [ "${ENABLE_DOCKER}" = "true" ]; then
        echo "[+] Recompiling kernel configuration after enabling LXC/Docker"
        make olddefconfig
    fi

    echo '[+] Building boot.img'
    $MKBOOTIMG --header_version 4 --kernel Image --output boot.img --ramdisk out/ramdisk --os_version 12.0.0 --os_patch_level "${PATCH_LEVEL}"
    $AVBTOOL add_hash_footer --partition_name boot --partition_size $((64 * 1024 * 1024)) --image boot.img --algorithm SHA256_RSA2048 --key ../kernel-build-tools/linux-x86/share/avb/testkey_rsa2048.pem

    echo '[+] Building boot-gz.img'
    $MKBOOTIMG --header_version 4 --kernel Image.gz --output boot-gz.img --ramdisk out/ramdisk --os_version 12.0.0 --os_patch_level "${PATCH_LEVEL}"
    $AVBTOOL add_hash_footer --partition_name boot --partition_size $((64 * 1024 * 1024)) --image boot-gz.img --algorithm SHA256_RSA2048 --key ../kernel-build-tools/linux-x86/share/avb/testkey_rsa2048.pem

    echo '[+] Building boot-lz4.img'
    $MKBOOTIMG --header_version 4 --kernel Image.lz4 --output boot-lz4.img --ramdisk out/ramdisk --os_version 12.0.0 --os_patch_level "${PATCH_LEVEL}"
    $AVBTOOL add_hash_footer --partition_name boot --partition_size $((64 * 1024 * 1024)) --image boot-lz4.img --algorithm SHA256_RSA2048 --key ../kernel-build-tools/linux-x86/share/avb/testkey_rsa2048.pem

    echo '[+] Compress images'
    for image in boot*.img; do
        $GZIP -n -f -9 "$image"
        mv "$image".gz "${1//Image-/}"-"$image".gz
    done

    echo "[+] Images to upload"
    find . -type f -name "*.gz"

    # find . -type f -name "*.gz" -exec python3 "$GITHUB_WORKSPACE"/KernelSU/scripts/ksubot.py {} +
}

for dir in Image*; do
    if [ -d "$dir" ]; then
        echo "----- Building $dir -----"
        cd "$dir"
        build_from_image "$dir"
        cd ..
    fi
done
