# Recipe Manager (native macOS app)

Build: double-click **Build Recipe Manager.app.command** (permanent app + optional install to
/Applications) or **Launch Recipe Manager.command**. Needs Xcode/Command Line Tools + `gh`.

First run: click **Choose Folder…** and select your stocked-recipes folder (with recipes.json).
It's remembered. (A double-clicked app starts in "/", so pick the folder or the list is empty.)

Feed card:
- Rebuild / Fill Images / Validate; Add N New (only recipes not already listed).
- Import Files… (or drag onto window): json, csv/tsv, txt, md, html → converted to recipes.
- Import from a GitHub repo (skips code/data/oversized files, validates real recipes).
- Remove: match a json url / GitHub repo / website and remove those; or Remove From File…;
  or **Remove No-Image** to drop every recipe without a photo.
- App refresh every N hours + Set Interval (writes feed_config.json; apply the included
  RemoteRecipeFeed.swift to the Stocked app so it honors it).
- "Push after import" auto commits + pushes after imports/removals.

GitHub card: Login, Connect Repo, Commit & Push (upstream-safe, big-file-safe), Pull
(--autostash), Verify, and branch Merge.

RemoteRecipeFeed.swift is for the STOCKED app, not this repo.
