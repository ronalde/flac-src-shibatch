#!/bin/bash

# Script to resample 24 bit flac files to 96KHz using the Shibatch SRC
# in twopass non-fast mode while preserving the flac metadata stored
# in the original files.
#
# Background:
# http://www.lacocina.nl/artikelen/how-to-setup-a-bit-perfect-digital-audio-streaming-client-with-free-software-with-ltsp-and-mpd
# 
#  88.2 KHz DVD-audio files are upsampled to 96KHz (ratio 147:160)
# 176.4 KHz files are downsampled to 96Khz (ratio 80:147)
# 192.0 KHz files are downsampled to 96Khz (ratio 2:1)
#
# Change gcc of shiboleth Makefile to compile on Debian/Ubuntu
# $(CC) $(CFLAGS) ssrc.c fftsg_ld.c dbesi0.c -o ssrc -lm
#                                                    ^^^
# author: ronalde
# version: 0.1
# may 2011

# Shibatch sampling rate converter version 1.30
#SSRC=~/ssrc-1.30/ssrc_hp
SSRC=~/ssrc-1.30/ssrc
# download URL
SSRCSRC="http://shibatch.sourceforge.net/"
# Options to pass to the converter, example for 96.000 KHz using best
# profile using two passes
TARGETBITDEPTH="24"
TARGETSAMPLERATE="96000"
# use these options for ssrc
#SSRCOPTS="--rate ${TARGETSAMPLERATE} --twopass --quiet --profile standard"
# use these options for ssrc_hp
SSRCOPTS="--rate ${TARGETSAMPLERATE} --twopass --quiet"
# Filename for the tarball containing the source flac files
SRCFLACTAR="original-flacs.tar"

FLAC=$(which flac)
METAFLAC=$(which metaflac)

# Test existence of ssrc command
if  ! [ -x "${SSRC}" ]; then
    echo "Error: Missing shibatch sampling rate converter in \`${SSRC}'."
    echo "       Please make sure it is compiled from ${SSRCSRC} and " \
	"marked as executable."
    exit
fi

# Test existence of flac command
if  ! [ -x "${FLAC}" ]; then
    echo "Error: Missing flac converter in \`${PATH}'."
    echo "       Please make sure it is installed."
    exit
fi

# Test existence of metaflac command
if  ! [ -x "${METAFLAC}" ]; then
    echo "Error: Missing metaflac in \`${PATH}'."
    echo "       Please make sure it is installed."
    exit
fi

# Test existence of backup tarball
if [ -f "${SRCFLACTAR}" ]; then
    echo "Error: It seems you have converted this directory before."
    echo "       If not, remove \`${SRCFLACTAR}' and try again."
    exit
fi

# Test existence of files with .flac extension in current directory
FLACS=$(find . -maxdepth 1 -name "*.flac")
if [ -z "${FLACS}" ]; then
    echo "Error: There are no flac files in the current directory"
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
	    if $(${SSRC} --rate 96000 --twopass --quiet --profile standard "${TMPTARGET}/${TARGETWAV}" "${TMPTARGET}/Upsampled ${TARGETWAV}"); then
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
