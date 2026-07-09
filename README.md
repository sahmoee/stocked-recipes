# Recipe Feed Manager (GUI)

A single Swift file that opens a real macOS window to manage your Stocked recipe feed and
its GitHub repo — like BuildBuddy, with buttons.

## Run

Put `RecipeManager.swift` and `Launch Recipe Manager.command` in your `stocked-recipes`
folder (the one with `recipes.json`). Then:

- Double-click **Launch Recipe Manager.command**, or
- Terminal: `cd` into the folder and run `swift RecipeManager.swift`

A window opens (no compile step needed; Swift runs it directly).

## What the buttons do

Top row:
- **Rebuild** — pulls DummyJSON + TheMealDB A-Z and merges your customs (~781), live log.
- **Add Recipe** — a form (title, category, area, image, steps, ingredients as
  "amount | ingredient"); saved to recipes.json and custom_recipes.json.
- **Validate** — checks titles, steps, ingredient/measure counts, duplicates.
- **GitHub Login** — opens a Terminal running `gh auth login` (interactive). Complete it,
  then press Verify.
- **repo name + Connect Repo** — inits git if needed and creates/pushes the repo via `gh`
  (or connects an existing remote).
- **Commit & Push** — commits and pushes recipes.json + custom_recipes.json.
- **Pull** — git pull --rebase.
- **Verify** — checks recipes.json, git repo, GitHub login, and remote; prints your feed URL.

The header shows recipe count and GitHub status. The **Feed URL** row has a Copy button —
paste it into `RemoteRecipeFeed.feedURLString` in the app.

Left pane: searchable recipe list with per-row delete. Right pane: live log.

## Requirements

- macOS with the Swift toolchain (Xcode or Command Line Tools).
- `gh` (GitHub CLI) for login/repo creation: `brew install gh`.
