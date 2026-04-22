import sys
import json

def process_renko(ticks, box_size):
    if not ticks:
        return []
    
    anchor = ticks[0]
    trend_up = True
    bricks = []
    
    for price in ticks:
        while True:
            if trend_up:
                if price >= anchor + box_size:
                    bricks.append({"open": anchor, "close": anchor + box_size, "high": anchor + box_size, "low": anchor})
                    anchor += box_size
                elif price <= anchor - (2 * box_size):
                    bricks.append({"open": anchor - box_size, "close": anchor - (2 * box_size), "high": anchor - box_size, "low": anchor - (2 * box_size)})
                    anchor -= 2 * box_size
                    trend_up = False
                else:
                    break
            else:
                if price <= anchor - box_size:
                    bricks.append({"open": anchor, "close": anchor - box_size, "high": anchor, "low": anchor - box_size})
                    anchor -= box_size
                elif price >= anchor + (2 * box_size):
                    bricks.append({"open": anchor + box_size, "close": anchor + (2 * box_size), "high": anchor + (2 * box_size), "low": anchor + box_size})
                    anchor += 2 * box_size
                    trend_up = True
                else:
                    break
    return bricks

if __name__ == "__main__":
    # Expecting JSON input: {"ticks": [1.123, 1.124, ...], "box_size": 0.001}
    try:
        data = json.load(sys.stdin)
        ticks = data.get("ticks", [])
        box_size = data.get("box_size", 10.0)
        result = process_renko(ticks, box_size)
        print(json.dumps(result))
    except Exception as e:
        print(json.dumps({"error": str(e)}))
