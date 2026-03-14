# OnePlus Ace 5 Pro Kernel Build

The community has long struggled with building Android kernels on Apple Silicon and other ARM64 devices. Today, s1lently hopes to change that.

社区长期苦于在 Apple Silicon 等 ARM64 设备上构建安卓内核。今天，s1lently 希望解决这一切。

Build scripts for OnePlus Ace 5 Pro (SM8750) kernel compilation.

## Repositories

| Repo | Description |
|------|-------------|
| [android_kernel_common_oneplus_sm8750](https://github.com/s1lently/android_kernel_common_oneplus_sm8750) | Common kernel (fork from OnePlusOSS) |
| [android_kernel_oneplus_sm8750](https://github.com/s1lently/android_kernel_oneplus_sm8750) | MSM/Qualcomm kernel (fork from OnePlusOSS) |
| [android_kernel_modules_and_devicetree_oneplus_sm8750](https://github.com/s1lently/android_kernel_modules_and_devicetree_oneplus_sm8750) | Device tree & vendor modules (fork from OnePlusOSS) |
| [llvm-project](https://github.com/s1lently/llvm-project) | Clang toolchain (arm64 & x86_64 release binaries) |

## Usage

```bash
git clone https://github.com/s1lently/oneplus_ace5pro_kernel_build
cd oneplus_ace5pro_kernel_build

# Android 16 (OxygenOS 16, kernel 6.6.89)
bash build_android16.sh

# Android 15 (OxygenOS 15, kernel 6.6.66)
bash build_android15.sh
```

Three commands: clone, cd, bash. Everything else is automatic.

## Supported platforms

- **arm64 Linux** (OrbStack, native ARM server) — auto-downloads ARM64 Clang from release
- **x86_64 Linux** (WSL, native) — auto-downloads x86_64 Clang from release

Both platforms are fully automatic — no `repo sync` or AOSP prebuilts needed.

## What the script does

1. Installs build dependencies (apt)
2. Clones 3 kernel source repos from GitHub forks
3. Downloads Clang toolchain (auto-detects platform)
4. Applies defconfig patches
5. Builds kernel Image

## Output

`kernel_workspace/kernel_platform/common/out/arch/arm64/boot/Image`

Flash with:
```bash
# Repack boot.img (needs stock boot_backup.img)
python3 tools/mkbootimg/unpack_bootimg.py \
  --boot_img boot_backup.img --out /tmp/unpack --format mkbootimg
cp kernel_workspace/kernel_platform/common/out/arch/arm64/boot/Image /tmp/unpack/kernel
python3 tools/mkbootimg/mkbootimg.py \
  --header_version 4 --kernel /tmp/unpack/kernel --ramdisk /tmp/unpack/ramdisk -o new_boot.img

# Flash
adb reboot bootloader
fastboot flash boot_b new_boot.img
fastboot reboot
```
