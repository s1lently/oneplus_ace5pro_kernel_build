#!/usr/bin/env bash
# build_android16_sukisu_kpm.sh — OnePlus Ace 5 Pro, Android 16, SukiSU + KPM
# Builds kernel with SukiSU-Ultra (SUSFS) and KernelPatch Module support
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/build_common.sh"

BRANCH="oneplus/sm8750_b_16.0.0_oneplus_ace5_pro"

# Match stock UTS_RELEASE suffix (uname -r)
LOCALVERSION="-android15-8-gf4dc45704e54-abogki446052083-4k"

# Match stock compile banner (who/where/when)
export KBUILD_BUILD_USER="kleaf"
export KBUILD_BUILD_HOST="build-host"
export KBUILD_BUILD_TIMESTAMP="Fri Sep 19 06:13:40 UTC 2025"
export KBUILD_BUILD_VERSION="1"

# Optimization flags (matches reference workflow)
EXTRA_KCFLAGS="-O2"

# ── SukiSU + SUSFS + KPM setup ─────────────────────────────
setup_sukisu_kpm() {
    log "=== Setting up SukiSU-Ultra + SUSFS + KPM ==="

    # Ensure kernel sources exist
    mkdir -p "$PLATFORM_DIR"
    clone_if_missing "$COMMON_REPO" "$KERNEL_DIR" "$BRANCH"

    # Remove ABI protected exports (prevents build errors)
    rm -f "$KERNEL_DIR/android/abi_gki_protected_exports_"* || true
    rm -f "$PLATFORM_DIR/msm-kernel/android/abi_gki_protected_exports_"* || true

    # ── SukiSU-Ultra ───────────────────────────────────────
    log "Installing SukiSU-Ultra (susfs-main)..."
    cd "$PLATFORM_DIR"
    curl -LSs "https://raw.githubusercontent.com/SukiSU-Ultra/SukiSU-Ultra/main/kernel/setup.sh" | bash -s susfs-main

    # Get KSU version for naming
    cd "$PLATFORM_DIR/KernelSU"
    KSU_VERSION=$(expr $(/usr/bin/env git rev-list --count HEAD) "+" 10700)
    export KSU_VERSION
    sed -i "s/DKSU_VERSION=12800/DKSU_VERSION=${KSU_VERSION}/" kernel/Makefile
    log "SukiSU version: $KSU_VERSION"

    # ── SUSFS ──────────────────────────────────────────────
    log "Installing SUSFS..."
    cd "$WORKSPACE"
    [[ ! -d susfs4ksu ]] && git clone https://gitlab.com/simonpunk/susfs4ksu.git -b gki-android15-6.6 --depth 1
    [[ ! -d SukiSU_patch ]] && git clone https://github.com/SukiSU-Ultra/SukiSU_patch.git --depth 1

    cd "$PLATFORM_DIR"
    cp ../susfs4ksu/kernel_patches/50_add_susfs_in_gki-android15-6.6.patch ./common/
    cp ../susfs4ksu/kernel_patches/fs/* ./common/fs/
    cp ../susfs4ksu/kernel_patches/include/linux/* ./common/include/linux/

    # lz4k compression support
    cp -r ../SukiSU_patch/other/zram/lz4k/include/linux/* ./common/include/linux
    cp -r ../SukiSU_patch/other/zram/lz4k/lib/* ./common/lib
    cp -r ../SukiSU_patch/other/zram/lz4k/crypto/* ./common/crypto
    cp -r ../SukiSU_patch/other/zram/lz4k_oplus ./common/lib/

    # Apply SUSFS patch
    cd ./common
    sed -i 's/-32,12 +32,38/-32,11 +32,37/g' 50_add_susfs_in_gki-android15-6.6.patch
    sed -i '/#include <trace\/hooks\/fs.h>/d' 50_add_susfs_in_gki-android15-6.6.patch
    patch -p1 < 50_add_susfs_in_gki-android15-6.6.patch || true

    # Apply syscall hooks patch
    cp ../../SukiSU_patch/hooks/syscall_hooks.patch ./
    patch -p1 -F 3 < syscall_hooks.patch || true

    log "SUSFS patched"

    # ── HMBird GKI patch ──────────────────────────────────
    log "Adding HMBird GKI patch..."
    if ! grep -q "hmbird_patch.o" "$KERNEL_DIR/drivers/Makefile"; then
        cat > "$KERNEL_DIR/drivers/hmbird_patch.c" << 'HMBIRD_EOF'
#include <linux/init.h>
#include <linux/module.h>
#include <linux/of.h>
#include <linux/slab.h>
#include <linux/string.h>

static int __init hmbird_patch_init(void)
{
    struct device_node *ver_np;
    const char *type;
    int ret;

    ver_np = of_find_node_by_path("/soc/oplus,hmbird/version_type");
    if (!ver_np) {
        pr_info("hmbird_patch: version_type node not found\n");
        return 0;
    }

    ret = of_property_read_string(ver_np, "type", &type);
    if (ret) {
        pr_info("hmbird_patch: type property not found\n");
        of_node_put(ver_np);
        return 0;
    }

    if (strcmp(type, "HMBIRD_OGKI")) {
        of_node_put(ver_np);
        return 0;
    }

    struct property *prop = of_find_property(ver_np, "type", NULL);
    if (prop) {
        struct property *new_prop = kmalloc(sizeof(*prop), GFP_KERNEL);
        if (!new_prop) {
            of_node_put(ver_np);
            return 0;
        }
        memcpy(new_prop, prop, sizeof(*prop));
        new_prop->value = kmalloc(strlen("HMBIRD_GKI") + 1, GFP_KERNEL);
        if (!new_prop->value) {
            kfree(new_prop);
            of_node_put(ver_np);
            return 0;
        }
        strcpy(new_prop->value, "HMBIRD_GKI");
        new_prop->length = strlen("HMBIRD_GKI") + 1;

        if (of_remove_property(ver_np, prop) != 0) {
            pr_info("hmbird_patch: of_remove_property failed\n");
            of_node_put(ver_np);
            return 0;
        }
        if (of_add_property(ver_np, new_prop) != 0) {
            pr_info("hmbird_patch: of_add_property failed\n");
            of_node_put(ver_np);
            return 0;
        }
        pr_info("hmbird_patch: success from HMBIRD_OGKI to HMBIRD_GKI\n");
    }
    of_node_put(ver_np);
    return 0;
}
early_initcall(hmbird_patch_init);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("Convert HMBIRD_OGKI to HMBIRD_GKI");
HMBIRD_EOF
        echo "obj-y += hmbird_patch.o" >> "$KERNEL_DIR/drivers/Makefile"
        log "HMBird patch added"
    fi

    # ── Defconfig: SukiSU + SUSFS + KPM ───────────────────
    local DEFCONFIG="$KERNEL_DIR/arch/arm64/configs/gki_defconfig"

    local ALL_CONFIGS=(
        # KSU + KPM
        "CONFIG_KSU=y"
        "CONFIG_KPM=y"
        "CONFIG_KSU_MANUAL_HOOK=y"

        # SUSFS
        "CONFIG_KSU_SUSFS=y"
        "CONFIG_KSU_SUSFS_HAS_MAGIC_MOUNT=y"
        "CONFIG_KSU_SUSFS_SUS_PATH=y"
        "CONFIG_KSU_SUSFS_SUS_MOUNT=y"
        "CONFIG_KSU_SUSFS_AUTO_ADD_SUS_KSU_DEFAULT_MOUNT=y"
        "CONFIG_KSU_SUSFS_AUTO_ADD_SUS_BIND_MOUNT=y"
        "CONFIG_KSU_SUSFS_SUS_KSTAT=y"
        "CONFIG_KSU_SUSFS_SUS_OVERLAYFS=n"
        "CONFIG_KSU_SUSFS_TRY_UMOUNT=y"
        "CONFIG_KSU_SUSFS_AUTO_ADD_TRY_UMOUNT_FOR_BIND_MOUNT=y"
        "CONFIG_KSU_SUSFS_SPOOF_UNAME=y"
        "CONFIG_KSU_SUSFS_ENABLE_LOG=y"
        "CONFIG_KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS=y"
        "CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG=y"
        "CONFIG_KSU_SUSFS_OPEN_REDIRECT=y"
        "CONFIG_KSU_SUSFS_SUS_SU=n"

        # lz4k / crypto
        "CONFIG_CRYPTO_LZ4HC=y"
        "CONFIG_CRYPTO_LZ4K=y"
        "CONFIG_CRYPTO_LZ4KD=y"
        "CONFIG_CRYPTO_842=y"

        # BBR
        "CONFIG_TCP_CONG_ADVANCED=y"
        "CONFIG_TCP_CONG_BBR=y"
        "CONFIG_NET_SCH_FQ=y"
        "CONFIG_TCP_CONG_BIC=n"
        "CONFIG_TCP_CONG_CUBIC=n"
        "CONFIG_TCP_CONG_WESTWOOD=n"
        "CONFIG_TCP_CONG_HTCP=n"
        "CONFIG_DEFAULT_TCP_CONG=bbr"

        # Misc
        "CONFIG_LOCALVERSION_AUTO=n"
    )

    for cfg in "${ALL_CONFIGS[@]}"; do
        local key="${cfg%%=*}"
        grep -q "$key" "$DEFCONFIG" || echo "$cfg" >> "$DEFCONFIG"
    done

    # Remove check_defconfig
    sed -i 's/check_defconfig//' "$KERNEL_DIR/build.config.gki" 2>/dev/null || true
    # Remove setlocalversion scm
    sed -i 's/${scm_version}//' "$KERNEL_DIR/scripts/setlocalversion" 2>/dev/null || true

    log "Defconfig updated with KSU + SUSFS + KPM + BBR + lz4k"

    # Commit so -dirty doesn't appear
    cd "$KERNEL_DIR"
    git add -A && git commit -m "SukiSU + SUSFS + KPM setup" --allow-empty 2>/dev/null || true
}

# ── KernelPatch binary patch (post-build) ──────────────────
patch_image_kp() {
    log "=== Applying KernelPatch to Image ==="
    local BOOT_DIR="$OUT_DIR/arch/arm64/boot"
    local IMAGE="$BOOT_DIR/Image"

    cd "$BOOT_DIR"

    # Download patch_linux from SukiSU KernelPatch releases
    if [[ ! -f patch_linux ]]; then
        log "Downloading patch_linux..."
        curl -LO https://github.com/SukiSU-Ultra/SukiSU_KernelPatch_patch/releases/download/0.13.0/patch_linux
        chmod +x patch_linux
    fi

    ./patch_linux
    if [[ -f oImage ]]; then
        rm -f Image
        mv oImage Image
        log "KernelPatch applied to Image"
    else
        warn "patch_linux did not produce oImage, using original"
    fi
}

# ── AnyKernel3 packaging ──────────────────────────────────
make_ak3_zip() {
    log "=== Packaging AnyKernel3 ==="
    local AK3_DIR="$WORKSPACE/AnyKernel3"
    local IMAGE="$OUT_DIR/arch/arm64/boot/Image"
    local ZIP_NAME="SukiSU_${KSU_VERSION:-unknown}_KPM_ace5pro_$(date +%Y%m%d).zip"
    local OUT_ZIP="$WORKSPACE/$ZIP_NAME"

    [[ -f "$IMAGE" ]] || die "Image not found: $IMAGE"

    # Clone AK3
    if [[ ! -d "$AK3_DIR" ]]; then
        git clone https://github.com/Kernel-SU/AnyKernel3.git --depth 1 "$AK3_DIR"
    fi
    rm -rf "$AK3_DIR/.git" "$AK3_DIR/push.sh"

    cp "$IMAGE" "$AK3_DIR/"

    # Create flashable zip
    cd "$AK3_DIR"
    zip -r9 "$OUT_ZIP" . -x '*.git*'
    log "AK3 zip: $OUT_ZIP"

    # Also copy to /mnt/c for convenience (Windows host)
    if [[ -d /mnt/c ]]; then
        cp -f "$OUT_ZIP" "/mnt/c/Users/mc282/Desktop/098/images/" 2>/dev/null || true
    fi
}

# ── Main ───────────────────────────────────────────────────
setup_sukisu_kpm
do_build
patch_image_kp
make_ak3_zip

log "=== ALL DONE ==="
log "Flash zip: $WORKSPACE/SukiSU_${KSU_VERSION:-unknown}_KPM_ace5pro_$(date +%Y%m%d).zip"
