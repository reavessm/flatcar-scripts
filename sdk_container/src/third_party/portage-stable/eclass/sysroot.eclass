# Copyright 2025 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

# @ECLASS: sysroot.eclass
# @MAINTAINER:
# cross@gentoo.org
# @AUTHOR:
# James Le Cuirot <chewi@gentoo.org>
# @SUPPORTED_EAPIS: 8
# @BLURB: Common functions for using a different sysroot (e.g. cross-compiling)

case ${EAPI} in
	7|8) ;;
	*) die "${ECLASS}: EAPI ${EAPI:-0} not supported" ;;
esac

# @FUNCTION: qemu_arch
# @DESCRIPTION:
# Return the QEMU architecture name for the current CHOST. This name is used in
# qemu-user binary filenames, e.g. qemu-ppc64le.
qemu_arch() {
	case "${CHOST}" in
		armeb*) echo armeb ;;
		arm*) echo arm ;;
		hppa*) echo hppa ;;
		i?86*) echo i386 ;;
		mips64el*) [[ ${ABI} == n32 ]] && echo mipsn32el || echo mips64el ;;
		mips64*) [[ ${ABI} == n32 ]] && echo mipsn32 || echo mips64 ;;
		powerpc64le*) echo ppc64le ;;
		powerpc64*) echo ppc64 ;;
		powerpc*) echo ppc ;;
		*) echo "${CHOST%%-*}" ;;
	esac
}
