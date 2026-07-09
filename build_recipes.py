#!/usr/bin/env python3
"""
build_recipes.py — generate a big recipes.json for Stocked's remote recipe feed.

Pulls free recipe sources (DummyJSON + TheMealDB A-Z) and writes recipes.json in the app's
OnlineRecipe schema. Optionally merges your own hand-written recipes from custom_recipes.json
so they survive regeneration. Commit the resulting recipes.json to your GitHub repo; the app
pulls it via RemoteRecipeFeed — no app update needed.

Usage:
    python3 build_recipes.py
    # then: git add recipes.json && git commit -m "update recipes" && git push

Requires only the Python standard library.
"""

import json, re, time, urllib.request, urllib.error, os

SOURCE_TAG = "Community Recipes"   # how these show up as a source inside the app
OUTPUT     = "recipes.json"
CUSTOM     = "custom_recipes.json"  # optional: your own recipes, same schema, merged in

def _get(url, tries=3):
    for i in range(tries):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "stocked-recipe-builder"})
            with urllib.request.urlopen(req, timeout=20) as r:
                return json.loads(r.read().decode("utf-8"))
        except Exception as e:
            print(f"  retry {i+1}/{tries} for {url}: {e}")
            time.sleep(1.0 * (i + 1))
    return None

def norm(title):
    return re.sub(r"[^a-z0-9]+", " ", (title or "").lower()).strip()

def add(recipes, seen, rec):
    key = norm(rec["title"])
    if not key or key in seen:
        return
    if not rec["title"].strip() or not rec["instructions"].strip():
        return
    seen.add(key)
    recipes.append(rec)

def from_dummyjson(recipes, seen):
    print("Fetching DummyJSON...")
    data = _get("https://dummyjson.com/recipes?limit=0")
    if not data:
        return
    for r in data.get("recipes", []):
        steps = r.get("instructions", [])
        add(recipes, seen, {
            "id": f"dummyjson-{r.get('id')}",
            "title": r.get("name", ""),
            "category": (r.get("mealType") or [""])[0],
            "area": r.get("cuisine", ""),
            "instructions": "\n".join(steps) if isinstance(steps, list) else str(steps),
            "imageURL": r.get("image", ""),
            "ingredients": r.get("ingredients", []),
            "measures": ["" for _ in r.get("ingredients", [])],
            "source": SOURCE_TAG,
        })
    print(f"  DummyJSON: {len(recipes)} so far")

def from_themealdb(recipes, seen):
    print("Fetching TheMealDB A-Z...")
    for letter in "abcdefghijklmnopqrstuvwxyz":
        data = _get(f"https://www.themealdb.com/api/json/v1/1/search.php?f={letter}")
        meals = (data or {}).get("meals") or []
        for m in meals:
            ings, meas = [], []
            for i in range(1, 21):
                ing = (m.get(f"strIngredient{i}") or "").strip()
                mea = (m.get(f"strMeasure{i}") or "").strip()
                if ing:
                    ings.append(ing)
                    meas.append(mea)
            add(recipes, seen, {
                "id": f"themealdb-{m.get('idMeal')}",
                "title": m.get("strMeal", ""),
                "category": m.get("strCategory", ""),
                "area": m.get("strArea", ""),
                "instructions": (m.get("strInstructions") or "").strip(),
                "imageURL": m.get("strMealThumb", ""),
                "ingredients": ings,
                "measures": meas,
                "source": SOURCE_TAG,
            })
        print(f"  letter {letter}: {len(recipes)} total")
        time.sleep(0.2)   # be polite

def from_custom(recipes, seen):
    if not os.path.exists(CUSTOM):
        return
    print(f"Merging {CUSTOM}...")
    try:
        for rec in json.load(open(CUSTOM)):
            rec.setdefault("category", ""); rec.setdefault("area", "")
            rec.setdefault("imageURL", ""); rec.setdefault("source", SOURCE_TAG)
            rec.setdefault("measures", ["" for _ in rec.get("ingredients", [])])
            add(recipes, seen, rec)
    except Exception as e:
        print(f"  could not read {CUSTOM}: {e}")

def main():
    recipes, seen = [], set()
    from_custom(recipes, seen)      # your recipes win (added first, dedup keeps them)
    from_dummyjson(recipes, seen)
    from_themealdb(recipes, seen)
    with open(OUTPUT, "w") as f:
        json.dump(recipes, f, ensure_ascii=False, indent=2)
    print(f"\nWrote {len(recipes)} recipes to {OUTPUT}")
    print("Next: git add recipes.json && git commit -m 'update recipes' && git push")

if __name__ == "__main__":
    main()
