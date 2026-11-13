# OPTIMIZE — vokobe2 (2026-11-13)

Optimization checklist from the complexity annotations. Constraints:
**minimal new code, readability first, output must stay byte-identical**
(verified via `diff -r` of a full site build before/after).

## Worth doing (small, safe, real wins)

* [.] **`group_by_key`: O(i²) → O(i)** (render.ml) — assoc scan + `@`
  rebuild per item; use a Hashtbl keyed by value, then extract groups
  (order: first-seen, as today).

* [.] **`gen_index_pages` / `safe_page`: O(k·n) → O(k+n)** (generator.ml) —
  each generated key does `List.exists` over all pages; build one name
  Hashtbl/set from the base page list up front and share it.

* [.] **Backlinks: O(n²·L) → one O(n·L) pre-pass** (render.ml/main.ml) —
  currently every page render rescans *all* pages' raw text with
  `references_name`. Scan each page's raw ONCE, collect `/slug`
  candidates, check membership against the page index, build
  name → referring-pages map; per render it's a lookup. Keep
  `references_name`'s boundary rule (no `/name-foo` matches for `name`).

* [.] **`get_page_attr` "location": O(l²) → O(l)** (render.ml) —
  `List.nth_opt countries i` inside `List.mapi`; zip the two lists
  (`List.combine` or a fold2) instead.

* [.] **`world_bin_features`: memoize the bbox filter** (roughmap.ml) —
  decode is cached, the O(B) region scan is not; key the existing cache
  pattern by (layer, rounded region) so repeated maps of the same region
  are O(1).

## Deferred (not worth it: code size / risk vs. win at ~980 pages)

* [ ] **`Page.parse_attrs` worst-case O(L²)** — would need a real
  single-pass sexp tokenizer rewrite; only hurts on pathological
  paren-heavy pages. The unbalanced-paren fallback already caps damage.

* [ ] **`assemble_rings` O(w·(w+P))** — algorithmically correct rewrite
  is fiddly; runs once per region, cached in feature cache.

* [ ] **`Json.member` assoc-list O(k)** — callers are memoized
  (`load_json_file`, `world_bin`); k is tiny in practice.

* [ ] **`group_header`/query table HTML string concat** — all linear
  already; Buffer micro-opts would only shave small constants.
