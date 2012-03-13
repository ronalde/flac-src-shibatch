#!/bin/sh

#
# Copyright 2011, 2012 Ronald van Engelen <rvengelen@hethooghuis.nl>,
# distributed under the terms of the GNU General Public License
# version 2 or any later version.
# 

# set -e

usage() {
cat <<EOF
$0 [ -s | --samplerate <samplerate> ] [ -b | --bitdepth <bitdepth> ] [ <other options> ]  -- directory

Resamples flac or wav files in the current directory tot the specified
bit depth and sample rate. Defaults to only upsample to 96Khz/24bit.

  -s, --samplerate     Target sample rate in Hz (defaults to 96000)
  -b, --bitdepth       Target bit depth (defaults to 24)
  -l, --list           List sample rates of source flac files
  -d, --downsample     Limit resampling to downsampling (default: false)
  -u, --upsample       Limit resampling to upsampling (default: true)
  -p, --purge          Remove original flac files after resampling  (defaults to keep)
  -h, --help           Show this help message
EOF
}

check_sanity() {

    test -x "$(which $SSRC)" || die "Error: command 'ssrc_hp' not found"
    test -x "$(which flac)" || die "Error: command 'flac' not found"
    test -x "$(which metaflac)" || die "Error: command 'metaflac' not found"

    if [ ! -n "$DIR" ] ; then
	DIR="$(pwd)"
    fi

}

analyze_command_line() {
    local done_opts

    while [ -z "$done_opts" ] ; do
        case "$1" in
            -b|--bitdepth) BITDEPTH=$(echo $2 | sed -e "s,',,g") ; shift 2 ;;
            -d|--downsample) DOWNSAMPLE=true; shift 1 ;;
            -h|--help) usage ; exit 0 ;;
            -l|--list) LIST=true ; shift 1 ;;
            -u|--upsample) UPSAMPLE=true; shift 1 ;;
            -p|--purge) PURGE=true; shift 1 ;;
            -s|--samplerate) SAMPLERATE=$(echo $2 | sed -e "s,',,g") ; shift 2 ;;
            *) 
		done_opts=true
		if [ ! -d "$@" ]; then
		    die "Error: Invalid path $@"
		fi
		;;
            #*) 
        esac
    done
    #DIR=$(echo "$@" | sed 's/\\//')
    DIR="${@}"
    if [ -d "$DIR" ] ; then
	echo "Dir $DIR is a dir"
    else
	echo "Not a dir: $DIR"
    fi
}

default_options() {

    if [ ! -n "$SAMPLERATE" ]; then
	SAMPLERATE="96000"
    fi

    if [ ! -n "$BITDEPTH" ]; then
	BITDEPTH="24"
    fi

    SSRC=ssrc_hp
    SSRCOPTS="--rate $SR --bits $BD --twopass --quiet"

    # Filename for the tarball containing the source flac files
    SRCFLACTAR="original-flacs.tar"

}


resample() {
    ${SSRC} $SSRCOPTS "$SOURCEWAV" "$TARGETWAV"
}


list_sourcefiles() {

    #echo "Dir: ${DIR}"
    #FDIR=$(find "$DIR" -type d)
    if [ -d "$DIR" ]; then
	if [ -w "$DIR" ]; then
	    FLACS=$(find "$DIR" -maxdepth 1 -name "*.flac")
	    WAVS=$(find "$DIR" -maxdepth 1 -name "*.wav")
	    if [ -n "$FLACS" ] || [ -n "$WAVS" ]; then
		echo "Found the following files:"
		if [ -n "$FLACS" ]; then
		    echo "$FLACS"
		fi
		if [ -n "$WAVS" ]; then
		    echo "$WAVS"
		fi
	    else
		die "Error: No flac or wav files found in directory $DIR"
	    fi
	else
	    die "Error: No write permissions in directory $DIR"    
	fi
    else
	echo "Error: $DIR is not a directory"
    fi

}

flacs() {

# Test existence of backup tarball
    if [ -f "${SRCFLACTAR}" ]; then
	echo "Error: It seems you have converted this directory before. /
           If not, remove \`${SRCFLACTAR}' and try again."
	exit
    fi
    
# Temporary sub directory for storing intermediate files
# will be cleaned afterwards
    TMPTARGET=$(mktemp -d "original.XXXXXXXXXX")

# Save internal field separator of bash,
# will be restored afterwards
    SAVEIFS=$IFS
    IFS=$(echo -en "\n\b")

# Process each file with .flac extension in current directory
    for f in *.flac
    do
	SRCFLAC="$f"
    # Test whether this is a real FLAC file
	SRCFLACMIME=$(file -b "${SRCFLAC}" | cut -d' ' -f1)
	if [ "${SRCFLACMIME}" != "FLAC" ]; then
	    echo "Warning: not processing \`${SRCFLAC}'; it seems not to be a FLAC-file."
	else
	    SRCSAMPLERATE=$(${METAFLAC} --show-sample-rate "${SRCFLAC}")
	    SRCBITDEPTH=$(${METAFLAC} --show-bps "${SRCFLAC}")
	    echo "Processing file \`${SRCFLAC}'"
	    echo " ... will convert from ${SRCBITDEPTH}bit/${SRCSAMPLERATE}Hz to ${TARGETBITDEPTH}bit/${TARGETSAMPLERATE}Hz"
        # Extract basename (ie filename without extension) 
	    BASENAME=$(echo "${SRCFLAC}" | cut -d \. -f 1 -)
	    TARGETWAV="${BASENAME}.wav"
        # Try to decode original flac file to wav file in temp directory 
	    echo " ... decoding to PCM"
	    if $(${FLAC} -s -d -o "${TMPTARGET}/${TARGETWAV}" "${SRCFLAC}"); then
	    # Move original FLAC to temporary directory
		mv "${SRCFLAC}" "${TMPTARGET}"
            # Upsample original wav according to SSRCOPTS
		echo " ... resampling"
		if $(resample ${SSRC} --rate 96000 --twopass --quiet --profile standard "${TMPTARGET}/${TARGETWAV}" "${TMPTARGET}/Upsampled ${TARGETWAV}" ); then
                # Encode upsampled wav file to flac
		    echo " ... recoding with flac"
		    $(${FLAC} -s "${TMPTARGET}/Upsampled ${TARGETWAV}" -o "${SRCFLAC}")
                # Store flac tags from original flac file in upsampled flac file
 		    $(${METAFLAC} --export-tags-to - "${TMPTARGET}/${SRCFLAC}" | ${METAFLAC} --import-tags-from - "${SRCFLAC}")
		    echo " done."
		else
	    	    echo "Error: Could not convert \`${TMPTARGET}/${TARGETWAV}' to \`${TMPTARGET}/Upsampled ${TARGETWAV}'"
	    	    echo "       Please review those temporary files and converter output."
		fi
	    fi
	fi
    done

    if [ -d "${TMPTARGET}" ]; then
    # HARRY=$(tar cf "${SRCFLACTAR}" "${TMPTARGET}")
	$(tar cf "${SRCFLACTAR}" "${TMPTARGET}")
    # if [ $HARRY ] ; then
    # 	echo "Done!"
    # 	echo "... original flac files copied to tarball \`original-882000-flac.tar'"
    # 	echo "... resulting upsampled flac files with metadata available in this directory"
    #     rm -rf "${TMPTARGET}"
    # else
    # 	echo "Error creating tarball of original flac files"
    # 	echo "... please review the temporary files in \`${TMPTARGET}'"
    # fi
    fi
    
    IFS=${SAVEIFS}

}

# Common functions shared by upsample scripts

die() {
    echo "$@" >&2
    exit 1
}

boolean_is_true() {
    case $1 in
       # match all cases of true|y|yes
       [Tt][Rr][Uu][Ee]|[Yy]|[Yy][Ee][Ss]) return 0 ;;
       *) return 1 ;;
    esac
}


# list files in a directory consisting only of alphanumerics, hyphens and
# underscores
# $1 - directory to list
# $2 - optional prefix to limit which files are selected
run_parts_list() {
    test $# -ge 1 || die "ERROR: Usage: run_parts_list <dir>"
    if [ -d "$1" ]; then
        find -L "$1" -mindepth 1 -maxdepth 1 -type f -name "$2*" |
            sed -n '/.*\/[0-9a-zA-Z_\-]\{1,\}$/p' | sort -n
    fi
}


# Remember mounted dirs so that it's easier to unmount them with a single call
# to umount_marked. They'll be unmounted in reverse order.
# Use the normal mount syntax, e.g.
#   mark_mount -t proc proc "$ROOT/proc"
mark_mount() {
    local dir

    # The last parameter is the dir we need to remember to unmount
    dir=$(eval "echo \$$#")
    if mount "$@"; then
        # Use newlines to separate dirs, in case they contain spaces
        if [ -z "$MARKED_MOUNTS" ]; then
            MARKED_MOUNTS="$dir"
        else
            MARKED_MOUNTS="$dir $MARKED_MOUNTS"
        fi
    else
        die "Could not mount $dir."
    fi
}

umount_marked() {
    [ -z "$MARKED_MOUNTS" ] && return

    echo "$MARKED_MOUNTS" | while read dir; do
        # binfmt_misc might need to be unmounted manually, see LP #534211
        if [ "$dir%/proc}" != "$dir" ] && 
            ( [ "$VENDOR" = "Debian" ] || [ "$VENDOR" = "Ubuntu" ] ) &&
            [ -d "$dir/sys/fs/binfmt_misc" ] && [ -f "$dir/mounts" ] &&
            grep -q "^binfmt_misc $dir/sys/fs/binfmt_misc" "$dir/mounts"; then
            if ! umount "$dir/sys/fs/binfmt_misc"; then
                echo "Couldn't unmount $dir/sys/fs/binfmt_misc." >&2
            fi
        fi
        if ! umount "$dir"; then
            echo "Couldn't unmount $dir." >&2
        fi
    done
}




# Main


# Parse command line arguments
if ! ARGS=$(getopt -n "$0" -o +a:b:cdhmpr -l \
    'samplerate:,bitdepth:,list,upsample,downsample,purge,help' -- "$@"); then
    exit 1
fi

# source the generic functions
 . ./get-samplerate
 . ./get-bitdepth

# include the configuration file if it exists
#if [ -f /etc/resample/resample.conf ]; then
#    . /etc/resample/resample.conf
#fi

# parse commandline parameters
analyze_command_line "$@"

# get defaults
default_options

# check existence of programs
check_sanity

# verify samplerate and bitdepth
get_samplerate $SAMPLERATE
get_bitdepth $BITDEPTH


echo "Preparing to process $DIR"
list_sourcefiles "$DIR"