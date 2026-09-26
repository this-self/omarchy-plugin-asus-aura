"""Named values shared by the hardware adapter and application operations."""
from dataclasses import asdict, dataclass
import re

PATH_RE = r"/xyz/ljones/aura/([A-Za-z0-9]+)_[A-Za-z0-9_]+"


def validate_path(path):
    if not isinstance(path, str) or not re.fullmatch(PATH_RE, path):
        raise ValueError("Invalid ASUS Aura device path")


@dataclass(frozen=True)
class Colour:
    red: int
    green: int
    blue: int

    def __post_init__(self):
        if any(type(v) is not int or not 0 <= v <= 255
               for v in (self.red, self.green, self.blue)):
            raise ValueError("Invalid RGB colour")

    def to_dict(self):
        return asdict(self)


@dataclass(frozen=True)
class Effect:
    mode: int
    zone: int
    colour1: Colour
    colour2: Colour
    speed: str
    direction: str

    def to_dict(self):
        return dict(modeId=self.mode, colour1=self.colour1.to_dict(),
                    colour2=self.colour2.to_dict(), speed=self.speed,
                    direction=self.direction)


@dataclass(frozen=True)
class PowerRow:
    zone: int
    boot: bool
    awake: bool
    sleep: bool
    shutdown: bool


@dataclass(frozen=True)
class DeviceState:
    brightness: int
    mode: int
    effect: Effect
    power: list[PowerRow]
    modes: list[int]
    levels: list[int]
    device_type: int
    zones: list[int]
    power_zones: list[int]
