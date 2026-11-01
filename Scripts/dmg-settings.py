"""Finder layout for the Rydool installer image (used by dmgbuild)."""

files = [defines["app"]]
symlinks = {"Applications": "/Applications"}
format = "UDZO"
background = defines["background"]
window_rect = ((200, 120), (640, 380))
default_view = "icon-view"
show_toolbar = False
show_status_bar = False
show_sidebar = False
show_pathbar = False
icon_size = 112
text_size = 13
icon_locations = {"Rydool.app": (175, 205), "Applications": (465, 205)}
