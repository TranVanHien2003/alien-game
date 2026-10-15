class_name Simulation
extends RefCounted
## Mô phỏng tài nguyên và dân số mỗi năm. Các hằng số nằm trong data/config/game.json.


static func run_year(game: Node) -> void:
	var cfg: Dictionary = Content.config
	var population: float = game.get_stat("population")

	for stat in cfg.get("yearly", {}):
		var rule: Dictionary = cfg.yearly[stat]
		var delta: float = float(rule.get("base", 0.0)) + float(rule.get("per_person", 0.0)) * population
		if rule.has("toward"):
			delta += (float(rule.toward) - game.get_stat(stat)) * float(rule.get("pull", 0.1))
		game.change_stat(stat, delta + ResearchSystem.yearly_bonus(game, stat))

	var pop_cfg: Dictionary = cfg.get("population", {})
	var morale_factor := clampf(game.get_stat("morale") / 50.0, 0.5, 1.5)
	var growth: float = population * (float(pop_cfg.get("birth_rate", 0.0)) * morale_factor - float(pop_cfg.get("death_rate", 0.0)))
	game.change_stat("population", growth)

	for shortage in cfg.get("shortages", []):
		if game.get_stat(shortage.stat) <= float(shortage.at_or_below):
			EventRules.apply(game, shortage.get("effects", {}))
			if shortage.has("population_loss"):
				game.change_stat("population", -ceilf(game.get_stat("population") * float(shortage.population_loss)))
			game.add_log(shortage.get("log", ""))
