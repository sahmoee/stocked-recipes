# Recipe Manager (native macOS app)

Build the app: double-click **Build Recipe Manager.app.command** (permanent app, optional
install to /Applications) or **Launch Recipe Manager.command** (build + open).
Needs Xcode/Command Line Tools and `gh` (`brew install gh`).

## First run — pick your folder
The app manages recipes.json in a WORKING FOLDER. On launch it looks for a saved folder,
then ~/Documents/stocked-recipes. If the recipe list is empty, click **Choose Folder…** in
the header and select your stocked-recipes folder. (This is why a double-clicked app can show
nothing: apps launch from "/", not your repo — choosing the folder fixes it, and it's remembered.)

## Features
- Sidebar: searchable recipes with thumbnails; Add Recipe.
- Feed: Rebuild, Fill Images, Validate, Add N New (only recipes not already listed).
- Import from a GitHub repo: paste a repo URL (e.g. https://github.com/dpapathanasiou/recipes)
  and click Import. It reads JSON recipe files directly, and does a best-effort parse of
  plain-text/markdown recipe files. The N field caps how many to pull.
- Drag .json files onto the window to import.
- GitHub: Login, Connect Repo, Commit & Push, Pull, Verify, and branch Merge.

Multiple custom*.json (including custom_github_<repo>.json) are merged on Rebuild.
