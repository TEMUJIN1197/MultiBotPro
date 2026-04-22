import json
import math
from dataclasses import dataclass
from typing import Any, Dict


@dataclass
class HedgeFeatures:
    progress: float
    gap_norm: float
    spread_norm: float


class HedgeRatioModel:
    def __init__(self, w_progress=0.20, w_gap=0.35, w_spread=-0.10, min_scale=0.5, max_scale=1.8):
        self.w_progress = w_progress
        self.w_gap = w_gap
        self.w_spread = w_spread
        self.min_scale = min_scale
        self.max_scale = max_scale

    def predict_scale(self, f: HedgeFeatures) -> float:
        s = 1.0 + self.w_progress * f.progress + self.w_gap * f.gap_norm + self.w_spread * f.spread_norm
        if math.isnan(s) or math.isinf(s):
            s = 1.0
        return max(self.min_scale, min(self.max_scale, s))

    def to_dict(self) -> Dict[str, Any]:
        return {
            "w_progress": self.w_progress,
            "w_gap": self.w_gap,
            "w_spread": self.w_spread,
            "min_scale": self.min_scale,
            "max_scale": self.max_scale,
            "schema_version": "v3",
        }

    def to_json(self) -> str:
        return json.dumps(self.to_dict(), indent=2)

    @classmethod
    def from_dict(cls, payload: Dict[str, Any]) -> "HedgeRatioModel":
        data = payload or {}
        return cls(
            w_progress=float(data.get("w_progress", 0.20)),
            w_gap=float(data.get("w_gap", 0.35)),
            w_spread=float(data.get("w_spread", -0.10)),
            min_scale=float(data.get("min_scale", 0.5)),
            max_scale=float(data.get("max_scale", 1.8)),
        )

    @classmethod
    def from_json(cls, payload: str) -> "HedgeRatioModel":
        if not payload:
            return cls()
        try:
            data = json.loads(payload)
        except Exception:
            data = {}
        return cls.from_dict(data)


if __name__ == "__main__":
    model = HedgeRatioModel()
    print(model.to_json())
