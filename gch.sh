#!/bin/bash

# gentoo-sources compilation helper
#
# Copyright (C) 2017 Marcus Hoffren <marcus@harikazen.com>.
# License GPLv3+: GNU GPL version 3 or later <http://gnu.org/licenses/gpl.html>.
# This is free software: you are free to change and redistribute it.
# There is NO WARRANTY, to the extent permitted by law.
#

### <source_functions>

. func/error.sh 2>/dev/null || { echo -e "\n\e[91m*\e[0m error.sh not found"; exit 1; } # error handler
. func/except.sh 2>/dev/null || error "\n\e[91m*\e[0m except.sh not found" # exception handler
. func/version.sh 2>/dev/null || error "\n\e[91m*\e[0m version.sh not found"
. func/largest.sh 2>/dev/null || error "\n\e[91m*\e[0m largest.sh not found" # return largest element from array
. func/usage.sh 2>/dev/null || error "\n\e[91m*\e[0m usage.sh not found"
. func/gtoe.sh 2>/dev/null || error "\n\e[91m*\e[0m gtoe.sh not found" # lexicographic greater than or equal

### </source_functions>

### <sanity_check>

if [[ -e gch.conf ]]; then
    . gch.conf
else
    error "gkh.conf not found"
fi

[[ $(whoami) != "root" ]] && error \
    "You must be root to run this script"
[[ "${BASH_VERSION}" < 4.4 ]] && error \
    "${0##*/} requires \033[1mbash v4.4\033[m or newer"
[[ $(type -p perl) == "" ]] && error \
    "perl is missing. Install \033[1mdev-lang/perl\033[m"
[[ $(type -p zcat) == "" ]] && error \
    "zcat is missing. Install \033[1mapp-arch/gzip\033[m"
[[ $(type -p uname) == "" ]] && error \
    "uname is missing. Install \033[1msys-apps/coreutils\033[m"
[[ $(type -p mount) == "" ]] && error \
    "mount is missing. Install \033[1msys-apps/util-linux\033[m"
[[ $(type -p getopt) == "" ]] && error \
    "getopt is missing. Install \033[1msys-apps/util-linux\033[m"
[[ $(type -p grub-mkconfig) == "" ]] && error \
    "grub-mkconfig is missing. Install \033[1msys-boot/grub\033[m"
[[ $(type -p find) == "" ]] && error \
    "find is missing. Install \033[1msys-apps/findutils\033[m"

### </sanity_check>

scriptdir="$( cd $(dirname "${BASH_SOURCE[0]}") && pwd )"; except "Could not cd to script directory" # save script directory

### <populate_array_with_kernel_versions>

kerndirs=(${kernelroot}/*); kerndirs=("${kerndirs[@]##*/}") # basename
kernhigh="$(largest "${kerndirs[@]}")" # return largest element from array

### </populate_array_with_kernel_versions>

### <script_arguments>

{ OPTS=$(getopt -ngch.sh -a -o "vk:yh" -l "version,kernel:,yestoall,help" -- "${@}"); except "getopt: Error in argument"; }

eval set -- "${OPTS}" # evaluating to avoid white space separated expansion

while true; do
    case ${1} in
	--version|-v)
	    version
	    exit 0;;
	--kernel|-k)
	    trigger="1"
	    kernhigh="${2}" # make input argument highest version
	    shift 2;;
	--yestoall|-y)
	    yestoall="1"
	    shift;;
	--help|-h)
	    usage
	    exit 0;;
	--)
	    shift
	    break;;
	*)
	    usage
	    exit 1;;
    esac
done

### </script_arguments>

### <kernel_version_sanity_check>

re="^(linux-)[0-9]{1,2}\.[0-9]{1,2}\.[0-9]{1,2}(-r[0-9]([0-9])?)?(-gentoo)(-r[0-9]([0-9])?)?$"

if [[ "${kernhigh}" =~ ${re} ]]; then # check if input format is valid
    if [[ "${trigger}" == "1" ]]; then # --kernel option set
	for (( i = 0; i < ${#kerndirs[@]}; i++ )); do
	    [[ "${kerndirs[${i}]}" == "${kernhigh}" ]] && { current="${kernhigh}"; break; } # check if version exists
	done
    elif [[ ${1} == "" ]]; then
	current="${kernhigh}" # if run without argument, make highest version current
    else
	error "${1} - Invalid argument"
    fi
    [[ ${current} == "" ]] && error "${kernhigh} - Version does not exist. Is it installed under ${kernelroot}?"
else
    error "${kernhigh} - Illegal format. Use linux-<version>-gentoo[<-r<1-9>>]"
fi; unset re kerndirs trigger

### </kernel_version_sanity_check>

### <kernel_reinstall_check>

if [[ ${current} =~ ^linux-$(uname -r)$ ]]; then
    echo ""
    if [[ ${yestoall} == "1" ]]; then
	REPLY="y"
    else
	read -rp "Kernel ${current} currently in use. Do you want to reinstall it? [y/N] "
    fi
    [[ "${REPLY}" != "y" ]] && { echo -e "\nSee ya!\n"; exit 0; }
fi

### </kernel_reinstall_check>

### <mount_handling>

if [[ $(find ${bootmount} -maxdepth 0 -empty) ]]; then # check if directory is empty
    echo ""
    if [[ ${yestoall} == "1" ]]; then
	REPLY="y"
    else
	read -rp "${bootmount} is empty. Do you want to try to mount it? [y/N] "
    fi

    if [[ "${REPLY}" == "y" ]]; then
	[[ $(grep -o ${bootmount} ${fstab}) == "" ]] && error "${bootmount} missing from ${fstab}"
	mount "${bootmount}" 2>/dev/null; except "Could not mount ${bootmount}"
    else
	error "${bootmount} is empty"
    fi
fi; unset fstab

### </mount_handling>

echo -e "\n\e[92m*\e[0m Processing kernel: \033[1m${current}\033[m"

### <symbolic_link_handling>

[[ -L ${kernelroot}/linux ]] && { rm ${kernelroot}/linux 2>/dev/null; except "Could not remove symbolic link ${kernelroot}/linux"; }

echo -e ">>> Creating symbolic link \033[1m${kernelroot}/${current}\033[m as \033[1m${kernelroot}/linux\033[m\n"
{ ln -s "${kernelroot}/${current}" "${kernelroot}/linux" 2>/dev/null;  except "Could not create symbolic link"; }

### </symbolic_link_handling>

### <config_handling>

if [[ ! -f ${kernelroot}/linux/.config ]]; then
	if [[ ${yestoall} == "1" ]]; then
	    REPLY="y"
	else
	    read -rp "${kernelroot}/linux/.config not present. Reuse old .config from /proc/config.gz? [y/N] "
	fi

	if [[ "${REPLY}" == "y" ]]; then
	    if [[ -e /proc/config.gz ]]; then
		echo -e "\n>>> Deflating \033[1m/proc/config.gz\033[m to \033[1m${kernelroot}/linux/.config\033[m\n"
		{ zcat /proc/config.gz > "${kernelroot}/linux/.config" 2>/dev/null; \
		    except "Could not deflate /proc/config.gz to ${kernelroot}/linux/.config"; }
	    else
		echo -e "\n\e[91m*\e[0m The following kernel flags need to be set:"
		echo -e "\e[91m*\e[0m \033[1m\033[1mCONFIG_PROC_FS\033[m"
		echo -e "\e[91m*\e[0m \033[1m\033[1mCONFIG_IKCONFIG\033[m"
		echo -e "\e[91m*\e[0m \033[1m\033[1mCONFIG_IKCONFIG_PROC\033[m\n"
		exit 1
	    fi
	else
	    echo -e "\n>>> Running manual kernel configuration\n"
	fi
elif [[ ! -s ${kernelroot}/linux/.config ]]; then
    error ".config is empty"
fi

cd "${kernelroot}/linux" 2>/dev/null || error "Could not cd ${kernelroot}/linux"; unset kernelroot

{ make ${makeconf}; except "make ${makeconf} failed"; }; unset makeconf

### </config_handling>

### <compilation_handling>

echo ""
if [[ ${yestoall} == "1" ]]; then
    REPLY="y"
else
    read -rp "Init complete. Do you want to compile kernel now? [y/N] "
fi

if [[ "${REPLY}" == "y" ]]; then
    echo ""
    { make ${makeopt} ${makearg}; except "make ${makeopt} ${makearg} failed"; }
else
    echo -e "\nSee Ya!\n"; exit 0
fi; unset makeopt makearg yestoall

### </compilation_handling>

### <naming_with_architecture>

case ${arch} in
    x64)
	re="$(echo "${current:6}" | perl -pe 's/(\d{1,2}\.\d{1,2}\.\d{1,2})/\1-x64/')";;
    x32)
	re="$(echo "${current:6}" | perl -pe 's/(\d{1,2}\.\d{1,2}\.\d{1,2})/\1-x32/')";;
    *)
	error "\${arch}: ${arch} - Valid architectures are \033[1mx32\033[m and \033[1mx64\033[m";;
esac

### </naming_with_architecture>

### <move_kernel_to_boot_and_rename_arch>

case ${kerninstall} in
    cp)
	copy="copy";;
    mv)
	copy="mov";;
    *)
	error "\${kerninstall}: ${kerninstall} - Valid arguments are \033[1mcp\033[m and \033[1mmv\033[m";;
esac

if [[ "${kernhigh}" =~ ^${current}$ ]]; then
	echo -e "\n>>> ${copy}ing \033[1m${bootmount}/System.map-${current:6}\033[m to \033[1m${bootmount}/System.map-${re}\033[m"
	{ ${kerninstall} "${bootmount}/System.map-${current:6}" ${bootmount}/System.map-"${re}" \
	    2>/dev/null; except "${copy}ing System.map failed"; }
	echo -e ">>> ${copy}ing \033[1m${bootmount}/config-${current:6}\033[m to \033[1m${bootmount}/config-${re}\033[m"
	{ ${kerninstall} "${bootmount}/config-${current:6}" ${bootmount}/config-"${re}" \
	    2>/dev/null; except "${copy}ing config failed"; }
	echo -e ">>> ${copy}ing \033[1m${bootmount}/vmlinuz-${current:6}\033[m to \033[1m${bootmount}/vmlinuz-${re}\033[m"
	{ ${kerninstall} "${bootmount}/vmlinuz-${current:6}" ${bootmount}/vmlinuz-"${re}" \
	    2>/dev/null; except "${copy}ing vmlinuz failed"; }
	if [[ -f "${bootmount}/initramfs-${current}" ]]; then
	    echo -e ">>> ${copy}ing \033[1m${bootmount}/initramfs-${current:6}\033[m to \033[1m${bootmount}/initramfs-${re}\033[m"
	    { ${kerninstall} "${bootmount}/initramfs-${current:6}" ${bootmount}/initramfs-"${re}" \
		2>/dev/null; except "${copy}ing initramfs failed"; }
	fi
else
    error "Something went wrong.."
fi; unset re kernhigh kerninstall copy

### </move_kernel_to_boot_and_rename_arch>

### <grub_handling>

echo ""
{ grub-mkconfig -o "${grubcfg}"; except "grub-mkconfig failed"; }

### </grub_handling>

### <unmount_handling>

if [[ ! $(mount | grep -o "${bootmount}") == "" ]]; then
    echo -e "\n>>> Unmounting ${bootmount}"
    umount "${bootmount}" 2>/dev/null; except "umount ${bootmount} failed"
fi; unset grubcfg bootmount

### </unmount_handling>

echo -e "Kernel version \033[1m${current}\033[m is now installed"; unset current

cd "${scriptdir}" 2>/dev/null || error "Could not cd to ${scriptdir}"; unset scriptdir # return to script directory

echo -e "\n\e[93m*\e[0m If you have any installed packages with external modules"
echo -e "\e[93m*\e[0m such as VirtualBox or GFX card drivers, don't forget to"
echo -e "\e[93m*\e[0m run \033[1m# emerge -1 @module-rebuild\033[m after upgrading\n"
exit 0
