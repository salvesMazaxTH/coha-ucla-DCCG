class_name DomainIconRow
extends HBoxContainer
## Compact, reusable row of the same domain seals shown on card faces.

func setup(domains: Array, icon_size := 18.0, gap := 3) -> DomainIconRow:
	alignment = BoxContainer.ALIGNMENT_CENTER
	add_theme_constant_override("separation", gap)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for domain_value in domains:
		var domain := String(domain_value)
		var badge := CardView.new().setup_domain_badge(domain, icon_size)
		badge.tooltip_text = String(CardDB.essence(domain).get("name", domain))
		add_child(badge)
	return self
