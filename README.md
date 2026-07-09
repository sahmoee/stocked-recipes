# Stocked recipe feed

A GitHub-hosted recipe feed that Stocked pulls at runtime. Add recipes by editing
`recipes.json` and pushing — no app update needed.

## One-time setup

1. Create a new **public** GitHub repo (e.g. `stocked-recipes`).
2. Add these files: `recipes.json`, `build_recipes.py` (optional), `README.md`.
3. Push. Your raw feed URL is:
   `https://raw.githubusercontent.com/<your-user>/stocked-recipes/main/recipes.json`
4. In the app, open `Stocked/RemoteRecipeFeed.swift` and set:
   `static let feedURLString = "https://raw.githubusercontent.com/<your-user>/stocked-recipes/main/recipes.json"`
5. Build. On the next Discover refresh the app pulls the feed and merges it into the
   recipe database (search, mood finder, Discover, cook ranking all see it).

## Adding recipes later (no app update)

Edit `recipes.json`, commit, push. The app refreshes the feed at most every 6 hours
(and keeps the last copy for offline use).

## Generate a large recipes.json automatically

`build_recipes.py` pulls free sources (DummyJSON + TheMealDB A-Z, ~300+ real recipes with
images and steps) and writes `recipes.json`. Run it on your Mac:

    python3 build_recipes.py
    git add recipes.json && git commit -m "update recipes" && git push

Note: DummyJSON only has 50 recipes total, so the bulk of the volume comes from TheMealDB.
To go beyond that toward hundreds more, keep a `custom_recipes.json` (same format) next to
the script — your entries are merged in and survive every regeneration.

## recipes.json format

An array of objects. Only `title` and `instructions` are required; the rest are optional
but recommended.

    [
      {
        "id": "feed-unique-id",
        "title": "Recipe name",
        "category": "Dinner",
        "area": "Italian",
        "instructions": "Step one\nStep two\nStep three",
        "imageURL": "https://.../photo.jpg",
        "ingredients": ["Ingredient A", "Ingredient B"],
        "measures": ["1 cup", "2 tbsp"],
        "source": "Community Recipes"
      }
    ]

- `instructions`: one step per line (use `\n`).
- `ingredients` and `measures`: same length, index-aligned. If you have no measures, use
  empty strings.
- `source`: the label the recipes appear under inside the app's Sources browser.
- `id`: any stable unique string. Keep it stable so the app can de-duplicate on refresh.
