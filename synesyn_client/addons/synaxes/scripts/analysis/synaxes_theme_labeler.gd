extends RefCounted
## Provisional theme labels for discovered SynAxes patterns.
##
## Builds short (2–4 word) human-readable labels from distinctive terms in each
## cluster's member texts. Works for both Local (TF-IDF) and Model embedding tiers:
## term statistics always come from member text. When terms are weak, falls back to
## a truncated nearest-to-centroid (or first-item) snippet.
##
## Labels are machine-proposed only — never auto-committed. Callers mark them
## provisional in the Dream Inbox / Closure Editor so humans can rename before Commit.

const MIN_TERM_LEN := 3
const MAX_LABEL_WORDS := 4
const MIN_LABEL_WORDS := 2
const SNIPPET_MAX_CHARS := 42
## Generic function-word list (English-leaning) plus short tokens filtered by length.
## Non-Latin corpora rely on length/frequency heuristics rather than this list.
const _STOPWORDS := {
	"the": true, "and": true, "for": true, "that": true, "with": true, "this": true,
	"from": true, "are": true, "was": true, "were": true, "have": true, "has": true,
	"had": true, "not": true, "but": true, "what": true, "when": true, "where": true,
	"who": true, "how": true, "why": true, "all": true, "any": true, "can": true,
	"into": true, "than": true, "then": true, "them": true, "they": true, "their": true,
	"there": true, "these": true, "those": true, "about": true, "after": true,
	"before": true, "between": true, "over": true, "under": true, "again": true,
	"further": true, "once": true, "here": true, "also": true, "just": true,
	"more": true, "most": true, "other": true, "some": true, "such": true,
	"only": true, "own": true, "same": true, "too": true, "very": true,
	"will": true, "would": true, "could": true, "should": true, "may": true,
	"might": true, "must": true, "shall": true, "being": true, "been": true,
	"does": true, "did": true, "doing": true, "each": true, "few": true,
	"many": true, "much": true, "our": true, "out": true, "its": true, "his": true,
	"her": true, "him": true, "she": true, "you": true, "your": true, "yours": true,
	"ours": true, "itself": true, "themselves": true, "via": true, "per": true,
	"within": true, "without": true, "across": true, "among": true, "against": true,
	"item": true, "items": true, "text": true, "data": true, "note": true,
	"notes": true, "sample": true, "samples": true, "variant": true,
}


## Annotate each cluster pattern with provisional_label / label_source / label_terms.
## Mutates pattern dictionaries in place and returns the same array.
func annotate_patterns(patterns: Array) -> Array:
	var corpus_texts: Array[String] = []
	for p_any in patterns:
		if typeof(p_any) != TYPE_DICTIONARY:
			continue
		var p: Dictionary = p_any
		for it_any in p.get("items", []):
			if typeof(it_any) == TYPE_DICTIONARY:
				corpus_texts.append(str((it_any as Dictionary).get("content", "")))

	var doc_freq: Dictionary = _document_frequencies(corpus_texts)
	var n_docs: int = maxi(corpus_texts.size(), 1)

	for p_any in patterns:
		if typeof(p_any) != TYPE_DICTIONARY:
			continue
		var pattern: Dictionary = p_any
		var ptype: String = str(pattern.get("type", "")).to_lower()
		if ptype != "cluster" and ptype != "pattern" and not ptype.is_empty():
			# Bridges/hubs: leave a short typed label.
			if not pattern.has("provisional_label"):
				pattern["provisional_label"] = ptype.capitalize()
				pattern["label_source"] = "pattern_type"
				pattern["label_terms"] = []
				pattern["label_is_provisional"] = true
			continue
		var labeled: Dictionary = label_cluster(
			pattern.get("items", []),
			doc_freq,
			n_docs,
			pattern.get("position", null),
		)
		pattern["provisional_label"] = str(labeled.get("label", ""))
		pattern["label_source"] = str(labeled.get("source", ""))
		pattern["label_terms"] = labeled.get("terms", [])
		pattern["label_is_provisional"] = true
	return patterns


## Build one provisional label for a cluster's items.
## `doc_freq` / `n_docs` may be empty/0 to compute IDF from the cluster alone.
func label_cluster(
	items: Array,
	doc_freq: Dictionary = {},
	n_docs: int = 0,
	cluster_position: Variant = null,
) -> Dictionary:
	var texts: Array[String] = []
	for it_any in items:
		if typeof(it_any) != TYPE_DICTIONARY:
			continue
		var content: String = str((it_any as Dictionary).get("content", "")).strip_edges()
		if not content.is_empty():
			texts.append(content)
	if texts.is_empty():
		return {
			"label": "Untitled theme",
			"source": "fallback_empty",
			"terms": [],
		}

	var local_freq: Dictionary = doc_freq
	var local_n: int = n_docs
	if local_freq.is_empty() or local_n <= 0:
		local_freq = _document_frequencies(texts)
		local_n = maxi(texts.size(), 1)

	var term_scores: Dictionary = {}
	for text_value in texts:
		var seen_in_doc: Dictionary = {}
		for term in _tokenize(text_value):
			if _is_stopword(term):
				continue
			seen_in_doc[term] = int(seen_in_doc.get(term, 0)) + 1
		for term in seen_in_doc.keys():
			var tf: float = float(seen_in_doc[term])
			var df: float = float(local_freq.get(term, 1))
			var idf: float = log(float(local_n + 1) / (df + 1.0)) + 1.0
			term_scores[term] = float(term_scores.get(term, 0.0)) + tf * idf

	var ranked: Array = []
	for term in term_scores.keys():
		ranked.append({"term": str(term), "score": float(term_scores[term])})
	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("score", 0.0)) > float(b.get("score", 0.0))
	)

	var chosen: Array[String] = []
	for entry_any in ranked:
		if chosen.size() >= MAX_LABEL_WORDS:
			break
		var entry: Dictionary = entry_any
		var term: String = str(entry.get("term", ""))
		if term.is_empty() or _is_stopword(term):
			continue
		# Avoid near-duplicates (learning / learn).
		var is_dup := false
		for existing in chosen:
			if existing.begins_with(term) or term.begins_with(existing):
				is_dup = true
				break
		if is_dup:
			continue
		chosen.append(term)

	if chosen.size() >= MIN_LABEL_WORDS:
		var title_words: Array[String] = []
		for w in chosen:
			title_words.append(_title_case_word(w))
		return {
			"label": " ".join(title_words),
			"source": "machine_proposed_terms",
			"terms": chosen.duplicate(),
		}

	# Fallback: nearest-to-centroid snippet (uses embedding/position vectors when present).
	var snippet: String = _nearest_centroid_snippet(items, cluster_position)
	if snippet.is_empty():
		snippet = texts[0]
	snippet = _truncate_snippet(snippet)
	return {
		"label": snippet,
		"source": "machine_proposed_snippet",
		"terms": chosen.duplicate(),
	}


func _document_frequencies(texts: Array) -> Dictionary:
	var doc_freq: Dictionary = {}
	for text_any in texts:
		var seen: Dictionary = {}
		for term in _tokenize(str(text_any)):
			if seen.has(term):
				continue
			seen[term] = true
			doc_freq[term] = int(doc_freq.get(term, 0)) + 1
	return doc_freq


func _tokenize(text: String) -> Array[String]:
	var lower: String = text.to_lower()
	var tokens: Array[String] = []
	var current := ""
	for ch_idx in range(lower.length()):
		var ch: String = lower[ch_idx]
		if _is_word_char(ch):
			current += ch
		else:
			if current.length() >= MIN_TERM_LEN:
				tokens.append(current)
			current = ""
	if current.length() >= MIN_TERM_LEN:
		tokens.append(current)
	return tokens


func _is_word_char(ch: String) -> bool:
	var code: int = ch.unicode_at(0)
	# ASCII alnum or any non-ASCII letter-ish codepoint (language-agnostic fallback).
	if (code >= 48 and code <= 57) or (code >= 65 and code <= 90) or (code >= 97 and code <= 122):
		return true
	return code > 127


func _is_stopword(term: String) -> bool:
	if term.length() < MIN_TERM_LEN:
		return true
	if _STOPWORDS.has(term):
		return true
	# Pure digits / mostly numeric.
	var digit_count := 0
	for i in range(term.length()):
		var code: int = term.unicode_at(i)
		if code >= 48 and code <= 57:
			digit_count += 1
	if digit_count == term.length():
		return true
	return false


func _title_case_word(word: String) -> String:
	if word.is_empty():
		return word
	# Preserve non-Latin tokens as-is.
	var first_code: int = word.unicode_at(0)
	if first_code > 127:
		return word
	return word.substr(0, 1).to_upper() + word.substr(1)


func _nearest_centroid_snippet(items: Array, cluster_position: Variant) -> String:
	var best_text := ""
	var best_dist := INF
	var has_vectors := false
	var mean: Array = []
	var count := 0
	for it_any in items:
		if typeof(it_any) != TYPE_DICTIONARY:
			continue
		var vec_any: Variant = (it_any as Dictionary).get("vector", [])
		if typeof(vec_any) != TYPE_ARRAY or (vec_any as Array).is_empty():
			continue
		has_vectors = true
		var vec: Array = vec_any
		if mean.is_empty():
			mean.resize(vec.size())
			for i in range(vec.size()):
				mean[i] = 0.0
		if mean.size() != vec.size():
			continue
		for i in range(vec.size()):
			mean[i] = float(mean[i]) + float(vec[i])
		count += 1
	if has_vectors and count > 0:
		for i in range(mean.size()):
			mean[i] = float(mean[i]) / float(count)
		for it_any in items:
			if typeof(it_any) != TYPE_DICTIONARY:
				continue
			var it: Dictionary = it_any
			var vec_any: Variant = it.get("vector", [])
			if typeof(vec_any) != TYPE_ARRAY or (vec_any as Array).size() != mean.size():
				continue
			var dist: float = _l2_distance(mean, vec_any)
			if dist < best_dist:
				best_dist = dist
				best_text = str(it.get("content", ""))
		return best_text

	# Position-based fallback when Pattern Space coords exist on items via embedding path.
	if typeof(cluster_position) == TYPE_VECTOR3:
		# Without per-item positions, use first non-empty content.
		pass
	if not items.is_empty() and typeof(items[0]) == TYPE_DICTIONARY:
		return str((items[0] as Dictionary).get("content", ""))
	return ""


func _l2_distance(a: Array, b: Array) -> float:
	var sum := 0.0
	for i in range(mini(a.size(), b.size())):
		var d: float = float(a[i]) - float(b[i])
		sum += d * d
	return sqrt(sum)


func _truncate_snippet(text: String) -> String:
	var cleaned: String = text.strip_edges().replace("\n", " ")
	while cleaned.find("  ") != -1:
		cleaned = cleaned.replace("  ", " ")
	if cleaned.length() <= SNIPPET_MAX_CHARS:
		return cleaned
	return cleaned.left(SNIPPET_MAX_CHARS - 1).rstrip(" ,.;:") + "…"
