#!/bin/sh
# Power settings for Xfce (xfce4-power-manager) on a MacBookPro13/14, written automatically from the source scripts (tag v2.122).
# Lid closed: on AC power = 0 (turn the screen off),
# on battery = 6 (shut down); never suspend (1).
# Power button = 0 (nothing): on these models the Touch ID sensor is the power button.
# Not yet run on a Mac by the automatic publication; run it as the desktop user, in the graphical session.
set -eu
x() { xfconf-query -c xfce4-power-manager -p "/xfce4-power-manager/$1" -n -t int -s "$2"; }
x lid-action-on-ac 0
x lid-action-on-battery 6
x power-button-action 0
