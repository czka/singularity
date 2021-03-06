#!/bin/bash
#
# Copyright (c) 2015-2016, Maciej Sieczka, Gregory M. Kurtzer. All rights
# reserved.
#
# “Singularity” Copyright (c) 2016, The Regents of the University of California,
# through Lawrence Berkeley National Laboratory (subject to receipt of any
# required approvals from the U.S. Dept. of Energy).  All rights reserved.
#
# This software is licensed under a customized 3-clause BSD license.  Please
# consult LICENSE file distributed with the sources of this project regarding
# your rights to use or distribute this software.
#
# NOTICE.  This Software was developed under funding from the U.S. Department of
# Energy and the U.S. Government consequently retains certain rights. As such,
# the U.S. Government has been granted for itself and others acting on its
# behalf a paid-up, nonexclusive, irrevocable, worldwide license in the Software
# to reproduce, distribute copies to the public, prepare derivative works, and
# perform publicly and display publicly, and to permit other to do so.

# This script defines a minimal installation process. Extra actions can be
# called from an image definition file (see eg. examples/arch.def).

# Basic sanity.
if [ -z "$SINGULARITY_libexecdir" ]; then
    echo "Could not identify the Singularity libexecdir."
    exit 1
fi

# Load functions.
if [ -f "$SINGULARITY_libexecdir/singularity/functions" ]; then
    . "$SINGULARITY_libexecdir/singularity/functions"
else
    echo "Error loading functions: $SINGULARITY_libexecdir/singularity/functions."
    exit 1
fi

if ! PACSTRAP=`singularity_which pacstrap`; then
    message ERROR "\`pacstrap' is not in PATH. You can install it with \`pacman -S arch-install-scripts'.\n"
    exit 1
fi

if ! WGET=`singularity_which wget`; then
    message ERROR "\`wget' is not in PATH. You can install it with \`pacman -S wget'.\n"
    exit 1
fi

ARCHITECTURE="`uname -m`"
if [ "$ARCHITECTURE" != 'x86_64' -a "$ARCHITECTURE" != 'i686' ]; then
    message ERROR "Architecture \`$ARCHITECTURE' is not supported."
    exit 1
fi

PACMAN_CONF_URL="https://git.archlinux.org/svntogit/packages.git/plain/trunk/pacman.conf.${ARCHITECTURE}?h=packages/pacman"

# `pacstrap' installs the whole "base" package group, unless told otherwise.
# $BASE_TO_SKIP are "base" packages that won't be normally needed on a
# container system. $BASE_TO_INST are "base" packages not present in
# $BASE_TO_SKIP. The list of packages included in "base" group may (it surely
# will, one day) change in future, so $BASE_TO_SKIP will need an update from
# time to time. Here I'm referring to `base' group contents as of 30.08.2016.
BASE_TO_SKIP='cryptsetup\|device-mapper\|dhcpcd\|iproute2\|jfsutils\|linux\|lvm2\|man-db\|man-pages\|mdadm\|nano\|netctl\|openresolv\|pciutils\|pcmciautils\|reiserfsprogs\|s-nail\|systemd-sysvcompat\|usbutils\|vi\|xfsprogs'
BASE_TO_INST=`pacman -Sgq base | grep -xv $BASE_TO_SKIP | tr '\n' ' '`

# TODO: Try choosing fastest mirror(s) with rankmirrors?
# https://wiki.archlinux.org/index.php/Mirrors#List_by_speed

Bootstrap() {
    PACMAN_CONF="/tmp/pacman.conf.$$"
    # TODO: Use mktemp instead?
    if ! eval "'$WGET' --no-verbose -O '$PACMAN_CONF' '$PACMAN_CONF_URL'"; then
        message ERROR "Failed to download \`$PACMAN_CONF_URL' to \`$PACMAN_CONF'.\n"
        exit 1
    fi

    # In addition to selected `base' packages `haveged' has to be installed.
    # It's required to generate enough entropy for Pacman package signing
    # setup without having to wait for ages until entropy accumulates. See
    # https://wiki.archlinux.org/index.php/Install_from_Existing_Linux,
    # https://wiki.archlinux.org/index.php/Pacman/Package_signing.
    if ! eval "'$PACSTRAP' -C '$PACMAN_CONF' -c -d -G -M '$SINGULARITY_ROOTFS' haveged $BASE_TO_INST"; then
        rm -f "$PACMAN_CONF"
        message ERROR "\`$PACSTRAP' failed.\n"
        exit 1
    fi

    # Pacman package signing setup.
    if ! eval "arch-chroot '$SINGULARITY_ROOTFS' /bin/sh -c 'haveged -w 1024; pacman-key --init; pacman-key --populate archlinux'"; then
        rm -f "$PACMAN_CONF"
        message ERROR "Pacman package signing setup failed.\n"
        return 1
    fi

    __mountproc
    __mountsys
    __mountdev

    return 0
}

InstallPkgs() {
    if ! __runcmd pacman -S --noconfirm "$@"; then
        return 1
    fi

    return 0
}

Cleanup() {
    if ! __runcmd pacman -Rs --noconfirm haveged; then
        return 1
    fi

    rm -f "$PACMAN_CONF"

    return 0
}
