"""Authoritative effect and controller policy, based on asusctl 6.4.

These are applicable controls, not every field in the generic D-Bus structs.
Unknown effects remain selectable; unknown protocols get no guessed controls.
"""
SPEEDS = ("Low", "Med", "High")
DIRECTIONS = ("Right", "Left", "Up", "Down")
# name, colour count, speed support, direction support
EFFECTS = {
    0: ("Static", 1, False, False),
    1: ("Breathe", 2, True, False),
    2: ("Rainbow", 0, True, False),
    3: ("Wave", 0, True, True),
    4: ("Stars", 2, True, False),
    5: ("Rain", 0, True, False),
    6: ("Highlight", 1, True, False),
    7: ("Laser", 1, True, False),
    8: ("Ripple", 1, True, False),
    10: ("Pulse", 1, False, False),
    11: ("Comet", 1, False, False),
    12: ("Flash", 1, False, False),
}
ZONE_NAMES = {0: "Logo", 1: "Keyboard", 2: "Lightbar", 3: "Lid", 4: "Rear glow",
              5: "Keyboard + lightbar", 6: "Ally"}
POWER_FIELDS = ("boot", "awake", "sleep", "shutdown")


def effect_info(mode):
    name, colours, speed, direction = EFFECTS.get(mode, (f"Mode {mode}", 0, False, False))
    fields = [f"colour{i + 1}" for i in range(colours)]
    if speed:
        fields.append("speed")
    if direction:
        fields.append("direction")
    return dict(id=mode, name=name, colourCount=colours, fields=fields,
                speeds=list(SPEEDS) if speed else [],
                directions=list(DIRECTIONS) if direction else [])


def power_keys(device, supported, rows):
    zones = [row.zone for row in rows if row.zone in supported]
    if device == 1:  # Pre-2021: OR-combined Boot/Sleep, independent Awake.
        return ([(-1, "boot"), (-1, "sleep")] if zones else []) + [
            (z, "awake") for z in zones if z in (1, 2, 5)]
    if device == 2:  # TUF: first supported row only, no Shutdown.
        return [(zones[0], f) for f in POWER_FIELDS[:3]] if zones else []
    if device in (0, 4):
        return [(z, f) for z in zones for f in POWER_FIELDS]
    return []


def power_controls(device, supported, rows):
    controls = []
    for zone, field in power_keys(device, supported, rows):
        shared = zone == -1
        name = ZONE_NAMES.get(zone, f"Zone {zone}")
        controls.append(dict(
            id=f"{zone}:{field}", zone=zone, field=field,
            scope="shared" if shared else "zone",
            target="keyboard and lightbar" if shared else name.lower(),
            label=f"Shared {field}" if shared else f"{name} {field}",
            value=any(getattr(row, field) for row in rows if shared or row.zone == zone),
        ))
    return controls
