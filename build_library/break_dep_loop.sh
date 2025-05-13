# Goo to attempt to resolve dependency loops on individual packages.
# If this becomes insufficient we will need to move to a full multi-stage
# bootstrap process like we do with the SDK via catalyst.
#
# Called like:
#
#     break_dep_loop [PKG_USE_PAIR]…
#
# PKG_USE_PAIR consists of two arguments: a package name (for example:
# sys-fs/lvm2), and a comma-separated list of USE flags to clear (for
# example: udev,systemd).
#
# Env vars:
#
# BDL_ROOT, BDL_PORTAGEQ, BDL_EQUERY, BDL_EMERGE
break_dep_loop() {
    local flag_file="${BDL_ROOT}/etc/portage/package.use/break_dep_loop"

    # Be sure to clean up use flag hackery from previous failed runs
    sudo rm -f "${flag_file}"

    if [[ ${#} -eq 0 ]]; then
        return 0
    fi

    # Temporarily compile/install packages with flags disabled. If a binary
    # package is available use it regardless of its version or use flags.
    local pkg use_flags disabled_flags
    local -a flags
    local -a pkgs all_flags args flag_file_entries pkg_summaries
    while [[ $# -gt 1 ]]; do
        pkg=${1}
        use_flags=${2}
        shift 2
        pkgs+=( "${pkg}" )
        mapfile -t flags <<<"${use_flags//,/$'\n'}"
        all_flags+=( "${flags[@]}" )
        disabled_flags="${flags[*]/#/-}"
        flag_file_entries+=( "${pkg} ${disabled_flags}" )
        args+=( "--buildpkg-exclude=${pkg}" )
        pkg_summaries+=( "${pkg}[${disabled_flags}]" )
    done
    unset pkg use_flags disabled_flags flags

    # If packages are already installed we have nothing to do
    local pkg any_package_uninstalled=
    for pkg in "${pkgs[@]}"; do
        if ! "${BDL_PORTAGEQ:-portageq}" has_version "${BDL_ROOT}" "${pkgs[@]}"; then
            any_package_uninstalled=x
            break
        fi
    done
    if [[ -z ${any_package_uninstalled} ]]; then
        return 0
    fi
    unset pkg any_package_uninstalled

    # Likewise, nothing to do if the flags aren't actually enabled.
    local pkg any_flag_enabled=
    local -a grep_args=( "${all_flags[@]/#/-e ^+}" )
    for pkg in "${pkgs[@]}"; do
        if "${BDL_EQUERY:-equery}" -q uses "${pkg}" | grep -q "${grep_args[@]}"; then
            any_flag_enabled=x
            break
        fi
    done
    if [[ -z ${any_flag_enabled} ]]; then
        return 0
    fi
    unset pkg any_flag_enabled grep_args

    info "Merging ${pkg_summaries[@]}"
    sudo mkdir -p "${flag_file%/*}"
    printf '%s\n' "${flag_file_entries[@]}" | sudo_clobber "${flag_file}"
    # rebuild-if-unbuilt is disabled to prevent portage from needlessly
    # rebuilding zlib for some unknown reason, in turn triggering more rebuilds.
    "${BDL_EMERGE:-emerge}"
         --rebuild-if-unbuilt=n \
         "${args[@]}" "${pkgs[@]}"
    sudo rm -f "${flag_file}"
}
