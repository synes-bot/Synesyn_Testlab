extends RefCounted
## Bottom-tab focus policy after Discover / reload.
##
## Pattern Overview (tab 0) is the default focused tab after Discover.
## Propose-themes explicitly queues Closures (tab 2) instead.

const TAB_OVERVIEW := 0
const TAB_CLOSURES := 2


static func bottom_tab_after_discover(focus_closures: bool, tab_count: int) -> int:
	if focus_closures and tab_count > TAB_CLOSURES:
		return TAB_CLOSURES
	if tab_count > TAB_OVERVIEW:
		return TAB_OVERVIEW
	return -1


static func spine_text(steps: Array[String], active_idx: int) -> String:
	## Two-line spine so "Commit" is not clipped in a narrow Pattern Space header.
	var parts: Array[String] = []
	for i in range(steps.size()):
		var step_label: String = steps[i]
		if i == active_idx:
			parts.append("[%s]" % step_label)
		else:
			parts.append(step_label)
	if parts.size() <= 3:
		return " › ".join(parts)
	var line1: Array[String] = []
	var line2: Array[String] = []
	for i in range(parts.size()):
		if i < 3:
			line1.append(parts[i])
		else:
			line2.append(parts[i])
	return "%s\n%s" % [" › ".join(line1), " › ".join(line2)]
