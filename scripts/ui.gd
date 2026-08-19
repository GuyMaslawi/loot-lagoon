class_name UI
extends RefCounted

# Type & touch scale.
#
# The game renders into a 720x1280 canvas with stretch/aspect = "keep", so every
# value below is multiplied by the device scale factor -- min(W/720, H/1280) --
# before it reaches the eye:
#
#   Galaxy S24  (360x780)  -> 0.50      iPhone 15   (393x852)  -> 0.55
#   iPhone SE3  (375x667)  -> 0.52      Pixel 8     (412x915)  -> 0.57
#
# Sizes are picked so the *worst* case (0.50) still clears the platform floors:
#   Apple HIG    11pt text minimum, 44x44pt touch target
#   Material 3   12sp body-small minimum, 48x48dp touch target
#   WCAG 2.2     SC 2.5.8 target size (AA), SC 2.5.5 target size (AAA)
#
# Rule of thumb: a value here, halved, is the pt/dp it renders at on the
# smallest supported phone.

# --- type ramp ---
const F_TINY    := 22   # 11pt  badges, micro-meta -- the absolute floor
const F_CAPTION := 26   # 13pt  captions under icons, secondary rows
const F_LABEL   := 30   # 15pt  button text, list rows
const F_BODY    := 34   # 17pt  sentences meant to be read
const F_SUBHEAD := 38   # 19pt  section heads, modal titles
const F_TITLE   := 46   # 23pt
const F_HEAD    := 54   # 27pt
const F_DISPLAY := 64   # 32pt  hero numbers and logos

# --- touch targets (height, or side for square controls) ---
const TAP       := 88   # 44pt  Apple HIG minimum -- never go below this
const TAP_COMFY := 96   # 48dp  Material minimum, prefer for primary actions
const TAP_HERO  := 132  # 66pt  the raised centre SPIN control

# --- icon boxes ---
const ICON_SM := 28
const ICON_MD := 40
const ICON_LG := 56
