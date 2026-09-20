# Capability audit and deliberate boundaries

Verified against the live G513QM / USB 1866 controller and upstream asusctl
[6.4.0](https://github.com/opengamingcollective/asusctl/tree/6.4.0).
D-Bus acceptance/readback is not proof that a physical effect uses a field.

## Effect controls

`Controls.js` and `aura.py` match the applicable fields in upstream
[`aura_types.slint`](https://github.com/opengamingcollective/asusctl/blob/6.4.0/rog-control-center/ui/types/aura_types.slint).
Only modes actually returned by `SupportedBasicModes` are offered.

| Tested mode | ID | Colours | Speed | Direction |
| --- | --- | --- | --- | --- |
| Static | 0 | 1 | No | No |
| Breathe | 1 | 2 | Low/Med/High | No |
| Rainbow Cycle | 2 | None | Low/Med/High | No |
| Rainbow Wave | 3 | None | Low/Med/High | Right/Left/Up/Down |
| Pulse | 10 | 1 | No supported control | No |

Pulse accepts a generic speed value and asusd transmits it, but upstream
exposes no Pulse speed control. Our observation that Breathe Low is slower
than Pulse Low does **not** prove Pulse ignores all speed values. No arbitrary
milliseconds or slower-than-Low setting is exposed.

## Power protocol

`DeviceType = 1` is `LaptopKeyboardPre2021`; the controller protocol matters,
not the laptop's marketing year. In upstream
[`keyboard/power.rs`](https://github.com/opengamingcollective/asusctl/blob/6.4.0/rog-aura/src/keyboard/power.rs):

- Keyboard and lightbar Awake have independent enable bits.
- Boot and Sleep bits are shared and OR-combined across all power rows.
- The Shutdown field is ignored. The legacy Boot bit group is documented
  as Boot/Shutdown; it does not offer a separate Shutdown policy.

The plugin displays shared flags using OR and writes shared changes to every
row so disabling them really clears the shared bits. Independent Awake writes
read fresh daemon state and preserve all unrelated flags. It does not rewrite
unsupported Shutdown values. New-protocol controllers get four flags per
reported power zone; TUF gets three flags on its first row; unknown protocols
get no speculative power controls.

## RGB zones: not the same as power zones

This machine reports:

- `SupportedBasicZones = [1, 2, 3, 4]`: keyboard regions, left to right.
- `SupportedPowerZones = [1, 2]`: keyboard and lightbar power.
- No lightbar RGB zones (`6`, `7`), no advertised advanced addressing support.

Reliable persisted per-zone editing remains **unimplemented**, rather than
presenting controls that cannot be round-tripped correctly:

1. `LedModeData` and `AllModeData` return the global `builtins` values, even
   while multizone is active. No D-Bus property exposes `multizone_on` or saved
   per-zone effects in 6.4.0.
2. [`AuraConfig::set_builtin`](https://github.com/opengamingcollective/asusctl/blob/6.4.0/asusd/src/aura_laptop/config.rs)
   returns early when updating an existing saved zone, before setting
   `multizone_on = true`. A successful zone write need not enable persisted
   multizone operation; modes/Resync can subsequently restore global lighting.
3. A zone-zero write deliberately sets `multizone_on = false`.

The helper reads only the top-level `multizone_on` flag from the daemon's
known config path, without writing it, interpreting saved enum IDs, restarting
asusd, or sending raw packets. Unknown/unreadable state blocks ordinary global
parameter writes. Zoned mode hides global colour/speed/direction values and
requires an explicit **Replace zones** action to leave it. Its tooltip explains
that this applies the saved global effect and enables parameter editing.
Saved-mode selection and Resync preserve the daemon's zone selection.

This guard is checked again at write time, not merely from the panel's cache.
Concurrent external clients can still race these operations; D-Bus does not
provide an atomic compare-and-set interface.

## Write semantics

- One writer serializes all plugin operations; adjacent same-field pending
  updates coalesce to the latest value without crossing mode/field barriers.
- Mode transitions disable parameter editing until the final live readback.
- Colour writes target the current applicable slot only; single-colour effects
  always target Colour 1. Other live effect fields are preserved.
- Mode, effect and Resync writes restore the brightness captured immediately
  before the operation, even on failure. The daemon can briefly set brightness
  internally before restoration; this is not an atomic firmware operation.
- Failed writes are shown in the panel and IPC state, cancel pending dependent
  writes, and trigger live readback. Stale in-flight polls are discarded.

Regression tests use mocked D-Bus calls and do not change lighting. Hardware
confirmation is still needed for each visual effect and boot/suspend policy.
