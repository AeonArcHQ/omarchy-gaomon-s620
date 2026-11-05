# GAOMON S620 plugin

An Omarchy bar widget that sets up the GAOMON S620 pen tablet without the vendor's driver.

## Language

**Backend**:
The driver that owns the tablet: the kernel driver or OpenTabletDriver. Exactly one is active at a time.
_Avoid_: mode, engine

**Kernel backend**:
The tablet handled by the kernel's `hid-uclogic` driver, with settings sent to Hyprland. The default.
_Avoid_: basic mode, native mode

**OTD backend**:
The tablet handled by the OpenTabletDriver daemon, with settings sent to it.
_Avoid_: advanced mode, OpenTablet mode

**Pressure range**:
The force at which the pen starts to register and the force at which it reaches full pressure; between them the response is a straight line.
_Avoid_: pressure sensitivity, pressure curve

**Pressure curve**:
The shape of the response between no pressure and full pressure, from very soft to very hard; the ends stay fixed.
_Avoid_: pressure range, sensitivity

**Express key**:
One of the four buttons in a row on the tablet's top-left corner, numbered 1–4 from the left in the right-handed orientation.
_Avoid_: pad button, shortcut key, tablet button

**Pen button**:
One of the two buttons on the pen barrel. They reach applications as stylus buttons.
_Avoid_: stylus key, side button
