class_name Difficulty
extends RefCounted
## Độ khó thống nhất cho mọi màn: tăng đều theo khoảng cách địa điểm, năm hiện tại,
## số lần đã hoàn thành nhiệm vụ đó và "tier" riêng của nhiệm vụ. Hệ số ở config.difficulty.


static func level(game: Node, mission: Dictionary, location_id: String) -> float:
	var cfg: Dictionary = Content.config.get("difficulty", {})
	var d := float(cfg.get("base", 1.0))
	d += float(Content.get_entry("locations", location_id).get("distance", 0)) * float(cfg.get("per_distance", 0.5))
	d += game.year * float(cfg.get("per_year", 0.05))
	d += int(game.completed_missions.get(mission.get("id", ""), 0)) * float(cfg.get("per_completion", 0.2))
	d += float(mission.get("tier", 0))
	return clampf(d, 1.0, float(cfg.get("max", 10)))


## Hệ số nhân cho một đại lượng: 1 + hệ_số × (độ_khó − 1)
static func scale(kind: String, d: float) -> float:
	return 1.0 + float(Content.config.get("difficulty", {}).get(kind, 0.0)) * (d - 1.0)


static func label(d: float) -> String:
	var labels: Array = Content.config.get("difficulty", {}).get("labels", ["?"])
	return labels[clampi(int((d - 1.0) / 1.5), 0, labels.size() - 1)]


static func stars(d: float) -> String:
	var n := clampi(int(round(d)), 1, 10)
	return "★".repeat(mini(n, 5)) + ("+" + str(n - 5) if n > 5 else "")
