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

    # LXC 和 Docker 集成部分
    if [ "${ENABLE_LXC}" = "true" ]; then
        echo "[+] Enabling LXC integration"
        # 添加 LXC 集成相关命令，例如修改内核配置、应用补丁等
        echo "CONFIG_LXC=y" >> .config
        echo "CONFIG_CGROUPS=y" >> .config
        echo "CONFIG_MEMCG=y" >> .config
        make olddefconfig
        # 应用其他必要的补丁或配置
        # 例如，您可以调用其他脚本或命令来应用特定的 LXC 补丁
        # echo "[+] Applying LXC patches"
        # patch -p1 < /path/to/lxc-patch.patch
    fi

    if [ "${ENABLE_DOCKER}" = "true" ]; then
        echo "[+] Enabling Docker integration"
        # 添加 Docker 集成相关命令，例如修改内核配置、应用补丁等
        echo "CONFIG_DOCKER=y" >> .config
        make olddefconfig
        # 应用其他必要的补丁或配置
        # echo "[+] Applying Docker patches"
        # patch -p1 < /path/to/docker-patch.patch
    fi

    # 如果启用了 LXC 和 Docker，需要重新编译配置
    if [ "${ENABLE_LXC}" = "true" ] || [ "${ENABLE_DOCKER}" = "true" ]; then
        echo "[+] Recompiling kernel configuration after enabling LXC/Docker"
        make olddefconfig
    fi

    echo "[+] Building Image.gz"
    $GZIP -n -k -f -9 Image >Image.gz

    echo "[+] Building boot.img"
    $MKBOOTIMG --header_version 4 --kernel Image --output boot.img --ramdisk out/ramdisk --os_version 12.0.0 --os_patch_level "${PATCH_LEVEL}"
    $AVBTOOL add_hash_footer --partition_name boot --partition_size $((64 * 1024 * 1024)) --image boot.img --algorithm SHA256_RSA2048 --key ../kernel-build-tools/linux-x86/share/avb/testkey_rsa2048.pem

    echo "[+] Building boot-gz.img"
    $MKBOOTIMG --header_version 4 --kernel Image.gz --output boot-gz.img --ramdisk out/ramdisk --os_version 12.0.0 --os_patch_level "${PATCH_LEVEL}"
    $AVBTOOL add_hash_footer --partition_name boot --partition_size $((64 * 1024 * 1024)) --image boot-gz.img --algorithm SHA256_RSA2048 --key ../kernel-build-tools/linux-x86/share/avb/testkey_rsa2048.pem

    echo "[+] Building boot-lz4.img"
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
