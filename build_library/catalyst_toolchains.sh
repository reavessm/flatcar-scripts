#!/bin/bash

set -e
source /tmp/chroot-functions.sh
source /tmp/toolchain_util.sh
source /tmp/break_dep_loop.sh

# A note on packages:
# The default PKGDIR is /usr/portage/packages
# To make sure things are uploaded to the correct places we split things up:
# crossdev build packages use ${PKGDIR}/crossdev (uploaded to SDK location)
# build deps in crossdev's sysroot use ${PKGDIR}/cross/${CHOST} (no upload)
# native toolchains use ${PKGDIR}/target/${BOARD} (uploaded to board location)

configure_target_root() {
    local board="$1"
    local cross_chost=$(get_board_chost "$1")
    local profile=$(get_board_profile "${board}")

    CBUILD="$(portageq envvar CBUILD)" \
        CHOST="${cross_chost}" \
        ROOT="/build/${board}" \
        SYSROOT="/build/${board}" \
        _configure_sysroot "${profile}"
}

build_target_toolchain() {
    local board="$1"
    local ROOT="/build/${board}"
    local SYSROOT="/usr/$(get_board_chost "${board}")"

    mkdir -p "${ROOT}/usr"
    cp -at "${ROOT}" "${SYSROOT}"/lib*
    cp -at "${ROOT}"/usr "${SYSROOT}"/usr/include "${SYSROOT}"/usr/lib*

    local -a args_for_bdl=()
    if [[ -n ${clst_VERBOSE} ]]; then
        args_for_bdl+=(-v)
    fi
    function btt_bdl_portageq() {
        ROOT=${ROOT} SYSROOT=${ROOT} PORTAGE_CONFIGROOT=${ROOT} portageq "${@}"
    }
    function btt_bdl_equery() {
        ROOT=${ROOT} SYSROOT=${ROOT} PORTAGE_CONFIGROOT=${ROOT} equery "${@}"
    }
    function btt_bdl_emerge() {
        PORTAGE_CONFIGROOT="$ROOT" run_merge --root="$ROOT" --sysroot="$ROOT" "${@}"
    }
    # Breaking the following loops here:
    #
    # cryptsetup[udev] -> libudev[systemd] -> systemd[cryptsetup] -> cryptsetup
    # lvm2[udev] -> libudev[systemd] -> systemd[cryptsetup] -> cryptsetup -> lvm2
    #      systemd requires udev, so needs to be disabled too
    # lvm2[lvm] -> systemd[cryptsetup] -> cryptsetup -> lvm2
    #      thin requires lvm, so needs to be disabled too
    # systemd[cryptsetup] -> cryptsetup -> tmpfiles[systemd] -> systemd
    # util-linux[audit] -> audit[python] -> python -> util-linux
    # util-linux[cryptsetup] -> cryptsetup -> util-linux
    # util-linux[selinux] -> libselinux[python] -> python -> util-linux
    # util-linux[systemd] -> systemd -> util-linux
    # util-linux[udev] -> libudev[systemd] -> systemd -> util-linux
    args_for_bdl+=(
        sys-apps/systemd cryptsetup
        sys-apps/util-linux audit,cryptsetup,selinux,systemd,udev
        #sys-fs/cryptsetup udev
        #sys-fs/lvm2 lvm,systemd,thin,udev
    )
    BDL_ROOT=${ROOT} \
    BDL_PORTAGEQ=btt_bdl_portageq \
    BDL_EQUERY=btt_bdl_equery \
    BDL_EMERGE=btt_bdl_emerge \
        break_dep_loop "${args_for_bdl[@]}"
    unset btt_bdl_portageq btt_bdl_equery btt_bdl_emerge

    # --root is required because run_merge overrides ROOT=
    PORTAGE_CONFIGROOT="$ROOT" \
        run_merge -u --root="$ROOT" --sysroot="$ROOT" "${TOOLCHAIN_PKGS[@]}"
}

configure_crossdev_overlay / /usr/local/portage/crossdev

for board in $(get_board_list); do
    echo "Building native toolchain for ${board}"
    target_pkgdir="$(portageq envvar PKGDIR)/target/${board}"
    PKGDIR="${target_pkgdir}" configure_target_root "${board}"
    PKGDIR="${target_pkgdir}" build_target_toolchain "${board}"
done
