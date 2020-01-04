#!/usr/bin/env bash
#  Flash Mynewt Application to nRF52 with Raspberry Pi

set -e  #  Exit when any command fails.
set -x  #  Echo all commands.

sudo /home/pi/openocd/src/openocd \
    -s /home/pi/openocd/tcl \
    -f swd-pi.ocd \
    -f scripts/nrf52-pi/flash-app.ocd