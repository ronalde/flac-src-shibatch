README for flac-src-shibatch
============================

 version: 0.3 (march 2013)

Script to resample flac files to a given sample rate and bit depth
using the Shibatch SRC in twopass non-fast mode while preserving the
flac metadata stored in the original files.

Requirements
------------

`ssrc`>= 1.3
`flac`
`sox` just for the `soxi` file analyzer, not intended to be used a an
      audio backend

Installation of the former commands can be achieved on Debian based
systems by executing:

    sudo apt-get install flac sox

Installation of ssrc on Debian and Ubuntu can be achieved by following
the instructions on
http://lacocina.nl/shibatch-ssrc-packages/.

Background and usage
--------------------

-  [Script to convert FLAC files using Shibatch SRC while preserving meta data](http://lacocina.nl/convert-flac-with-shibatch)


Default conversions
-------------------

-  88.2 KHz DVD-audio files are upsampled to 96KHz (ratio `147:160`)
- 176.4 KHz files are downsampled to 96Khz (ratio `80:147`)
- 192.0 KHz files are downsampled to 96Khz (ratio `2:1`)


License
-------

Copyright 2011, 2012, 2013 Ronald van Engelen <r.v.engelen@gmail.com>,
distributed under the terms of the GNU General Public License
version 2 or any later version.
 

