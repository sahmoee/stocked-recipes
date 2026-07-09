#!/usr/bin/env python3
"""
build_extra_sources.py — add the CMU recipe archive to recipes.json, and build pairings.json
(the RecipeNet "which ingredients go well together" function, computed from your recipe corpus).

Run it in your stocked-recipes folder (next to recipes.json):

    python3 build_extra_sources.py            # scrape CMU (capped) + build pairings
    python3 build_extra_sources.py --cmu 400  # cap CMU to 400 new recipes
    python3 build_extra_sources.py --no-cmu   # only rebuild pairings.json
    python3 build_extra_sources.py --pairings-only

Then commit/push (or use the Recipe Manager app's Commit & Push). Stdlib only.

- CMU archive (https://www.cs.cmu.edu/~mjw/recipes/): thousands of classic full recipes.
- pairings.json: for each ingredient, the ingredients most often used alongside it. This is
  the same idea as RecipeNet (schmidtdominik/RecipeNet), but derived from your own recipes,
  so it needs no ML model or 60 MB dataset and works offline.
"""

import sys, json, re, time, html, urllib.request, urllib.parse
from html.parser import HTMLParser
from collections import Counter, defaultdict

CMU_BASE   = "https://www.cs.cmu.edu/~mjw/recipes/"
SOURCE_TAG = "CMU Recipe Archive"
RECIPES    = "recipes.json"
PAIRINGS   = "pairings.json"

# ----------------------------------------------------------------------------- helpers

def get(url, tries=3):
    for i in range(tries):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "stocked-recipe-builder"})
            with urllib.request.urlopen(req, timeout=25) as r:
                return r.read().decode("utf-8", errors="replace")
        except Exception as e:
            time.sleep(0.6 * (i + 1))
    return None

def norm(title):
    return re.sub(r"[^a-z0-9]+", " ", (title or "").lower()).strip()

def load(path):
    try:
        return json.load(open(path))
    except Exception:
        return []

def save(path, data):
    json.dump(data, open(path, "w"), ensure_ascii=False, indent=2)

class LinkGrabber(HTMLParser):
    def __init__(self): super().__init__(); self.links = []
    def handle_starttag(self, tag, attrs):
        if tag == "a":
            for k, v in attrs:
                if k == "href" and v: self.links.append(v)

class TextExtractor(HTMLParser):
    def __init__(self): super().__init__(); self.parts = []; self.title = ""; self._in_title = False; self._skip = 0
    def handle_starttag(self, tag, attrs):
        if tag == "title": self._in_title = True
        if tag in ("script", "style"): self._skip += 1
        if tag in ("br", "p", "tr", "li", "pre", "div"): self.parts.append("\n")
    def handle_endtag(self, tag):
        if tag == "title": self._in_title = False
        if tag in ("script", "style") and self._skip: self._skip -= 1
    def handle_data(self, data):
        if self._in_title: self.title += data
        elif not self._skip: self.parts.append(data)
    def text(self): return html.unescape("".join(self.parts))

def links_from(url):
    page = get(url)
    if not page: return []
    g = LinkGrabber(); g.feed(page)
    out = []
    for href in g.links:
        full = urllib.parse.urljoin(url, href)
        out.append(full)
    return out

# ----------------------------------------------------------------------------- CMU scrape

def parse_recipe(url):
    page = get(url)
    if not page: return None
    ex = TextExtractor(); ex.feed(page)
    raw = ex.text()
    title = (ex.title or "").replace("Recipe", "").strip()
    lines = [l.rstrip() for l in raw.splitlines()]

    # Meal-Master style: a "Title:" line is common; else use <title> or first strong line.
    for l in lines:
        m = re.match(r"\s*Title:\s*(.+)", l, re.I)
        if m: title = m.group(1).strip(); break
    if not title:
        for l in lines:
            if l.strip(): title = l.strip(); break
    if not title or len(title) > 100: return None

    # Split into ingredients (amount-led lines) and instructions.
    ings, instr = [], []
    for l in lines:
        s = l.strip()
        if not s: continue
        if re.match(r"(title|categories|yield|servings|from|date|source)\s*:", s, re.I): continue
        # ingredient line heuristic: starts with a quantity/fraction/measure
        if re.match(r"^[\d¼½¾⅓⅔/.\s]+[a-zA-Z]", s) and len(s) < 60 and not s.endswith(('.', ':')):
            ings.append(re.sub(r"\s+", " ", s))
        else:
            instr.append(s)
    instructions = "\n".join(instr).strip()
    if len(instructions) < 25:  # not a real recipe page (index/redirect/etc.)
        return None
    slug = norm(title).replace(" ", "-")
    return {
        "id": f"cmu-{slug}",
        "title": title,
        "category": "",
        "area": "",
        "instructions": instructions,
        "imageURL": "",
        "ingredients": ings,
        "measures": ["" for _ in ings],
        "source": SOURCE_TAG,
    }

def scrape_cmu(limit):
    print("Scraping the CMU recipe archive…")
    categories = [u for u in links_from(CMU_BASE)
                  if u.startswith(CMU_BASE) and u.endswith("/index.html")]
    print(f"  {len(categories)} categories")
    recipe_urls = []
    seen_urls = set()
    for cat in categories:
        for u in links_from(cat):
            if (u.startswith(CMU_BASE) and u.endswith(".html")
                    and not u.endswith("index.html") and u not in seen_urls):
                seen_urls.add(u); recipe_urls.append(u)
        time.sleep(0.15)
    print(f"  {len(recipe_urls)} recipe pages found")

    out, seen = [], set()
    for i, u in enumerate(recipe_urls):
        if limit and len(out) >= limit: break
        rec = parse_recipe(u)
        if rec:
            k = norm(rec["title"])
            if k and k not in seen:
                seen.add(k); out.append(rec)
        if (i + 1) % 50 == 0:
            print(f"  …{i+1} pages, {len(out)} recipes")
        time.sleep(0.1)
    print(f"  CMU: {len(out)} recipes parsed")
    return out

# ----------------------------------------------------------------------------- pairings

UNITS = {"cup","cups","tbsp","tsp","tablespoon","tablespoons","teaspoon","teaspoons","oz","ounce",
         "ounces","lb","lbs","pound","pounds","g","kg","ml","l","clove","cloves","pinch","dash",
         "can","cans","package","packages","slice","slices","cup","large","small","medium","fresh",
         "chopped","minced","diced","ground","to","taste","of","a","the","and","or"}

def core_ingredient(s):
    s = re.sub(r"[^a-z ]", " ", s.lower())
    words = [w for w in s.split() if w and w not in UNITS and not w.isdigit()]
    # drop trailing descriptors, keep last 1-2 meaningful words (usually the food noun)
    if not words: return ""
    core = words[-1]
    # simple singularize
    if core.endswith("es") and len(core) > 4: core = core[:-2]
    elif core.endswith("s") and len(core) > 3: core = core[:-1]
    return core

def build_pairings(recipes, top=12, min_count=3):
    print("Building pairings.json (ingredient co-occurrence)…")
    co = defaultdict(Counter)
    freq = Counter()
    for r in recipes:
        ings = set()
        for raw in r.get("ingredients", []):
            c = core_ingredient(raw)
            if len(c) >= 3: ings.add(c)
        for a in ings:
            freq[a] += 1
            for b in ings:
                if a != b: co[a][b] += 1
    pairings = {}
    for ing, counter in co.items():
        if freq[ing] < min_count: continue
        best = [[p, n] for p, n in counter.most_common(top) if n >= 2]
        if best: pairings[ing] = best
    save(PAIRINGS, pairings)
    print(f"  Wrote {PAIRINGS}: {len(pairings)} ingredients with suggestions")

# ----------------------------------------------------------------------------- main

def main():
    args = sys.argv[1:]
    cmu_limit = 600
    do_cmu = True
    if "--no-cmu" in args or "--pairings-only" in args: do_cmu = False
    if "--cmu" in args:
        try: cmu_limit = int(args[args.index("--cmu") + 1])
        except Exception: pass

    feed = load(RECIPES)
    before = len(feed)
    seen = set(norm(r["title"]) for r in feed)

    if do_cmu:
        cmu = scrape_cmu(cmu_limit)
        added = 0
        for r in cmu:
            k = norm(r["title"])
            if k and k not in seen:
                seen.add(k); feed.append(r); added += 1
        # keep a custom copy so a Rebuild in the manager doesn't lose them
        save("custom_cmu.json", cmu)
        save(RECIPES, feed)
        print(f"Added {added} new CMU recipes. Feed now {len(feed)} (was {before}).")

    build_pairings(load(RECIPES))
    print("\nDone. Commit & push (or use the Recipe Manager app).")

if __name__ == "__main__":
    main()
