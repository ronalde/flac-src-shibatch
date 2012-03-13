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

    if [ -d "$DIR" ]; then
	if [ -w "$DIR" ]; then
	    FILES=$(find "$DIR" -maxdepth 1 -iname "*.flac" -or -iname "*.wav")

	    if [ -n "$FILES" ] ; then
		echo "Found the following files:"
		echo "$FILES" | while read FILE
		do 
		    echo "$FILE"
		    analyze_file "$FILE"
		done
		#

		exit 0

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


# Main

# Parse command line arguments
if ! ARGS=$(getopt -n "$0" -o +a:b:cdhmpr -l \
    'samplerate:,bitdepth:,list,upsample,downsample,purge,help' -- "$@"); then
    exit 1
fi

# source the generic functions
 . ./get-samplerate
 . ./get-bitdepth
 . ./analyze-file

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

if [ $LIST ]; then
    list_sourcefiles
fi


# verify samplerate and bitdepth
get_samplerate $SAMPLERATE
get_bitdepth $BITDEPTH


echo "Preparing to process $DIR"
list_sourcefiles "$DIR"