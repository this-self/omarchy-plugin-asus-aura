"""Read-response adapter for the old aura.py entry point only.

Keep cached pre-refactor widgets and existing helper callers functional until
shell restart. New QML always uses the normalized backend/aura_cli.py contract.
There is no legacy operation implementation: all writes use AuraService.
"""
from .busctl import effect_data, power_data


def state(service):
    path, st = service.read_device()
    zone_state = service.zone_reader(path, st.zones)
    return dict(available=True, path=path, brightness=st.brightness, mode=st.mode,
                data=effect_data(st.effect), power=power_data(st.power),
                modes=st.modes, levels=st.levels, deviceType=st.device_type,
                zones=st.zones, powerZones=st.power_zones,
                multizone=None if zone_state == "unknown" else zone_state == "zoned")
