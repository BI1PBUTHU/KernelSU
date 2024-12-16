name: Build Kernel with Docker and LXC Integration - Android 12

on:
  push:
    branches: ["main", "ci", "checkci"]
    paths:
      - ".github/workflows/build-kernel-a12-with-docker-lxc.yml"
      - ".github/workflows/gki-kernel-with-lxc.yml"
      - ".github/scripts/build_a12-with-lxc.sh"
      - "kernel/**"
  pull_request:
    branches: ["main"]
    paths:
      - ".github/workflows/build-kernel-a12-with-docker-lxc.yml"
      - ".github/workflows/gki-kernel-with-lxc.yml"
      - ".github/scripts/build_a12-with-lxc.sh"
      - "kernel/**"
  workflow_call:

jobs:
  build-kernel-with-docker-lxc:
    # 定义矩阵策略
    strategy:
      matrix:
        sub_level: [198, 205, 209, 218]
        os_patch_level: [2024-01, 2024-03, 2024-05, 2024-08]

    # 调用可复用工作流
    uses: ./.github/workflows/gki-kernel-with-lxc.yml

    # 传递输入参数
    with:
      version: android12-5.10
      version_name: "android12-5.10.${{ matrix.sub_level }}"
      tag: "android12-5.10-${{ matrix.os_patch_level }}"
      os_patch_level: "${{ matrix.os_patch_level }}"
      patch_path: "5.10"
      ENABLE_LXC: true
      ENABLE_DOCKER: true
      # 其他需要传递给 gki-kernel-with-lxc.yml 的参数

    # 传递密钥
    secrets:
      BOOT_SIGN_KEY: ${{ secrets.BOOT_SIGN_KEY }}
      CHAT_ID: ${{ secrets.CHAT_ID }}
      BOT_TOKEN: ${{ secrets.BOT_TOKEN }}
      MESSAGE_THREAD_ID: ${{ secrets.MESSAGE_THREAD_ID }}

    # 定义环境变量
    env:
      ENABLE_LXC: true
      ENABLE_DOCKER: true
      # 其他全局环境变量

  upload-artifacts:
    needs: build-kernel-with-docker-lxc
    runs-on: ubuntu-latest
    if: >
      ( github.event_name != 'pull_request' && github.ref == 'refs/heads/main' )
      || github.ref_type == 'tag'
      || github.ref == 'refs/heads/ci'
    env:
      CHAT_ID: ${{ secrets.CHAT_ID }}
      BOT_TOKEN: ${{ secrets.BOT_TOKEN }}
      MESSAGE_THREAD_ID: ${{ secrets.MESSAGE_THREAD_ID }}
      COMMIT_MESSAGE: ${{ github.event.head_commit.message }}
      COMMIT_URL: ${{ github.event.head_commit.url }}
      RUN_URL: ${{ github.server_url }}/${{ github.repository }}/actions/runs/${{ github.run_id }}
    steps:
      - name: Download artifacts
        uses: actions/download-artifact@v4

      - uses: actions/checkout@v4
        with:
          path: KernelSU
          fetch-depth: 0

      - name: List artifacts
        run: |
          tree

      - name: Download prebuilt toolchain
        run: |
          AOSP_MIRROR=https://android.googlesource.com
          BRANCH=main-kernel-build-2024
          git clone "$AOSP_MIRROR/platform/prebuilts/build-tools" -b "$BRANCH" --depth 1 build-tools
          git clone "$AOSP_MIRROR/kernel/prebuilts/build-tools" -b "$BRANCH" --depth 1 kernel-build-tools
          git clone "$AOSP_MIRROR/platform/system/tools/mkbootimg" -b "$BRANCH" --depth 1
          pip3 install telethon

      - name: Set boot sign key
        env:
          BOOT_SIGN_KEY: ${{ secrets.BOOT_SIGN_KEY }}
        run: |
          if [ -n "$BOOT_SIGN_KEY" ]; then
            echo "$BOOT_SIGN_KEY" > ./kernel-build-tools/linux-x86/share/avb/testkey_rsa2048.pem
          fi

      - name: Bot session cache
        id: bot_session_cache
        uses: actions/cache@v4
        if: false
        with:
          path: scripts/ksubot.session
          key: ${{ runner.os }}-bot-session

      - name: Build boot images
        run: |
          export AVBTOOL="$GITHUB_WORKSPACE/kernel-build-tools/linux-x86/bin/avbtool"
          export GZIP="$GITHUB_WORKSPACE/build-tools/path/linux-x86/gzip"
          export LZ4="$GITHUB_WORKSPACE/build-tools/path/linux-x86/lz4"
          export MKBOOTIMG="$GITHUB_WORKSPACE/mkbootimg/mkbootimg.py"
          export UNPACK_BOOTIMG="$GITHUB_WORKSPACE/mkbootimg/unpack_bootimg.py"
          cd "$GITHUB_WORKSPACE/KernelSU"
          export VERSION=$(( $(git rev-list --count HEAD) + 10200 ))
          echo "VERSION: $VERSION"
          cd -
          bash "$GITHUB_WORKSPACE/KernelSU/.github/scripts/build_a12-with-lxc.sh"

      - name: Display structure of boot files
        run: ls -R

      - name: Upload images artifact
        uses: actions/upload-artifact@v4
        with:
          name: boot-images-android12
          path: Image-android12*/*.img.gz
