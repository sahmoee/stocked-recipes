// RecipeManager.swift — native macOS app (SwiftUI @main), BuildBuddy-style, to manage Stocked's
// recipe feed and its GitHub repo. Build with "Build Recipe Manager.app.command".
//
// Choose a working folder (remembered). Rebuild from free sources; add only-new by amount;
// add/remove customs; multiple custom*.json; import many file types (json/csv/txt/md/html);
// import from a GitHub repo; REMOVE by matching a json/github/website or by missing image;
// fill images; validate; configurable app refresh interval; full git (login/commit/push/pull/
// merge/verify) with big-file safety.

import SwiftUI
import AppKit
import Foundation
import UniformTypeIdentifiers

// MARK: - Model

struct Recipe: Codable, Identifiable {
    var id: String
    var title: String
    var category: String
    var area: String
    var instructions: String
    var imageURL: String
    var ingredients: [String]
    var measures: [String]
    var source: String
}

let SOURCE_TAG = "Community Recipes"
let RECIPES_FILE = "recipes.json"
let CUSTOM_FILE  = "custom_recipes.json"

// MARK: - IO + helpers

func loadRecipes(_ path: String) -> [Recipe] {
    guard let data = FileManager.default.contents(atPath: path) else { return [] }
    return (try? JSONDecoder().decode([Recipe].self, from: data)) ?? []
}

@discardableResult
func saveRecipes(_ recipes: [Recipe], to path: String) -> Bool {
    let enc = JSONEncoder()
    enc.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes, .sortedKeys]
    guard let data = try? enc.encode(recipes) else { return false }
    return (try? data.write(to: URL(fileURLWithPath: path), options: .atomic)) != nil
}

func normalize(_ title: String) -> String {
    let cleaned = title.lowercased().unicodeScalars.map {
        CharacterSet.alphanumerics.contains($0) ? Character($0) : " "
    }
    return String(cleaned).split(separator: " ").joined(separator: " ")
}

func merge(_ base: [Recipe], _ incoming: [Recipe]) -> [Recipe] {
    var out = base
    var seen = Set(base.map { normalize($0.title) })
    for r in incoming {
        let key = normalize(r.title)
        guard !key.isEmpty, !seen.contains(key) else { continue }
        guard !r.title.trimmingCharacters(in: .whitespaces).isEmpty,
              !r.instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
        seen.insert(key); out.append(r)
    }
    return out
}

func loadAllCustoms() -> [Recipe] {
    let fm = FileManager.default
    let files = ((try? fm.contentsOfDirectory(atPath: fm.currentDirectoryPath)) ?? []).sorted()
    var all: [Recipe] = []
    for f in files where f.lowercased().hasPrefix("custom") && f.lowercased().hasSuffix(".json") {
        all = merge(all, loadRecipes(f))
    }
    return all
}

func customJSONFiles() -> [String] {
    let fm = FileManager.default
    return ((try? fm.contentsOfDirectory(atPath: fm.currentDirectoryPath)) ?? [])
        .filter { $0.lowercased().hasPrefix("custom") && $0.lowercased().hasSuffix(".json") }
}

// MARK: - Networking (synchronous; called off the main thread)

func fetchData(_ urlString: String) -> (Data, HTTPURLResponse)? {
    guard let url = URL(string: urlString) else { return nil }
    let sem = DispatchSemaphore(value: 0)
    var out: (Data, HTTPURLResponse)?
    var req = URLRequest(url: url)
    req.setValue("stocked-recipe-manager", forHTTPHeaderField: "User-Agent")
    req.timeoutInterval = 20
    URLSession.shared.dataTask(with: req) { data, resp, _ in
        if let data = data, let http = resp as? HTTPURLResponse { out = (data, http) }
        sem.signal()
    }.resume()
    _ = sem.wait(timeout: .now() + 25)
    return out
}

func fetchJSON(_ urlString: String) -> Any? {
    guard let (data, _) = fetchData(urlString) else { return nil }
    return try? JSONSerialization.jsonObject(with: data)
}

func fetchDummyJSON() -> [Recipe] {
    guard let root = fetchJSON("https://dummyjson.com/recipes?limit=0") as? [String: Any],
          let arr = root["recipes"] as? [[String: Any]] else { return [] }
    return arr.map { r in
        let steps = (r["instructions"] as? [String]) ?? []
        let ings = (r["ingredients"] as? [String]) ?? []
        return Recipe(id: "dummyjson-\(r["id"] as? Int ?? 0)",
                      title: r["name"] as? String ?? "",
                      category: ((r["mealType"] as? [String])?.first) ?? "",
                      area: r["cuisine"] as? String ?? "",
                      instructions: steps.joined(separator: "\n"),
                      imageURL: r["image"] as? String ?? "",
                      ingredients: ings, measures: ings.map { _ in "" }, source: SOURCE_TAG)
    }
}

func fetchMealDB(progress: (String) -> Void) -> [Recipe] {
    var out: [Recipe] = []
    for letter in "abcdefghijklmnopqrstuvwxyz" {
        guard let root = fetchJSON("https://www.themealdb.com/api/json/v1/1/search.php?f=\(letter)") as? [String: Any],
              let meals = root["meals"] as? [[String: Any]] else { continue }
        for m in meals {
            var ings: [String] = []; var meas: [String] = []
            for i in 1...20 {
                let ing = (m["strIngredient\(i)"] as? String ?? "").trimmingCharacters(in: .whitespaces)
                let mea = (m["strMeasure\(i)"] as? String ?? "").trimmingCharacters(in: .whitespaces)
                if !ing.isEmpty { ings.append(ing); meas.append(mea) }
            }
            out.append(Recipe(id: "themealdb-\(m["idMeal"] as? String ?? UUID().uuidString)",
                              title: m["strMeal"] as? String ?? "",
                              category: m["strCategory"] as? String ?? "",
                              area: m["strArea"] as? String ?? "",
                              instructions: (m["strInstructions"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                              imageURL: m["strMealThumb"] as? String ?? "",
                              ingredients: ings, measures: meas, source: SOURCE_TAG))
        }
        progress("  \(letter): \(out.count) fetched")
    }
    return out
}

// MARK: - Import parsing (many file types) + quality gate

func looksLikeRecipe(_ r: Recipe) -> Bool {
    let t = r.title.lowercased()
    let bad = ["import ", "export ", "def ", "return ", "print(", "#!/", "http://", "https://",
               "==", "();", "np.", "std::", "lc_all", "self.", "0x", "){", "});"]
    if bad.contains(where: { t.contains($0) }) { return false }
    if r.title.count < 3 || r.title.count > 90 { return false }
    if r.title.filter({ $0.isLetter }).count < 3 { return false }
    if r.title.filter({ $0.isNumber }).count > r.title.count / 2 { return false }
    let instr = r.instructions
    if instr.count < 25 || instr.count > 8000 { return false }
    return true
}

func prettifyFilename(_ path: String) -> String {
    let base = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
    let words = base.replacingOccurrences(of: "-", with: " ").replacingOccurrences(of: "_", with: " ")
    return words.split(separator: " ").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
}

func parseTextRecipe(_ text: String, path: String, repo: String) -> Recipe? {
    let lines = text.components(separatedBy: "\n")
    var title = ""
    for l in lines {
        let t = l.trimmingCharacters(in: .whitespaces)
        if t.isEmpty { continue }
        title = t.replacingOccurrences(of: "#", with: "").trimmingCharacters(in: .whitespaces)
        break
    }
    if title.isEmpty || title.count > 90 { title = prettifyFilename(path) }

    var ings: [String] = []; var instr: [String] = []; var mode = 0
    for l in lines {
        let t = l.trimmingCharacters(in: .whitespaces)
        let low = t.lowercased()
        if t.isEmpty { continue }
        if low.contains("ingredient") && t.count < 40 { mode = 1; continue }
        if (low.contains("direction") || low.contains("instruction") || low.contains("method") || low.contains("preparation")) && t.count < 40 { mode = 2; continue }
        let clean = t.replacingOccurrences(of: "- ", with: "").replacingOccurrences(of: "* ", with: "")
        if mode == 1 { ings.append(clean) } else { instr.append(clean) }
    }
    let instructions = instr.joined(separator: "\n")
    guard !instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
    let slug = normalize(title).replacingOccurrences(of: " ", with: "-")
    return Recipe(id: "github-\(repo)-\(slug)", title: title, category: "", area: "",
                  instructions: instructions, imageURL: "", ingredients: ings,
                  measures: ings.map { _ in "" }, source: "GitHub: \(repo)")
}

func stripHTML(_ s: String) -> String {
    let noTags = s.replacingOccurrences(of: "<[^>]+>", with: "\n", options: .regularExpression)
    return noTags.replacingOccurrences(of: "&nbsp;", with: " ").replacingOccurrences(of: "&amp;", with: "&")
}

func recipesFromCSV(_ text: String) -> [Recipe] {
    var rows = text.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    guard rows.count > 1 else { return [] }
    let sep: Character = rows[0].contains("\t") ? "\t" : ","
    func cols(_ line: String) -> [String] {
        var result: [String] = []; var cur = ""; var q = false
        for ch in line {
            if ch == "\"" { q.toggle() }
            else if ch == sep && !q { result.append(cur); cur = "" }
            else { cur.append(ch) }
        }
        result.append(cur)
        return result.map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " \"")) }
    }
    let header = cols(rows.removeFirst()).map { $0.lowercased() }
    func idx(_ names: [String]) -> Int? { for n in names { if let i = header.firstIndex(of: n) { return i } }; return nil }
    let ti = idx(["title","name","recipe"]); let ii = idx(["ingredients","ingredient"])
    let di = idx(["instructions","directions","steps","method"])
    var out: [Recipe] = []
    for row in rows {
        let c = cols(row)
        func at(_ i: Int?) -> String { if let i = i, i < c.count { return c[i] }; return "" }
        let title = at(ti)
        let instr = at(di).isEmpty ? row : at(di)
        guard !title.isEmpty, !instr.isEmpty else { continue }
        let ings = at(ii).components(separatedBy: CharacterSet(charactersIn: ";|"))
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let slug = normalize(title).replacingOccurrences(of: " ", with: "-")
        out.append(Recipe(id: "csv-\(slug)", title: title, category: "", area: "", instructions: instr,
                          imageURL: "", ingredients: ings, measures: ings.map { _ in "" }, source: "Imported"))
    }
    return out
}

func recipesFromFile(_ url: URL) -> [Recipe] {
    guard let data = try? Data(contentsOf: url), data.count < 8_000_000 else { return [] }
    let ext = url.pathExtension.lowercased()
    if ext == "json" {
        if let recs = try? JSONDecoder().decode([Recipe].self, from: data) { return recs }
        if let r = try? JSONDecoder().decode(Recipe.self, from: data) { return [r] }
        return []
    }
    guard let text = String(data: data, encoding: .utf8) else { return [] }
    if ext == "csv" || ext == "tsv" { return recipesFromCSV(text) }
    let body = (ext == "html" || ext == "htm") ? stripHTML(text) : text
    if var r = parseTextRecipe(body, path: url.lastPathComponent, repo: "file") {
        r.source = "Imported"
        r.id = "file-\(normalize(r.title).replacingOccurrences(of: " ", with: "-"))"
        return [r]
    }
    return []
}

// MARK: - GitHub repo import

func parseOwnerRepo(_ urlString: String) -> (String, String)? {
    guard let r = urlString.range(of: "github.com/") else { return nil }
    let parts = urlString[r.upperBound...].split(separator: "/")
    guard parts.count >= 2 else { return nil }
    var repo = String(parts[1])
    if repo.hasSuffix(".git") { repo = String(repo.dropLast(4)) }
    return (String(parts[0]), repo)
}

func githubDefaultBranch(_ owner: String, _ repo: String) -> String {
    if let root = fetchJSON("https://api.github.com/repos/\(owner)/\(repo)") as? [String: Any],
       let b = root["default_branch"] as? String { return b }
    return "main"
}

func githubRecipes(repoURL: String, limit: Int?, log: @escaping (String) -> Void) -> [Recipe] {
    guard let (owner, repo) = parseOwnerRepo(repoURL) else { log("  Invalid GitHub URL."); return [] }
    let branch = githubDefaultBranch(owner, repo)
    log("  \(owner)/\(repo) @ \(branch) — listing files…")
    guard let tree = fetchJSON("https://api.github.com/repos/\(owner)/\(repo)/git/trees/\(branch)?recursive=1") as? [String: Any],
          let nodes = tree["tree"] as? [[String: Any]] else { log("  Could not read repo tree (private or API rate-limited)."); return [] }

    let codeExt = [".py",".ipynb",".sh",".npz",".pkl",".pickle",".h5",".bin",".dat",".model",".cfg",
                   ".ini",".png",".jpg",".jpeg",".gif",".svg",".css",".js",".html",".htm",".yml",
                   ".yaml",".toml",".lock",".xml",".csv",".tsv",".zip",".gz",".pdf",".map",".ppm"]
    var paths: [String] = []
    for n in nodes {
        guard (n["type"] as? String) == "blob", let path = n["path"] as? String else { continue }
        let low = path.lowercased()
        let name = (low as NSString).lastPathComponent
        if codeExt.contains(where: { low.hasSuffix($0) }) { continue }
        if name.contains("license") || name.contains("readme") || name.contains("contributing")
            || name.contains("makefile") || name.contains("requirement") || name.hasPrefix(".") { continue }
        paths.append(path)
    }
    log("  \(paths.count) candidate files — fetching…")

    var out: [Recipe] = []; var seen = Set<String>()
    func addUnique(_ r: Recipe) {
        let k = normalize(r.title)
        guard !k.isEmpty, !seen.contains(k), looksLikeRecipe(r) else { return }
        seen.insert(k); out.append(r)
    }
    for path in paths {
        if let limit = limit, out.count >= limit { break }
        let enc = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
        guard let (data, http) = fetchData("https://raw.githubusercontent.com/\(owner)/\(repo)/\(branch)/\(enc)"),
              (200..<300).contains(http.statusCode), data.count < 300_000 else { continue }
        if path.lowercased().hasSuffix(".json") {
            if let recs = try? JSONDecoder().decode([Recipe].self, from: data) { recs.forEach(addUnique); continue }
            if let r = try? JSONDecoder().decode(Recipe.self, from: data) { addUnique(r); continue }
        }
        if let text = String(data: data, encoding: .utf8), let r = parseTextRecipe(text, path: path, repo: repo) {
            addUnique(r)
        }
    }
    return out
}

// MARK: - Shell / git / gh

@discardableResult
func runShell(_ cmd: String, _ args: [String]) -> String {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    task.arguments = [cmd] + args
    let pipe = Pipe(); task.standardOutput = pipe; task.standardError = pipe
    do { try task.run() } catch { return "\(cmd): \(error.localizedDescription)" }
    task.waitUntilExit()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    return (String(data: data, encoding: .utf8) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
}

func runGit(_ args: [String]) -> String { runShell("git", args) }
func isGitRepo() -> Bool { runGit(["rev-parse", "--is-inside-work-tree"]).contains("true") }
func remoteURL() -> String { runGit(["config", "--get", "remote.origin.url"]) }

/// Writes .gitignore, keeps oversized junk out, then commits + pushes (upstream-safe).
func gitCommitPushSync(log: @escaping (String) -> Void) {
    guard isGitRepo() else { log("Not a git repo — use Connect Repo."); return }
    let ignore = ".DS_Store\n*.app/\n.build/\n__pycache__/\n*.pyc\n"
    try? ignore.write(toFile: ".gitignore", atomically: true, encoding: .utf8)
    _ = runGit(["rm", "-r", "--cached", "--ignore-unmatch", "--quiet", "RecipeManager.app", ".build", "__pycache__"])
    if let items = try? FileManager.default.contentsOfDirectory(atPath: ".") {
        for f in items {
            if let attrs = try? FileManager.default.attributesOfItem(atPath: f),
               let sz = attrs[.size] as? Int, sz > 45_000_000 {
                _ = runGit(["rm", "--cached", "--ignore-unmatch", "--quiet", f])
                if let h = try? FileHandle(forWritingTo: URL(fileURLWithPath: ".gitignore")) {
                    h.seekToEndOfFile(); h.write((f + "\n").data(using: .utf8)!); try? h.close()
                }
                log("Skipped oversized file \(f) (\(sz / 1_000_000) MB) — kept locally, not pushed.")
            }
        }
    }
    let count = loadRecipes(RECIPES_FILE).count
    _ = runGit(["add", "-A"])
    let commit = runGit(["commit", "-m", "Update recipes (\(count) total)"])
    log(commit.isEmpty ? "Nothing new to commit." : commit)
    if remoteURL().isEmpty { log("No remote — use Connect Repo."); return }
    let branch = runGit(["rev-parse", "--abbrev-ref", "HEAD"])
    let upstream = runGit(["rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}"])
    let needsUpstream = upstream.isEmpty || upstream.lowercased().contains("fatal") || upstream.lowercased().contains("no upstream")
    let push = needsUpstream ? runGit(["push", "-u", "origin", branch.isEmpty ? "main" : branch]) : runGit(["push"])
    log(push.isEmpty ? "Pushed." : push)
}

func ghUser() -> String? {
    let s = runShell("gh", ["auth", "status"])
    if let r = s.range(of: "account ") {
        let tail = s[r.upperBound...]
        if let name = tail.split(whereSeparator: { $0 == " " || $0 == "\n" }).first.map(String.init), !name.isEmpty { return name }
    }
    if s.lowercased().contains("logged in") { return "connected" }
    return nil
}

func rawFeedURL() -> String? {
    var url = remoteURL(); guard !url.isEmpty else { return nil }
    url = url.replacingOccurrences(of: "git@github.com:", with: "https://github.com/")
    if url.hasSuffix(".git") { url = String(url.dropLast(4)) }
    guard let r = url.range(of: "github.com/") else { return nil }
    return "https://raw.githubusercontent.com/\(String(url[r.upperBound...]))/main/\(RECIPES_FILE)"
}

// MARK: - Image resolution (free, no key)

func foodishCategory(title: String, category: String) -> String? {
    let t = (title + " " + category).lowercased()
    if t.contains("dessert") || t.contains("cake") || t.contains("cookie") || t.contains("pie") || t.contains("sweet") { return "dessert" }
    if t.contains("pasta") || t.contains("noodle") || t.contains("spaghetti") || t.contains("lasagna") { return "pasta" }
    if t.contains("pizza") { return "pizza" }
    if t.contains("rice") || t.contains("risotto") || t.contains("biryani") { return "rice" }
    if t.contains("burger") || t.contains("sandwich") || t.contains("taco") || t.contains("wrap") { return "burger" }
    if t.contains("curry") || t.contains("masala") || t.contains("tikka") { return "butter-chicken" }
    if t.contains("samosa") || t.contains("pakora") { return "samosa" }
    return nil
}

func resolveImage(title: String, category: String) -> String? {
    if let q = title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
       let root = fetchJSON("https://www.themealdb.com/api/json/v1/1/search.php?s=\(q)") as? [String: Any],
       let meals = root["meals"] as? [[String: Any]],
       let thumb = meals.first?["strMealThumb"] as? String, !thumb.isEmpty {
        return thumb
    }
    if let cat = foodishCategory(title: title, category: category),
       let root = fetchJSON("https://foodish-api.com/api/images/\(cat)") as? [String: Any],
       let img = root["image"] as? String, !img.isEmpty {
        return img
    }
    return nil
}

func missingImageCount(_ rs: [Recipe]) -> Int {
    rs.filter { $0.imageURL.trimmingCharacters(in: .whitespaces).isEmpty }.count
}

// MARK: - Store

@MainActor
final class Store: ObservableObject {
    @Published var recipes: [Recipe] = []
    @Published var log = ""
    @Published var busy = false
    @Published var busyLabel = ""
    @Published var gh = "checking…"
    @Published var remote = ""
    @Published var feedURL = ""
    @Published var search = ""
    @Published var addAmount = "100"
    @Published var currentBranch = ""
    @Published var folder = ""
    @Published var githubURL = "https://github.com/dpapathanasiou/recipes"
    @Published var refreshHours = "6"
    @Published var pushAfterImport = true
    @Published var removeSource = ""

    var filtered: [Recipe] {
        guard !search.isEmpty else { return recipes }
        let k = normalize(search)
        return recipes.filter { normalize($0.title).contains(k) }
    }

    func out(_ s: String) { log += (log.isEmpty ? "" : "\n") + s }

    func restoreFolder() {
        let saved = UserDefaults.standard.string(forKey: "workingFolder") ?? ""
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [saved, "\(home)/Documents/stocked-recipes", "\(home)/Documents/stocked-recipes-repo", FileManager.default.currentDirectoryPath]
        for c in candidates where !c.isEmpty && FileManager.default.fileExists(atPath: "\(c)/\(RECIPES_FILE)") {
            FileManager.default.changeCurrentDirectoryPath(c); folder = c; break
        }
        if folder.isEmpty { folder = FileManager.default.currentDirectoryPath }
    }

    func setFolder(_ path: String) {
        guard !path.isEmpty else { return }
        FileManager.default.changeCurrentDirectoryPath(path)
        folder = path
        UserDefaults.standard.set(path, forKey: "workingFolder")
        out("Working folder: \(path)")
        reload(); refreshStatus()
    }

    func reload() {
        recipes = loadRecipes(RECIPES_FILE)
        remote = remoteURL()
        feedURL = rawFeedURL() ?? ""
        currentBranch = isGitRepo() ? runGit(["rev-parse", "--abbrev-ref", "HEAD"]) : ""
        if let data = FileManager.default.contents(atPath: "feed_config.json"),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let h = obj["refreshHours"] as? Int { refreshHours = String(h) }
    }

    func refreshStatus() {
        background("Checking GitHub…") {
            let u = ghUser()
            DispatchQueue.main.async {
                self.gh = u ?? "not logged in"
                self.reload()
                self.out("Folder \(self.folder) · \(self.recipes.count) recipes · GitHub \(self.gh)")
            }
        }
    }

    private func background(_ label: String, _ work: @escaping () -> Void) {
        busy = true; busyLabel = label
        DispatchQueue.global(qos: .userInitiated).async {
            work()
            DispatchQueue.main.async { self.busy = false; self.busyLabel = ""; self.reload() }
        }
    }

    func rebuild() {
        background("Rebuilding feed…") {
            DispatchQueue.main.async { self.out("Rebuilding from free sources + your customs…") }
            var recipes = loadAllCustoms()
            recipes = merge(recipes, fetchDummyJSON())
            DispatchQueue.main.async { self.out("  DummyJSON merged (\(recipes.count))") }
            recipes = merge(recipes, fetchMealDB { line in DispatchQueue.main.async { self.out(line) } })
            var filled = 0
            for i in recipes.indices where recipes[i].imageURL.trimmingCharacters(in: .whitespaces).isEmpty {
                if let url = resolveImage(title: recipes[i].title, category: recipes[i].category) { recipes[i].imageURL = url; filled += 1 }
            }
            let ok = saveRecipes(recipes, to: RECIPES_FILE)
            DispatchQueue.main.async {
                self.out(ok ? "Wrote \(recipes.count) recipes to \(RECIPES_FILE)." : "! write failed")
                if filled > 0 { self.out("Filled \(filled) missing image(s).") }
            }
        }
    }

    func addNewFromSources(limit: Int?) {
        background("Adding new recipes…") {
            let existing = Set(loadRecipes(RECIPES_FILE).map { normalize($0.title) })
            DispatchQueue.main.async { self.out("Fetching sources for new recipes…") }
            var pool = fetchDummyJSON()
            pool += fetchMealDB { line in DispatchQueue.main.async { self.out(line) } }
            var seen = existing; var newOnes: [Recipe] = []
            for rec in pool {
                let k = normalize(rec.title)
                guard !k.isEmpty, !seen.contains(k),
                      !rec.instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                seen.insert(k)
                var r2 = rec
                if r2.imageURL.isEmpty, let url = resolveImage(title: r2.title, category: r2.category) { r2.imageURL = url }
                newOnes.append(r2)
                if let limit = limit, newOnes.count >= limit { break }
            }
            var feed = loadRecipes(RECIPES_FILE); feed += newOnes
            _ = saveRecipes(feed, to: RECIPES_FILE)
            DispatchQueue.main.async { self.out("Added \(newOnes.count) NEW recipe(s). Feed now \(feed.count).") }
        }
    }

    func importGitHub(_ url: String, limit: Int?) {
        background("Importing from GitHub…") {
            var recs = githubRecipes(repoURL: url, limit: limit) { line in DispatchQueue.main.async { self.out(line) } }
            for i in recs.indices where recs[i].imageURL.isEmpty {
                if let u = resolveImage(title: recs[i].title, category: recs[i].category) { recs[i].imageURL = u }
            }
            var feed = loadRecipes(RECIPES_FILE); let before = feed.count
            feed = merge(feed, recs)
            _ = saveRecipes(feed, to: RECIPES_FILE)
            let repo = parseOwnerRepo(url)?.1 ?? "import"
            _ = saveRecipes(merge(loadRecipes("custom_github_\(repo).json"), recs), to: "custom_github_\(repo).json")
            let added = feed.count - before
            DispatchQueue.main.async { self.out("Imported \(added) new recipe(s) from GitHub. Feed now \(feed.count).") }
            if self.pushAfterImport && added > 0 { gitCommitPushSync { line in DispatchQueue.main.async { self.out(line) } } }
        }
    }

    func importFiles(_ urls: [URL]) {
        background("Importing files…") {
            var feed = loadRecipes(RECIPES_FILE); let before = feed.count; var files = 0
            for url in urls {
                let recs = recipesFromFile(url).filter { looksLikeRecipe($0) }
                guard !recs.isEmpty else {
                    DispatchQueue.main.async { self.out("  \(url.lastPathComponent): no recipes recognized") }
                    continue
                }
                files += 1; feed = merge(feed, recs)
                let name = "custom_" + url.deletingPathExtension().lastPathComponent.replacingOccurrences(of: " ", with: "_") + ".json"
                _ = saveRecipes(merge(loadRecipes(name), recs), to: name)
                DispatchQueue.main.async { self.out("  \(url.lastPathComponent): \(recs.count) recipe(s)") }
            }
            _ = saveRecipes(feed, to: RECIPES_FILE)
            let added = feed.count - before
            DispatchQueue.main.async { self.out("Imported \(added) new recipe(s) from \(files) file(s).") }
            if self.pushAfterImport && added > 0 { gitCommitPushSync { line in DispatchQueue.main.async { self.out(line) } } }
        }
    }

    func saveInterval() {
        let n = max(1, Int(refreshHours) ?? 6)
        if let data = try? JSONSerialization.data(withJSONObject: ["refreshHours": n], options: [.prettyPrinted]) {
            try? data.write(to: URL(fileURLWithPath: "feed_config.json"))
            out("Set feed refresh to \(n) hour(s). Commit & Push to publish — the app reads feed_config.json.")
        }
    }

    // MARK: Remove — by matching a source, or by missing image

    func removeNoImage() {
        background("Removing recipes with no image…") {
            var feed = loadRecipes(RECIPES_FILE); let before = feed.count
            feed.removeAll { $0.imageURL.trimmingCharacters(in: .whitespaces).isEmpty }
            _ = saveRecipes(feed, to: RECIPES_FILE)
            for f in customJSONFiles() {
                var cs = loadRecipes(f); cs.removeAll { $0.imageURL.trimmingCharacters(in: .whitespaces).isEmpty }; _ = saveRecipes(cs, to: f)
            }
            let removed = before - feed.count
            let push = self.pushAfterImport
            DispatchQueue.main.async { self.out("Removed \(removed) recipe(s) with no image. Feed now \(feed.count).") }
            if push && removed > 0 { gitCommitPushSync { line in DispatchQueue.main.async { self.out(line) } } }
        }
    }

    func removeFromSource(_ input: String) {
        let src = input.trimmingCharacters(in: .whitespaces)
        guard !src.isEmpty else { return }
        background("Finding matches…") {
            var titles = Set<String>(); var label = "source"
            if src.lowercased().contains("github.com") {
                let recs = githubRecipes(repoURL: src, limit: 3000) { line in DispatchQueue.main.async { self.out(line) } }
                titles = Set(recs.map { normalize($0.title) }); label = "GitHub repo"
            } else if let (data, http) = fetchData(src), (200..<300).contains(http.statusCode) {
                if src.lowercased().hasSuffix(".json"), let recs = try? JSONDecoder().decode([Recipe].self, from: data) {
                    titles = Set(recs.map { normalize($0.title) }); label = "JSON"
                } else if let text = String(data: data, encoding: .utf8) {
                    let pageNorm = normalize(stripHTML(text))
                    let feed = loadRecipes(RECIPES_FILE)
                    titles = Set(feed.map { normalize($0.title) }.filter { $0.count >= 4 && pageNorm.contains($0) })
                    label = "website"
                }
            }
            self.applyRemoval(titles, label: label)
        }
    }

    func removeFromFile(_ urls: [URL]) {
        background("Finding matches…") {
            var titles = Set<String>()
            for url in urls { titles.formUnion(recipesFromFile(url).map { normalize($0.title) }) }
            self.applyRemoval(titles, label: "file(s)")
        }
    }

    private func applyRemoval(_ titles: Set<String>, label: String) {
        guard !titles.isEmpty else { DispatchQueue.main.async { self.out("No matching titles found for \(label).") }; return }
        var feed = loadRecipes(RECIPES_FILE); let before = feed.count
        feed.removeAll { titles.contains(normalize($0.title)) }
        _ = saveRecipes(feed, to: RECIPES_FILE)
        for f in customJSONFiles() {
            var cs = loadRecipes(f); cs.removeAll { titles.contains(normalize($0.title)) }; _ = saveRecipes(cs, to: f)
        }
        let removed = before - feed.count
        let push = self.pushAfterImport
        DispatchQueue.main.async { self.out("Removed \(removed) recipe(s) matching \(label). Feed now \(feed.count).") }
        if push && removed > 0 { gitCommitPushSync { line in DispatchQueue.main.async { self.out(line) } } }
    }

    func fillMissingImages() {
        background("Filling images…") {
            var rs = loadRecipes(RECIPES_FILE); var filled = 0
            for i in rs.indices where rs[i].imageURL.trimmingCharacters(in: .whitespaces).isEmpty {
                let t = rs[i].title
                if let url = resolveImage(title: rs[i].title, category: rs[i].category) {
                    rs[i].imageURL = url; filled += 1
                    DispatchQueue.main.async { self.out("  + \(t)") }
                }
            }
            _ = saveRecipes(rs, to: RECIPES_FILE)
            DispatchQueue.main.async { self.out("Filled \(filled) image(s). Remaining without image: \(missingImageCount(rs)).") }
        }
    }

    func validate() {
        let rs = loadRecipes(RECIPES_FILE); var problems = 0; var seen = Set<String>()
        for (i, r) in rs.enumerated() {
            if r.title.trimmingCharacters(in: .whitespaces).isEmpty { out("  #\(i): empty title"); problems += 1 }
            if r.instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { out("  #\(i) \(r.title): no steps"); problems += 1 }
            if r.ingredients.count != r.measures.count { out("  #\(i) \(r.title): ingredient/measure mismatch"); problems += 1 }
            let k = normalize(r.title)
            if seen.contains(k) { out("  #\(i) \(r.title): duplicate"); problems += 1 }
            seen.insert(k)
        }
        out(problems == 0 ? "Valid — \(rs.count) recipes, no problems." : "\(problems) problem(s) found.")
        let missing = missingImageCount(rs)
        if missing > 0 { out("\(missing) recipe(s) have no image — use Fill Images or Remove No-Image.") }
    }

    func addRecipe(_ r: Recipe) {
        _ = saveRecipes(merge(loadRecipes(CUSTOM_FILE), [r]), to: CUSTOM_FILE)
        let feed = merge(loadRecipes(RECIPES_FILE), [r]); _ = saveRecipes(feed, to: RECIPES_FILE)
        reload(); out("Added \"\(r.title)\". Feed now \(recipes.count).")
    }

    func remove(_ r: Recipe) {
        var feed = loadRecipes(RECIPES_FILE); feed.removeAll { normalize($0.title) == normalize(r.title) }
        _ = saveRecipes(feed, to: RECIPES_FILE)
        for f in customJSONFiles() {
            var cs = loadRecipes(f); cs.removeAll { normalize($0.title) == normalize(r.title) }; _ = saveRecipes(cs, to: f)
        }
        reload(); out("Removed \"\(r.title)\". Feed now \(recipes.count).")
    }

    func ghLogin() {
        out("Opening a Terminal for GitHub login — finish it there, then press Verify.")
        runShell("osascript", ["-e", "tell application \"Terminal\" to activate",
                               "-e", "tell application \"Terminal\" to do script \"gh auth login\""])
    }

    func connectRepo(name: String) {
        background("Connecting repo…") {
            if !isGitRepo() {
                DispatchQueue.main.async { self.out("git init…") }
                _ = runGit(["init"]); _ = runGit(["add", "-A"])
                _ = runGit(["commit", "-m", "Initial recipe feed"]); _ = runGit(["branch", "-M", "main"])
            }
            if remoteURL().isEmpty {
                let repo = name.trimmingCharacters(in: .whitespaces).isEmpty ? "stocked-recipes" : name
                DispatchQueue.main.async { self.out("Creating \(repo) via gh and pushing…") }
                let o = runShell("gh", ["repo", "create", repo, "--public", "--source=.", "--remote=origin", "--push"])
                DispatchQueue.main.async { self.out(o.isEmpty ? "(no output)" : o) }
            } else {
                DispatchQueue.main.async { self.out("Remote already set: \(remoteURL())") }
            }
            if let raw = rawFeedURL() { DispatchQueue.main.async { self.out("Feed URL: \(raw)") } }
        }
    }

    func commitPush() {
        background("Committing & pushing…") {
            gitCommitPushSync { line in DispatchQueue.main.async { self.out(line) } }
        }
    }

    func pull() {
        background("Pulling…") {
            let o = runGit(["pull", "--rebase", "--autostash"])
            DispatchQueue.main.async { self.out(o.isEmpty ? "Up to date." : o) }
        }
    }

    func mergeBranch(_ name: String) {
        let branch = name.trimmingCharacters(in: .whitespaces)
        guard !branch.isEmpty else { return }
        background("Merging \(branch)…") {
            guard isGitRepo() else { DispatchQueue.main.async { self.out("Not a git repo.") }; return }
            let branches = runGit(["branch", "--all"])
            DispatchQueue.main.async { self.out("Branches:\n\(branches)") }
            let o = runGit(["merge", "--no-edit", branch])
            DispatchQueue.main.async { self.out(o.isEmpty ? "Merged \(branch)." : o) }
        }
    }

    func verify() {
        background("Verifying…") {
            var lines = ["── Verify ──", "Folder: \(self.folder)"]
            lines.append(FileManager.default.fileExists(atPath: RECIPES_FILE) ? "✓ recipes.json present (\(loadRecipes(RECIPES_FILE).count))" : "✗ recipes.json missing — Choose Folder")
            lines.append(isGitRepo() ? "✓ git repo" : "✗ not a git repo (use Connect Repo)")
            lines.append(ghUser() != nil ? "✓ GitHub logged in (\(ghUser() ?? ""))" : "✗ GitHub not logged in (use Login)")
            lines.append(remoteURL().isEmpty ? "✗ no remote set" : "✓ remote: \(remoteURL())")
            if let raw = rawFeedURL() { lines.append("→ feed URL: \(raw)") }
            DispatchQueue.main.async { lines.forEach { self.out($0) } }
        }
    }
}

// MARK: - UI (BuildBuddy-style)

@main
struct RecipeManagerApp: App {
    @StateObject private var store = Store()
    var body: some Scene {
        WindowGroup("Recipe Feed Manager") {
            ContentView().environmentObject(store).frame(minWidth: 900, minHeight: 600)
        }
        .windowStyle(.titleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1160, height: 780)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Rebuild Feed") { store.rebuild() }.keyboardShortcut("r", modifiers: [.command])
                Button("Add New From Sources") { store.addNewFromSources(limit: Int(store.addAmount)) }.keyboardShortcut("n", modifiers: [.command])
                Button("Commit & Push") { store.commitPush() }.keyboardShortcut("p", modifiers: [.command, .shift])
                Button("Pull") { store.pull() }.keyboardShortcut("l", modifiers: [.command])
            }
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var store: Store
    @State private var branchToMerge = ""
    @State private var repoName = "stocked-recipes"
    @State private var showAdd = false

    var body: some View {
        NavigationSplitView {
            Sidebar(showAdd: $showAdd).navigationSplitViewColumnWidth(min: 250, ideal: 320, max: 460)
        } detail: {
            DetailView(branchToMerge: $branchToMerge, repoName: $repoName, chooseFolder: chooseFolder)
        }
        .tint(.accentColor)
        .onAppear { store.restoreFolder(); store.reload(); store.refreshStatus() }
        .sheet(isPresented: $showAdd) { AddRecipeSheet { store.addRecipe($0) } }
        .onDrop(of: [UTType.fileURL], isTargeted: nil) { providers in handleDrop(providers); return true }
        .overlay(alignment: .top) {
            if store.busy {
                HStack(spacing: 10) { ProgressView().controlSize(.small); Text(store.busyLabel).font(.callout) }
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(.regularMaterial, in: Capsule())
                    .overlay(Capsule().strokeBorder(.tint.opacity(0.4), lineWidth: 1))
                    .padding(.top, 10)
            }
        }
        .animation(.easeOut(duration: 0.15), value: store.busy)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false
        panel.title = "Choose your stocked-recipes folder (with recipes.json)"
        if panel.runModal() == .OK, let url = panel.url { store.setFolder(url.path) }
    }

    private func handleDrop(_ providers: [NSItemProvider]) {
        var urls: [URL] = []
        let group = DispatchGroup()
        for pr in providers {
            group.enter()
            _ = pr.loadObject(ofClass: URL.self) { url, _ in
                if let url = url { urls.append(url) }
                group.leave()
            }
        }
        group.notify(queue: .main) { if !urls.isEmpty { store.importFiles(urls) } }
    }
}

struct Sidebar: View {
    @EnvironmentObject var store: Store
    @Binding var showAdd: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary).font(.caption)
                TextField("Search recipes", text: $store.search).textFieldStyle(.plain).font(.callout)
                if !store.search.isEmpty {
                    Button { store.search = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.borderless).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal, 10).padding(.top, 8).padding(.bottom, 4)

            List {
                Section("\(store.filtered.count) recipes") { ForEach(store.filtered) { r in row(r) } }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)

            Divider()
            HStack(spacing: 8) {
                Button { showAdd = true } label: { Label("Add Recipe", systemImage: "plus.circle.fill") }
                    .buttonStyle(.borderless)
                Spacer()
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
        }
        .background(.regularMaterial)
    }

    @ViewBuilder private func row(_ r: Recipe) -> some View {
        HStack(spacing: 10) {
            AsyncImage(url: URL(string: r.imageURL)) { phase in
                switch phase {
                case .success(let img): img.resizable().aspectRatio(contentMode: .fill)
                default: ZStack { Color.gray.opacity(0.12); Image(systemName: "photo").font(.caption).foregroundStyle(.secondary) }
                }
            }
            .frame(width: 40, height: 40).clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(r.title).fontWeight(.medium).lineLimit(1)
                Text([r.area, r.category].filter { !$0.isEmpty }.joined(separator: " · ")).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            Button(role: .destructive) { store.remove(r) } label: { Image(systemName: "trash") }
                .buttonStyle(.borderless).foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

struct DetailView: View {
    @EnvironmentObject var store: Store
    @Binding var branchToMerge: String
    @Binding var repoName: String
    var chooseFolder: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                headerCard
                HStack(alignment: .top, spacing: 14) { feedSection; gitSection }
                logCard
            }
            .padding(16)
        }
    }

    var headerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "fork.knife.circle.fill").font(.system(size: 22)).foregroundStyle(.tint)
                Text("Recipe Feed Manager").font(.title2.bold())
                Spacer()
                chip("Recipes", "\(store.recipes.count)", "list.bullet")
                chip("GitHub", store.gh, "person.crop.circle")
                chip("Branch", store.currentBranch.isEmpty ? "—" : store.currentBranch, "arrow.triangle.branch")
            }
            HStack(spacing: 6) {
                Image(systemName: "folder").font(.caption).foregroundStyle(.secondary)
                Text(store.folder.isEmpty ? "No folder chosen" : store.folder)
                    .font(.caption.monospaced()).lineLimit(1).truncationMode(.middle)
                Button("Choose Folder…") { chooseFolder() }.controlSize(.small)
                Spacer()
            }
            if !store.feedURL.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "link").font(.caption).foregroundStyle(.secondary)
                    Text(store.feedURL).font(.caption.monospaced()).textSelection(.enabled).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Button {
                        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(store.feedURL, forType: .string)
                    } label: { Label("Copy", systemImage: "doc.on.doc") }.controlSize(.small)
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(nsColor: .controlBackgroundColor).opacity(0.6)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.06), lineWidth: 1))
    }

    var feedSection: some View {
        card {
            sectionLabel("Feed", "sparkles")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ActionButton("Rebuild", "arrow.triangle.2.circlepath") { store.rebuild() }
                ActionButton("Fill Images", "photo.on.rectangle") { store.fillMissingImages() }
                ActionButton("Validate", "checkmark.seal", tint: .green) { store.validate() }
            }
            HStack(spacing: 8) {
                Text("Add").foregroundStyle(.secondary)
                TextField("N", text: $store.addAmount).frame(width: 56).textFieldStyle(.roundedBorder)
                Button("Add N New") { store.addNewFromSources(limit: Int(store.addAmount)) }
                Text("only new").font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                Button("Import Files…") {
                    let panel = NSOpenPanel(); panel.canChooseFiles = true
                    panel.canChooseDirectories = false; panel.allowsMultipleSelection = true
                    panel.title = "Import recipes (json, csv, txt, md, html)"
                    if panel.runModal() == .OK { store.importFiles(panel.urls) }
                }
                Toggle("Push after import", isOn: $store.pushAfterImport).toggleStyle(.checkbox)
            }
            Divider().padding(.vertical, 2)
            Text("Import from a GitHub repo").font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                TextField("https://github.com/owner/repo", text: $store.githubURL).textFieldStyle(.roundedBorder)
                Button("Import") { store.importGitHub(store.githubURL, limit: Int(store.addAmount)) }
            }
            Divider().padding(.vertical, 2)
            sectionLabel("Remove", "trash")
            HStack(spacing: 8) {
                TextField("json url, github repo, or website", text: $store.removeSource).textFieldStyle(.roundedBorder)
                Button("Remove Matches") { store.removeFromSource(store.removeSource) }
            }
            HStack(spacing: 8) {
                Button("Remove From File…") {
                    let panel = NSOpenPanel(); panel.canChooseFiles = true
                    panel.canChooseDirectories = false; panel.allowsMultipleSelection = true
                    if panel.runModal() == .OK { store.removeFromFile(panel.urls) }
                }
                Button("Remove No-Image", role: .destructive) { store.removeNoImage() }
            }
            Divider().padding(.vertical, 2)
            HStack(spacing: 8) {
                Text("App refresh every").foregroundStyle(.secondary)
                TextField("6", text: $store.refreshHours).frame(width: 46).textFieldStyle(.roundedBorder)
                Text("hours").foregroundStyle(.secondary)
                Button("Set Interval") { store.saveInterval() }
            }
            Text("Import & remove support json, csv, txt, md, html, GitHub, and websites. Drag files onto the window.").font(.caption2).foregroundStyle(.secondary)
        }
    }

    var gitSection: some View {
        card {
            sectionLabel("GitHub", "cloud")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ActionButton("Login", "person.badge.key") { store.ghLogin() }
                ActionButton("Connect Repo", "link.badge.plus") { store.connectRepo(name: repoName) }
                ActionButton("Commit & Push", "arrow.up.circle", tint: .blue) { store.commitPush() }
                ActionButton("Pull", "arrow.down.circle") { store.pull() }
                ActionButton("Verify", "checkmark.shield", tint: .green) { store.verify() }
            }
            TextField("repo name", text: $repoName).frame(width: 150).textFieldStyle(.roundedBorder)
            HStack(spacing: 8) {
                Image(systemName: "arrow.triangle.merge").foregroundStyle(.secondary)
                TextField("branch to merge", text: $branchToMerge).frame(width: 150).textFieldStyle(.roundedBorder)
                Button("Merge") { store.mergeBranch(branchToMerge) }
            }
        }
    }

    var logCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack { Text("Log").font(.headline); Spacer(); Button("Clear") { store.log = "" }.controlSize(.small) }
            ScrollView {
                Text(store.log.isEmpty ? "Ready. Choose your stocked-recipes folder if the list is empty." : store.log)
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled).padding(8)
            }
            .frame(minHeight: 200)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    @ViewBuilder private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) { content() }
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(nsColor: .controlBackgroundColor).opacity(0.5)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.06), lineWidth: 1))
    }

    private func sectionLabel(_ title: String, _ icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).foregroundStyle(.tint).font(.system(size: 12, weight: .semibold))
            Text(title.uppercased()).font(.caption.bold()).foregroundStyle(.secondary).tracking(0.6)
        }
    }

    private func chip(_ k: String, _ v: String, _ icon: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.caption2).foregroundStyle(.secondary)
            Text(k).font(.caption2).foregroundStyle(.secondary)
            Text(v).font(.caption.bold()).lineLimit(1)
        }
        .padding(.horizontal, 9).padding(.vertical, 5).background(.tint.opacity(0.12), in: Capsule())
    }
}

struct ActionButton: View {
    let title: String; let icon: String; var tint: Color = .accentColor
    let action: () -> Void
    init(_ title: String, _ icon: String, tint: Color = .accentColor, action: @escaping () -> Void) {
        self.title = title; self.icon = icon; self.tint = tint; self.action = action
    }
    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 14, weight: .semibold)).foregroundStyle(tint).frame(width: 22)
                Text(title).font(.callout).fontWeight(.medium).foregroundStyle(.primary).lineLimit(1)
                Spacer(minLength: 4)
            }
            .padding(.vertical, 8).padding(.horizontal, 11).frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(nsColor: .controlBackgroundColor).opacity(hovering ? 0.95 : 0.5)))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(hovering ? 0.12 : 0.06), lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain).opacity(isEnabled ? 1 : 0.5)
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hovering = h && isEnabled } }
    }
}

struct AddRecipeSheet: View {
    var onSave: (Recipe) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var category = ""
    @State private var area = ""
    @State private var imageURL = ""
    @State private var steps = ""
    @State private var ingredients = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Add a recipe").font(.title3.bold())
            HStack {
                TextField("Title", text: $title)
                TextField("Category", text: $category).frame(width: 130)
                TextField("Cuisine/Area", text: $area).frame(width: 130)
            }
            TextField("Image URL (optional — Fill Images can find one)", text: $imageURL)
            Text("Instructions — one step per line").font(.caption).foregroundStyle(.secondary)
            TextEditor(text: $steps).frame(height: 110).border(Color.gray.opacity(0.3))
            Text("Ingredients — one per line as  amount | ingredient").font(.caption).foregroundStyle(.secondary)
            TextEditor(text: $ingredients).frame(height: 90).border(Color.gray.opacity(0.3))
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") { save() }.keyboardShortcut(.defaultAction).disabled(title.isEmpty || steps.isEmpty)
            }
        }.padding(16).frame(width: 560)
    }

    private func save() {
        var ings: [String] = []; var meas: [String] = []
        for line in ingredients.split(separator: "\n") {
            let parts = line.components(separatedBy: "|")
            if parts.count == 2 { meas.append(parts[0].trimmingCharacters(in: .whitespaces)); ings.append(parts[1].trimmingCharacters(in: .whitespaces)) }
            else { ings.append(line.trimmingCharacters(in: .whitespaces)); meas.append("") }
        }
        let slug = normalize(title).replacingOccurrences(of: " ", with: "-")
        let r = Recipe(id: "custom-\(slug)", title: title, category: category, area: area,
                       instructions: steps.split(separator: "\n").map(String.init).joined(separator: "\n"),
                       imageURL: imageURL, ingredients: ings, measures: meas, source: SOURCE_TAG)
        onSave(r); dismiss()
    }
}
