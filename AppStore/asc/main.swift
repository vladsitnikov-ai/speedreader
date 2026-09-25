// Minimal App Store Connect API client for SpeedReader:
//   asc status                       — app, versions, builds, localizations, screenshot sets
//   asc sync <listing.json> <shotsDir> — create/patch the version listing and upload screenshots
// Auth: ~/private_keys/AuthKey_<KEY_ID>.p8, KEY_ID / ISSUER_ID from the environment.
import Foundation
import CryptoKit

// MARK: - Config

let keyID = ProcessInfo.processInfo.environment["ASC_KEY_ID"] ?? "8Y5C9HV3FH"
let issuerID = ProcessInfo.processInfo.environment["ASC_ISSUER_ID"] ?? "69a6de7e-3a56-47e3-e053-5b8c7c11a4d1"
let bundleID = ProcessInfo.processInfo.environment["ASC_BUNDLE_ID"] ?? "com.vladsitnikov.speedreader.ios"
let base = URL(string: "https://api.appstoreconnect.apple.com")!

// MARK: - JWT

func base64url(_ data: Data) -> String {
    data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
}

func makeToken() throws -> String {
    let keyPath = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("private_keys/AuthKey_\(keyID).p8")
    let pem = try String(contentsOf: keyPath, encoding: .utf8)
    let key = try P256.Signing.PrivateKey(pemRepresentation: pem)
    let now = Int(Date().timeIntervalSince1970)
    let header = try JSONSerialization.data(withJSONObject: ["alg": "ES256", "kid": keyID, "typ": "JWT"])
    let payload = try JSONSerialization.data(withJSONObject: ["iss": issuerID, "iat": now, "exp": now + 1100, "aud": "appstoreconnect-v1"])
    let signingInput = base64url(header) + "." + base64url(payload)
    let signature = try key.signature(for: Data(signingInput.utf8))
    return signingInput + "." + base64url(signature.rawRepresentation)
}

// MARK: - HTTP

struct APIError: Error, CustomStringConvertible {
    let status: Int
    let body: String
    var description: String { "HTTP \(status): \(body)" }
}

@discardableResult
func request(_ method: String, _ path: String, query: [String: String] = [:], json: Any? = nil, absolute: URL? = nil, rawBody: Data? = nil, headers: [String: String] = [:]) throws -> [String: Any] {
    var url: URL
    if let absolute {
        url = absolute
    } else {
        var components = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) } }
        url = components.url!
    }
    var req = URLRequest(url: url)
    req.httpMethod = method
    if absolute == nil {
        req.setValue("Bearer \(try makeToken())", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    }
    for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
    if let json { req.httpBody = try JSONSerialization.data(withJSONObject: json) }
    if let rawBody { req.httpBody = rawBody }

    let semaphore = DispatchSemaphore(value: 0)
    var result: (Data?, URLResponse?, Error?) = (nil, nil, nil)
    URLSession.shared.dataTask(with: req) { result = ($0, $1, $2); semaphore.signal() }.resume()
    semaphore.wait()
    if let error = result.2 { throw error }
    let status = (result.1 as? HTTPURLResponse)?.statusCode ?? 0
    let data = result.0 ?? Data()
    guard (200..<300).contains(status) else { throw APIError(status: status, body: String(data: data, encoding: .utf8) ?? "") }
    if data.isEmpty { return [:] }
    return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
}

func items(_ response: [String: Any]) -> [[String: Any]] { response["data"] as? [[String: Any]] ?? [] }
func attrs(_ item: [String: Any]) -> [String: Any] { item["attributes"] as? [String: Any] ?? [:] }
func id(_ item: [String: Any]) -> String { item["id"] as? String ?? "" }

// MARK: - Lookups

func findApp() throws -> [String: Any] {
    let apps = items(try request("GET", "/v1/apps", query: ["filter[bundleId]": bundleID]))
    guard let app = apps.first else { throw APIError(status: 404, body: "no app with bundle id \(bundleID)") }
    return app
}

func versions(appID: String, platform: String) throws -> [[String: Any]] {
    items(try request("GET", "/v1/apps/\(appID)/appStoreVersions", query: ["filter[platform]": platform, "limit": "10"]))
}

func editableVersion(appID: String, platform: String, versionString: String) throws -> [String: Any] {
    let editableStates: Set<String> = ["PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED", "WAITING_FOR_REVIEW", "INVALID_BINARY"]
    if let existing = try versions(appID: appID, platform: platform).first(where: { editableStates.contains(attrs($0)["appStoreState"] as? String ?? "") }) {
        let current = attrs(existing)["versionString"] as? String ?? ""
        if current != versionString {
            print("  version \(current) → \(versionString)")
            try request("PATCH", "/v1/appStoreVersions/\(id(existing))", json: ["data": ["type": "appStoreVersions", "id": id(existing), "attributes": ["versionString": versionString]]])
        }
        return existing
    }
    print("  creating \(platform) version \(versionString)")
    let created = try request("POST", "/v1/appStoreVersions", json: ["data": [
        "type": "appStoreVersions",
        "attributes": ["platform": platform, "versionString": versionString],
        "relationships": ["app": ["data": ["type": "apps", "id": appID]]],
    ]])
    return created["data"] as? [String: Any] ?? [:]
}

// MARK: - Status

func status() throws {
    let app = try findApp()
    let appID = id(app)
    print("APP \(appID): \(attrs(app)["name"] ?? "") primaryLocale=\(attrs(app)["primaryLocale"] ?? "") bundle=\(attrs(app)["bundleId"] ?? "")")
    for platform in ["IOS", "MAC_OS"] {
        for v in try versions(appID: appID, platform: platform) {
            print("VERSION \(platform) \(attrs(v)["versionString"] ?? "") state=\(attrs(v)["appStoreState"] ?? "") id=\(id(v))")
            for loc in items(try request("GET", "/v1/appStoreVersions/\(id(v))/appStoreVersionLocalizations")) {
                let a = attrs(loc)
                let sets = items(try request("GET", "/v1/appStoreVersionLocalizations/\(id(loc))/appScreenshotSets"))
                let setInfo = sets.map { "\(attrs($0)["screenshotDisplayType"] ?? "")" }.joined(separator: ",")
                print("  LOC \(a["locale"] ?? "") desc=\((a["description"] as? String)?.count ?? 0)ch keywords=\(a["keywords"] ?? "") sets=[\(setInfo)]")
            }
        }
    }
    let builds = items(try request("GET", "/v1/builds", query: ["filter[app]": appID, "sort": "-uploadedDate", "limit": "5"]))
    for b in builds { print("BUILD \(attrs(b)["version"] ?? "") state=\(attrs(b)["processingState"] ?? "") id=\(id(b)) uploaded=\(attrs(b)["uploadedDate"] ?? "")") }
    for info in items(try request("GET", "/v1/apps/\(appID)/appInfos")) {
        print("APPINFO \(id(info)) state=\(attrs(info)["appStoreState"] ?? "")")
        for loc in items(try request("GET", "/v1/appInfos/\(id(info))/appInfoLocalizations")) {
            let a = attrs(loc)
            print("  INFO LOC \(a["locale"] ?? ""): name=\(a["name"] ?? "") subtitle=\(a["subtitle"] ?? "") privacy=\(a["privacyPolicyUrl"] ?? "")")
        }
    }
}

// MARK: - Sync

struct Listing: Decodable {
    struct Locale: Decodable {
        let name: String
        let subtitle: String
        let description: String
        let keywords: String
        let promotionalText: String
        let whatsNew: String
        let supportUrl: String
        let marketingUrl: String
        let privacyPolicyUrl: String
    }
    let version: String
    let platforms: [String]
    let primaryCategory: String
    let secondaryCategory: String
    let locales: [String: Locale]
}

func sync(listingPath: String, shotsDir: String) throws {
    let listing = try JSONDecoder().decode(Listing.self, from: Data(contentsOf: URL(fileURLWithPath: listingPath)))
    let app = try findApp()
    let appID = id(app)
    print("APP \(appID) \(attrs(app)["name"] ?? "")")

    // App info: name / subtitle / privacy URL per locale, categories.
    let infos = items(try request("GET", "/v1/apps/\(appID)/appInfos"))
    if let info = infos.first(where: { (attrs($0)["appStoreState"] as? String) != "READY_FOR_SALE" }) ?? infos.first {
        print("APPINFO \(id(info))")
        try request("PATCH", "/v1/appInfos/\(id(info))", json: ["data": ["type": "appInfos", "id": id(info), "relationships": [
            "primaryCategory": ["data": ["type": "appCategories", "id": listing.primaryCategory]],
            "secondaryCategory": ["data": ["type": "appCategories", "id": listing.secondaryCategory]],
        ]]])
        print("  categories set")
        let existing = items(try request("GET", "/v1/appInfos/\(id(info))/appInfoLocalizations"))
        for (locale, text) in listing.locales {
            let attributes: [String: Any] = ["name": text.name, "subtitle": text.subtitle, "privacyPolicyUrl": text.privacyPolicyUrl]
            if let loc = existing.first(where: { (attrs($0)["locale"] as? String) == locale }) {
                try request("PATCH", "/v1/appInfoLocalizations/\(id(loc))", json: ["data": ["type": "appInfoLocalizations", "id": id(loc), "attributes": attributes]])
            } else {
                var a = attributes; a["locale"] = locale
                try request("POST", "/v1/appInfoLocalizations", json: ["data": ["type": "appInfoLocalizations", "attributes": a, "relationships": ["appInfo": ["data": ["type": "appInfos", "id": id(info)]]]]])
            }
            print("  info localization \(locale) ok")
        }
    }

    for platform in listing.platforms {
        print("PLATFORM \(platform)")
        let version = try editableVersion(appID: appID, platform: platform, versionString: listing.version)
        let versionID = id(version)
        let existing = items(try request("GET", "/v1/appStoreVersions/\(versionID)/appStoreVersionLocalizations"))
        for (locale, text) in listing.locales {
            let attributes: [String: Any] = [
                "description": text.description, "keywords": text.keywords, "promotionalText": text.promotionalText,
                "whatsNew": text.whatsNew, "supportUrl": text.supportUrl, "marketingUrl": text.marketingUrl,
            ]
            var locID: String
            // A first release has no "What's New"; App Store Connect rejects the field with 409, so retry without it.
            func write(_ attributes: [String: Any], existingID: String?) throws -> String {
                if let existingID {
                    try request("PATCH", "/v1/appStoreVersionLocalizations/\(existingID)", json: ["data": ["type": "appStoreVersionLocalizations", "id": existingID, "attributes": attributes]])
                    return existingID
                }
                var a = attributes; a["locale"] = locale
                let created = try request("POST", "/v1/appStoreVersionLocalizations", json: ["data": ["type": "appStoreVersionLocalizations", "attributes": a, "relationships": ["appStoreVersion": ["data": ["type": "appStoreVersions", "id": versionID]]]]])
                return id(created["data"] as? [String: Any] ?? [:])
            }
            let existingID = existing.first(where: { (attrs($0)["locale"] as? String) == locale }).map(id)
            do {
                locID = try write(attributes, existingID: existingID)
            } catch let error as APIError where error.status == 409 && error.body.contains("whatsNew") {
                var withoutWhatsNew = attributes
                withoutWhatsNew.removeValue(forKey: "whatsNew")
                locID = try write(withoutWhatsNew, existingID: existingID)
                print("  (whatsNew skipped — not allowed for a first release)")
            }
            print("  version localization \(locale) ok (\(locID))")

            let displayTypes: [(type: String, folder: String)] = platform == "MAC_OS"
                ? [("APP_DESKTOP", "mac")]
                : [("APP_IPHONE_67", "iphone"), ("APP_IPAD_PRO_3GEN_129", "ipad")]
            for (displayType, folder) in displayTypes {
                let dir = URL(fileURLWithPath: shotsDir).appendingPathComponent(folder)
                let files = ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []).filter { $0.hasSuffix(".png") }.sorted()
                guard !files.isEmpty else { print("  \(displayType): no files in \(folder)/, skipped"); continue }
                try uploadScreenshots(localizationID: locID, displayType: displayType, files: files.map { dir.appendingPathComponent($0) })
            }
        }
    }
    print("DONE")
}

func uploadScreenshots(localizationID: String, displayType: String, files: [URL]) throws {
    let sets = items(try request("GET", "/v1/appStoreVersionLocalizations/\(localizationID)/appScreenshotSets"))
    var setID: String
    if let set = sets.first(where: { (attrs($0)["screenshotDisplayType"] as? String) == displayType }) {
        setID = id(set)
        // Replace whatever is there so the set matches the folder exactly.
        for shot in items(try request("GET", "/v1/appScreenshotSets/\(setID)/appScreenshots")) {
            try request("DELETE", "/v1/appScreenshots/\(id(shot))")
        }
    } else {
        let created = try request("POST", "/v1/appScreenshotSets", json: ["data": ["type": "appScreenshotSets", "attributes": ["screenshotDisplayType": displayType], "relationships": ["appStoreVersionLocalization": ["data": ["type": "appStoreVersionLocalizations", "id": localizationID]]]]])
        setID = id(created["data"] as? [String: Any] ?? [:])
    }
    for file in files {
        let data = try Data(contentsOf: file)
        let reservation = try request("POST", "/v1/appScreenshots", json: ["data": ["type": "appScreenshots", "attributes": ["fileName": file.lastPathComponent, "fileSize": data.count], "relationships": ["appScreenshotSet": ["data": ["type": "appScreenshotSets", "id": setID]]]]])
        let shot = reservation["data"] as? [String: Any] ?? [:]
        let operations = attrs(shot)["uploadOperations"] as? [[String: Any]] ?? []
        for op in operations {
            let offset = op["offset"] as? Int ?? 0
            let length = op["length"] as? Int ?? data.count
            var headers: [String: String] = [:]
            for h in op["requestHeaders"] as? [[String: String]] ?? [] { if let n = h["name"], let v = h["value"] { headers[n] = v } }
            try request(op["method"] as? String ?? "PUT", "", absolute: URL(string: op["url"] as? String ?? "")!, rawBody: data.subdata(in: offset..<(offset + length)), headers: headers)
        }
        let checksum = Insecure.MD5.hash(data: data).map { String(format: "%02x", $0) }.joined()
        try request("PATCH", "/v1/appScreenshots/\(id(shot))", json: ["data": ["type": "appScreenshots", "id": id(shot), "attributes": ["uploaded": true, "sourceFileChecksum": checksum]]])
        print("  \(displayType): uploaded \(file.lastPathComponent) (\(data.count / 1024) KB)")
    }
}

// MARK: - Finalize (build, age rating, content rights)

func finalize(platform: String, versionString: String) throws {
    let app = try findApp()
    let appID = id(app)

    // Attach the newest processed build of this version to the App Store version.
    let builds = items(try request("GET", "/v1/builds", query: ["filter[app]": appID, "filter[processingState]": "VALID", "sort": "-uploadedDate", "limit": "10"]))
    guard let build = builds.first(where: { (attrs($0)["version"] as? String) != nil }) else { throw APIError(status: 404, body: "no processed build") }
    let version = try editableVersion(appID: appID, platform: platform, versionString: versionString)
    try request("PATCH", "/v1/appStoreVersions/\(id(version))/relationships/build", json: ["data": ["type": "builds", "id": id(build)]])
    print("BUILD \(attrs(build)["version"] ?? "") attached to \(platform) \(versionString)")

    // Age rating: nothing objectionable.
    if let info = items(try request("GET", "/v1/apps/\(appID)/appInfos")).first {
        let declaration = try request("GET", "/v1/appInfos/\(id(info))/ageRatingDeclaration")
        if let declarationID = (declaration["data"] as? [String: Any]).map(id), !declarationID.isEmpty {
            let none = ["alcoholTobaccoOrDrugUseOrReferences", "contests", "gamblingSimulated", "horrorOrFearThemes",
                        "matureOrSuggestiveThemes", "medicalOrTreatmentInformation", "profanityOrCrudeHumor",
                        "sexualContentGraphicAndNudity", "sexualContentOrNudity", "violenceCartoonOrFantasy",
                        "violenceRealistic", "violenceRealisticProlongedGraphicOrSadistic"]
            var attributes: [String: Any] = Dictionary(uniqueKeysWithValues: none.map { ($0, "NONE") })
            attributes["gambling"] = false
            attributes["unrestrictedWebAccess"] = false
            attributes["kidsAgeBand"] = NSNull()
            try request("PATCH", "/v1/ageRatingDeclarations/\(declarationID)", json: ["data": ["type": "ageRatingDeclarations", "id": declarationID, "attributes": attributes]])
            print("AGE RATING set (4+)")
        }
    }

    // Content rights: no third-party content.
    try request("PATCH", "/v1/apps/\(appID)", json: ["data": ["type": "apps", "id": appID, "attributes": ["contentRightsDeclaration": "DOES_NOT_USE_THIRD_PARTY_CONTENT"]]])
    print("CONTENT RIGHTS set")
}

// MARK: - Main

let arguments = CommandLine.arguments.dropFirst()
do {
    switch arguments.first {
    case "status":
        try status()
    case "sync":
        guard arguments.count >= 3 else { print("usage: asc sync <listing.json> <shotsDir>"); exit(1) }
        try sync(listingPath: Array(arguments)[1], shotsDir: Array(arguments)[2])
    case "finalize":
        guard arguments.count >= 3 else { print("usage: asc finalize <IOS|MAC_OS> <version>"); exit(1) }
        try finalize(platform: Array(arguments)[1], versionString: Array(arguments)[2])
    default:
        print("usage: asc status | asc sync <listing.json> <shotsDir> | asc finalize <IOS|MAC_OS> <version>")
        exit(1)
    }
} catch {
    print("ERROR: \(error)")
    exit(2)
}
