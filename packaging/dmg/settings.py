# The disk image's window, for dmgbuild. scripts/make-dmg.sh passes the app
# and the background:
#
#   dmgbuild -s packaging/dmg/settings.py -D app=APP -D background=PNG VOLUME OUT.dmg
#
# The window and the icons' places match scripts/make-dmg-background.swift;
# change both together.
import os.path

application = defines["app"]
name = os.path.basename(application)
# The link to Applications is named with a blank Braille cell, U+2800, so
# it shows no name. Named with a space, Finder draws the hidden .background
# folder over it; named so, it draws the link on top.
link = "\u2800"

# make-dmg.sh moves the background into .background/ and then compresses.
format = "UDRW"
filesystem = "HFS+"
files = [application]
symlinks = {link: "/Applications"}
# No hide_extensions: Finder hides .app already, and the flag it sets is
# Finder info on the bundle, which strict code signature checks reject.
background = defines["background"]
# No volume icon: .VolumeIcon.icns would be another hidden file, and nothing
# in the window hides its preview.

# 300 points show below the 32-point title bar. Finder scrolls only to show
# icons and names, never for the background, so a path bar or status bar
# just crops the background. With a grid spacing of 1, an icon and its name
# reach 96 points below the icon's center: 240 here, which still shows with
# both bars (about 28 points each).
window_rect = ((400, 360), (540, 332))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
show_icon_preview = False
arrange_by = None
grid_spacing = 1
icon_size = 128
text_size = 13
label_pos = "bottom"
icon_locations = {
    name: (150, 144),
    link: (390, 144),
    # For those who show hidden files: a folder hides exactly behind the
    # Applications folder. Anywhere else it would show, or make the window
    # scroll.
    ".background": (390, 144),
}
