# Recipe Manager (native macOS app)

Build: double-click **Build Recipe Manager.app.command** (permanent app, optional install to
/Applications) or **Launch Recipe Manager.command**. Needs Xcode/Command Line Tools + `gh`.

## First run — pick your folder
Click **Choose Folder…** in the header and select your stocked-recipes folder (the one with
recipes.json). It's remembered. (A double-clicked app starts in "/", so it can't find your
recipes until you point it at the folder — this fixes the empty list.)

## What's new
- **Import many file types → JSON:** Import Files… (or drag onto the window) accepts json,
  csv/tsv, txt, md, and html — each is converted to the recipe format. Junk/code files are
  rejected automatically.
- **Cleaner GitHub import:** skips code/data/binary files and oversized files, and validates
  that each entry is actually a recipe (no more "import random" or giant blobs).
- **Push after import:** toggle on to auto commit + push after any import.
- **Configurable app refresh interval:** set "App refresh every N hours" and Set Interval —
  it writes feed_config.json. Apply the included RemoteRecipeFeed.swift to the Stocked app so
  it reads that interval instead of the fixed 6 hours.
- **Big-file safe:** files over 45 MB are kept local and never committed (GitHub rejects
  >100 MB / warns >50 MB). The built .app and caches are git-ignored.
- **Pull fixed:** uses --autostash so local edits don't block a pull.

## Files
- RecipeManager.swift — the app.
- RemoteRecipeFeed.swift — DROP-IN replacement for the Stocked app (reads feed_config.json for
  the refresh interval). Apply it to the Stocked repo, not this one.
