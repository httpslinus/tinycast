import Foundation

/// Clock time in another city. See docs/features/calculator.md.
enum CalcTimeZone {
    static func evaluate(_ raw: String, now: Date, calendar: Calendar) -> CalcResult? {
        guard raw.count <= 128, raw.contains(where: \.isWhitespace) else {
            return nil
        }
        let echo = raw.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let query = echo.lowercased()
        let (zoneQuery, offset) = splitOffset(query)
        guard hasConnector(query) || query.first?.isNumber == true
            || ["noon ", "midnight ", "tomorrow ", "today ", "next "].contains(where: query.hasPrefix)
            || zoneQuery.hasSuffix(" time") || zoneQuery.hasPrefix("time ")
        else { return nil }

        if let difference = offsetBetween(query, now: now, calendar: calendar) { return difference }

        var words = zoneQuery.split(whereSeparator: \.isWhitespace).map(String.init)
        guard words.count >= 2 else { return nil }
        if words.last == "time", zone(named: Array(words.dropLast()), home: calendar.timeZone) != nil {
            words = ["time", "in"] + words.dropLast()
        } else if words.first == "time", zone(named: Array(words.dropFirst()), home: calendar.timeZone) != nil {
            words.insert("in", at: 1)
        }

        let connector = words.lastIndex(where: { ["in", "to", "at", "->", "→"].contains($0) })
        var target = calendar.timeZone
        var leading = words
        var needsSourceZone = true
        var isLocalTarget = true
        var ahead: (count: Int, component: Calendar.Component)?
        if let connector, words[connector] != "at"
            || zone(named: Array(words[(connector + 1)...]), home: calendar.timeZone) != nil
            || parseDuration(words[(connector + 1)...].joined(separator: " ")) != nil
        {
            let targetWords = Array(words[(connector + 1)...])
            if let zone = zone(named: targetWords, home: calendar.timeZone) {
                target = zone
                isLocalTarget = localNames.contains(targetWords.joined(separator: " "))
            } else if let duration = parseDuration(targetWords.joined(separator: " ")) {
                ahead = duration
            } else {
                return nil
            }
            leading = Array(words[..<connector])
            needsSourceZone = false
        }
        guard var source = sourceMoment(
            leading, needsZone: needsSourceZone, now: now, calendar: calendar)
        else { return nil }
        if let ahead {
            guard let shifted = calendar.date(byAdding: ahead.component, value: ahead.count, to: source.date)
            else { return nil }
            source = SourceMoment(date: shifted, zone: source.zone)
        }
        if let offset {
            guard
                let shifted = calendar.date(byAdding: offset.component, value: offset.count, to: source.date)
            else { return nil }
            source = SourceMoment(date: shifted, zone: source.zone)
        }

        return result(source, target: target, isLocalTarget: isLocalTarget, echo: echo, now: now, calendar: calendar)
    }

    /// Splits a trailing `+ 2h` / `- 30 min` off the zone phrase it shifts.
    private static func splitOffset(
        _ query: String
    ) -> (String, (count: Int, component: Calendar.Component)?) {
        for separator in [" + ", " - "] {
            guard let range = query.range(of: separator, options: .backwards) else { continue }
            let tail = String(query[range.upperBound...])
            guard let duration = parseDuration(tail, impliesHours: true) else { continue }
            let sign = separator == " - " ? -1 : 1
            return (String(query[..<range.lowerBound]), (duration.count * sign, duration.component))
        }
        return (query, nil)
    }

    /// `2h`, `90 min`, `2 hours` — sub-day only, since a zone answer is a clock time.
    private static func parseDuration(
        _ text: String, impliesHours: Bool = false
    ) -> (count: Int, component: Calendar.Component)? {
        let compact = text.replacingOccurrences(of: " ", with: "")
        let digits = compact.prefix { $0.isNumber }
        guard let count = Int(digits), count < 100_000 else { return nil }
        switch String(compact.dropFirst(digits.count)) {
        case "h", "hr", "hrs", "hour", "hours": return (count, .hour)
        case "m", "min", "mins", "minute", "minutes": return (count, .minute)
        case "s", "sec", "secs", "second", "seconds": return (count, .second)
        // A clock answer makes hours the only sensible unit for a bare `+ 5`.
        case "" where impliesHours: return (count, .hour)
        default: return nil
        }
    }

    private struct SourceMoment {
        let date: Date
        let zone: TimeZone
    }

    private static func hasConnector(_ raw: String) -> Bool {
        var word = ""
        for character in raw {
            if character.isWhitespace {
                if Self.connectors.contains(word.lowercased()) { return true }
                word = ""
            } else {
                word.append(character)
            }
        }
        return Self.connectors.contains(word.lowercased())
    }

    private static let connectors: Set<String> = ["in", "to", "at", "diff", "difference", "->", "→"]

    /// `diff paris`, `time diff paris` — how far a zone runs from the Mac's own.
    private static func offsetBetween(
        _ query: String, now: Date, calendar: Calendar
    ) -> CalcResult? {
        var words = query.split(whereSeparator: \.isWhitespace).map(String.init)
        if words.first == "time" { words.removeFirst() }
        guard words.count >= 2, words[0] == "diff" || words[0] == "difference",
            let target = zone(named: Array(words.dropFirst()))
        else { return nil }

        let home = calendar.timeZone
        let minutes =
            (target.secondsFromGMT(for: now) - home.secondsFromGMT(for: now)) / 60
        let sign = minutes < 0 ? "-" : "+"
        let whole = abs(minutes) / 60
        let part = abs(minutes) % 60
        let text = part == 0 ? "\(sign)\(whole)h" : "\(sign)\(whole)h \(part)m"

        return CalcResult(
            expression: clockString(now, zone: home, calendar: calendar),
            sourceBadge: label(for: home),
            targetBadge: label(for: target),
            payload: .value(
                display: "\(clockString(now, zone: target, calendar: calendar)) (\(text))",
                copyText: text))
    }

    private static func sourceMoment(
        _ words: [String], needsZone: Bool, now: Date, calendar: Calendar
    ) -> SourceMoment? {
        if let connector = words.lastIndex(where: { $0 == "in" || $0 == "at" }),
            let duration = parseDuration(words[(connector + 1)...].joined(separator: " ")),
            let source = sourceMoment(Array(words[..<connector]), needsZone: needsZone, now: now, calendar: calendar),
            let date = calendar.date(byAdding: duration.component, value: duration.count, to: source.date)
        {
            return SourceMoment(date: date, zone: source.zone)
        }
        var words = words
        for prefix in [
            ["what", "time", "is", "it"], ["what", "is", "the", "current", "time"],
            ["what", "is", "the", "time"], ["whats", "the", "time"], ["what's", "the", "time"],
            ["what", "time"], ["current", "time"], ["the", "time"]
        ]
        where words.starts(with: prefix) {
            words = ["time"] + words.dropFirst(prefix.count)
            break
        }
        guard let head = words.first else { return nil }
        if ["time", "now", "clock"].contains(head) {
            let rest = Array(words.dropFirst())
            if rest.isEmpty {
                return needsZone ? nil : SourceMoment(date: now, zone: calendar.timeZone)
            }
            if let zone = zone(named: rest, home: calendar.timeZone) {
                return SourceMoment(date: now, zone: zone)
            }
            return nil
        }

        guard let clockIndex = words.indices.first(where: { index in
            parseClock(words[index]) != nil
                || (index + 1 < words.count && parseClock(words[index] + words[index + 1]) != nil)
        }) else { return nil }
        var clockText = words[clockIndex]
        var clockEnd = clockIndex + 1
        if clockEnd < words.count, ["am", "pm", "a.m.", "p.m."].contains(words[clockEnd]) {
            clockText += words[clockEnd]
            clockEnd += 1
        }
        guard let clock = parseClock(clockText) else { return nil }
        var dayWords = Array(words[..<clockIndex])
        if dayWords.last == "at" { dayWords.removeLast() }
        let rest = Array(words[clockEnd...])
        guard let location = sourceLocation(rest, dayWords: dayWords, needsZone: needsZone, now: now, calendar: calendar)
        else { return nil }
        var source = calendar
        source.timeZone = location.zone
        let matching = DateComponents(hour: clock.hour, minute: clock.minute, second: 0)
        let date: Date?
        if let day = location.day {
            let candidate = source.nextDate(
                after: source.startOfDay(for: day).addingTimeInterval(-1), matching: matching,
                matchingPolicy: .strict, repeatedTimePolicy: .first)
            date = candidate.flatMap { source.isDate($0, inSameDayAs: day) ? $0 : nil }
        } else {
            date = source.nextDate(after: now, matching: matching, matchingPolicy: .strict, repeatedTimePolicy: .first)
        }
        return date.map { SourceMoment(date: $0, zone: location.zone) }
    }

    private static func sourceLocation(
        _ words: [String], dayWords: [String], needsZone: Bool, now: Date, calendar: Calendar
    ) -> (zone: TimeZone, day: Date?)? {
        for start in words.indices {
            for end in stride(from: words.count, through: start + 1, by: -1) {
                guard let zone = zone(named: Array(words[start..<end]), home: calendar.timeZone) else { continue }
                let prefixEnd = start > 0 && ["in", "at", "from"].contains(words[start - 1]) ? start - 1 : start
                var remaining = dayWords + words[..<prefixEnd] + words[end...]
                if remaining.first == "on" { remaining.removeFirst() }
                if remaining.isEmpty { return (zone, nil) }
                var source = calendar
                source.timeZone = zone
                if let day = CalcDateTime.resolveDay(remaining.joined(separator: " "), now: now, calendar: source) {
                    return (zone, day)
                }
            }
        }
        guard !needsZone else { return nil }
        var remaining = dayWords + words
        if remaining.first == "on" { remaining.removeFirst() }
        if remaining.isEmpty { return (calendar.timeZone, nil) }
        guard let day = CalcDateTime.resolveDay(remaining.joined(separator: " "), now: now, calendar: calendar)
        else { return nil }
        return (calendar.timeZone, day)
    }

    private static func parseClock(_ word: String) -> (hour: Int, minute: Int)? {
        if word == "noon" { return (12, 0) }
        if word == "midnight" { return (0, 0) }
        var text = word.replacingOccurrences(of: "a.m.", with: "am").replacingOccurrences(of: "p.m.", with: "pm")
        var meridiem: String?
        for suffix in ["am", "pm"] where text.hasSuffix(suffix) {
            meridiem = suffix
            text.removeLast(2)
        }
        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
        guard (1...2).contains(parts.count), let first = parts.first, (1...2).contains(first.count),
            first.allSatisfy({ $0.isASCII && $0.isNumber }), let hour = Int(first)
        else { return nil }
        let minute: Int
        if parts.count == 2 {
            guard parts[1].count == 2, parts[1].allSatisfy({ $0.isASCII && $0.isNumber }),
                let value = Int(parts[1]), (0...59).contains(value)
            else { return nil }
            minute = value
        } else {
            minute = 0
        }
        guard let meridiem else {
            guard parts.count == 2, (0...23).contains(hour) else { return nil }
            return (hour, minute)
        }
        guard (1...12).contains(hour) else { return nil }
        return (meridiem == "pm" ? (hour % 12) + 12 : hour % 12, minute)
    }

    private static func zone(named words: [String], home: TimeZone? = nil) -> TimeZone? {
        // `são paulo` and `zürich` are how the cities are spelled; the identifiers are not.
        var phrase = words.joined(separator: " ")
            .folding(options: [.diacriticInsensitive], locale: nil)
        if localNames.contains(phrase) { return home }
        if phrase.hasSuffix(" time"), aliases[phrase] == nil { phrase.removeLast(5) }
        if let zone = fixedZone(phrase) { return zone }
        if let identifier = aliases[phrase] { return TimeZone(identifier: identifier) }
        guard let identifier = cities[phrase] else { return nil }
        return TimeZone(identifier: identifier)
    }

    /// Foundation already carries the IANA database, so nothing here is generated.
    private static let cities: [String: String] = {
        var table: [String: String] = [:]
        for identifier in TimeZone.knownTimeZoneIdentifiers {
            guard let city = identifier.split(separator: "/").last else { continue }
            table[identifier.lowercased()] = identifier
            table[city.replacingOccurrences(of: "_", with: " ").lowercased()] = identifier
        }
        return table
    }()

    /// Curated: `abbreviationDictionary` is unusable, its `BDT` being the Bangladeshi taka.
    private static let aliasGroups: [String: [String]] = [
        "UTC": ["utc", "zulu"],
        "GMT": ["gmt"],
        "America/New_York": [
            "est", "edt", "et", "eastern", "eastern time", "nyc", "new york city", "boston", "washington",
            "dc", "miami", "atlanta",
            "philadelphia", "jfk", "atl", "bos", "mia", "ewr", "iad", "charlotte", "nashville", "orlando",
            "tampa", "pittsburgh", "cleveland", "cincinnati", "columbus", "baltimore", "raleigh",
            "indianapolis", "louisville"
        ],
        "America/Chicago": [
            "cst", "cdt", "ct", "central time", "austin", "dallas", "houston", "ord", "dfw", "iah", "minneapolis", "st louis",
            "kansas city", "milwaukee", "new orleans", "memphis", "oklahoma city", "san antonio"
        ],
        "America/Denver": ["mst", "mdt", "mt", "mountain time", "den", "salt lake city", "albuquerque", "boise"],
        "America/Los_Angeles": [
            "pst", "pdt", "pt", "california", "pacific", "pacific time", "la", "sf", "san francisco", "silicon valley",
            "seattle", "las vegas", "sfo",
            "lax", "sea", "san diego", "san jose", "portland", "sacramento", "fresno", "oakland"
        ],
        "Europe/Paris": [
            "cet", "cest", "cdg", "ory", "lyon", "marseille", "toulouse", "nice", "bordeaux", "nantes",
            "lille", "strasbourg"
        ],
        "Europe/London": [
            "bst", "ldn", "lhr", "lgw", "manchester", "birmingham", "liverpool", "leeds", "glasgow",
            "edinburgh", "bristol", "cardiff", "cambridge", "oxford", "belfast"
        ],
        "Asia/Kolkata": [
            "india", "ist", "kolkata", "bengaluru", "bangalore", "mumbai", "delhi", "new delhi", "chennai",
            "hyderabad", "bom", "del", "blr", "pune", "ahmedabad", "jaipur", "surat", "lucknow", "kanpur",
            "nagpur", "goa", "kochi", "indore", "thane", "bhopal", "visakhapatnam", "vizag", "patna",
            "vadodara", "ghaziabad", "ludhiana", "agra", "nashik", "faridabad", "meerut", "rajkot",
            "varanasi", "srinagar", "aurangabad", "amritsar", "navi mumbai", "allahabad", "prayagraj",
            "ranchi", "howrah", "coimbatore", "jabalpur", "gwalior", "vijayawada", "jodhpur", "madurai",
            "raipur", "chandigarh", "guwahati", "mysore", "mysuru", "gurgaon", "gurugram", "noida", "cochin",
            "trivandrum", "thiruvananthapuram", "panaji", "dehradun", "udaipur", "pondicherry", "puducherry",
            "jamshedpur", "bhubaneswar", "cuttack", "siliguri", "dhanbad", "kota", "shimla", "tirupati"
        ],
        "Asia/Tokyo": [
            "japan", "jst", "osaka", "kyoto", "nrt", "hnd", "kix", "yokohama", "nagoya", "sapporo", "fukuoka", "kobe",
            "hiroshima", "sendai", "okinawa", "nara"
        ],
        "Asia/Seoul": ["south korea", "kst", "icn", "busan", "incheon", "daegu"],
        "Australia/Sydney": ["aest", "aedt", "syd", "canberra", "newcastle"],
        "Asia/Singapore": ["sgp", "sin"],
        "Asia/Ho_Chi_Minh": ["vietnam", "saigon", "hcmc", "hanoi", "haiphong", "hue", "da nang"],
        "Europe/Berlin": [
            "germany", "munich", "frankfurt", "hamburg", "cologne", "fra", "muc", "txl", "ber", "hannover", "hanover",
            "stuttgart", "dusseldorf", "dortmund", "essen", "leipzig", "dresden", "bremen", "nuremberg",
            "nurnberg", "bonn", "mannheim", "karlsruhe", "freiburg", "munster", "augsburg", "kiel", "koln",
            "munchen"
        ],
        "Europe/Rome": [
            "italy", "milan", "fco", "mxp", "naples", "turin", "florence", "venice", "bologna", "genoa", "palermo",
            "verona"
        ],
        "Europe/Madrid": ["barcelona", "bcn", "valencia", "seville", "malaga", "bilbao", "zaragoza"],
        "Europe/Zurich": [
            "switzerland", "geneva", "zrh", "gva", "basel", "bern", "lausanne", "lucerne", "luzern", "winterthur",
            "st gallen", "lugano"
        ],
        "Europe/Moscow": ["st petersburg", "svo", "led"],
        "Europe/Kyiv": ["kyiv", "lviv", "odesa"],
        "Asia/Tel_Aviv": ["tel aviv", "tlv"],
        "Asia/Shanghai": [
            "shenzhen", "beijing", "guangzhou", "pvg", "pek", "chengdu", "tianjin", "wuhan", "xian",
            "hangzhou", "nanjing", "qingdao", "suzhou", "shenyang", "kunming", "xiamen"
        ],
        "Australia/Melbourne": ["melbourne", "mel"],
        "Australia/Brisbane": ["brisbane", "bne", "gold coast"],
        "Australia/Perth": ["perth", "per"],
        "America/Sao_Paulo": [
            "rio", "rio de janeiro", "gru", "brasilia", "salvador", "curitiba", "porto alegre",
            "belo horizonte", "recife"
        ],
        "America/Mexico_City": ["cdmx", "mexico city", "mex", "guadalajara", "puebla"],
        "Europe/Vienna": [
            "austria", "vie", "graz", "salzburg", "linz", "innsbruck", "klagenfurt", "villach", "wels", "st polten",
            "dornbirn", "bregenz", "wien"
        ],
        "Europe/Amsterdam": ["ams", "rotterdam", "the hague", "den haag", "eindhoven", "utrecht"],
        "Europe/Copenhagen": ["cph", "aarhus", "odense"],
        "Europe/Oslo": ["osl", "bergen", "trondheim"],
        "Europe/Stockholm": ["sweden", "arn", "gothenburg", "malmo"],
        "Europe/Helsinki": ["finland", "hel", "tampere", "turku"],
        "Europe/Dublin": ["ireland", "dub", "cork", "galway"],
        "Europe/Lisbon": ["lis", "porto"],
        "Europe/Athens": ["greece", "ath", "thessaloniki"],
        "Europe/Prague": ["czechia", "czech republic", "prg", "brno", "ostrava"],
        "Europe/Warsaw": ["poland", "waw", "krakow", "gdansk", "wroclaw", "poznan", "lodz"],
        "Europe/Budapest": ["hungary", "bud"],
        "Europe/Brussels": ["belgium", "bru", "antwerp", "ghent", "bruges"],
        "Europe/Tirane": ["albania", "tirana"],
        "Asia/Dubai": ["uae", "united arab emirates", "abu dhabi", "dxb", "auh", "sharjah"],
        "Asia/Qatar": ["doh", "doha"],
        "Asia/Hong_Kong": ["hkg"],
        "Asia/Bangkok": ["thailand", "bkk", "phuket", "chiang mai"],
        "Asia/Kuala_Lumpur": ["malaysia", "kul", "penang", "johor bahru"],
        "Asia/Jakarta": ["cgk", "surabaya", "medan", "bandung", "denpasar", "bali"],
        "Asia/Manila": ["philippines", "mnl", "cebu", "davao"],
        "Pacific/Auckland": ["akl", "wellington", "christchurch"],
        "America/Toronto": ["yyz", "yul", "ottawa", "quebec", "montreal"],
        "America/Vancouver": ["yvr", "victoria"],
        "America/Phoenix": ["phx"],
        "America/Argentina/Buenos_Aires": ["eze", "rosario", "mendoza"],
        "America/Santiago": ["scl", "valparaiso"],
        "America/Bogota": ["bog", "medellin", "cali", "cartagena"],
        "America/Lima": ["lim", "arequipa"],
        "Africa/Johannesburg": ["jnb", "cpt", "durban", "pretoria", "soweto"],
        "Africa/Cairo": ["cai", "alexandria", "giza"],
        "Africa/Nairobi": ["nbo", "mombasa"],
        "Africa/Lagos": ["los", "abuja", "kano", "ibadan"],
        "Africa/Casablanca": ["cmn", "marrakech", "rabat", "fes", "tangier"],
        "Europe/Istanbul": ["ankara", "izmir"],
        "Asia/Karachi": ["pakistan", "lahore", "islamabad", "faisalabad", "rawalpindi", "multan", "peshawar"],
        "America/Guayaquil": ["quito"],
        "Europe/Malta": ["valletta"],
        "Asia/Dhaka": ["bangladesh", "chittagong", "chattogram"],
        "Asia/Riyadh": ["saudi arabia", "jeddah", "mecca", "medina", "dammam"],
        "Asia/Taipei": ["kaohsiung", "taichung"],
        "Asia/Kuwait": ["kuwait city"],
        "Asia/Bahrain": ["manama"],
        "Asia/Jerusalem": ["haifa"],
        "America/Edmonton": ["calgary"]
    ]

    /// Flattened once from the grouping above, which is the form that gets edited.
    private static let aliases: [String: String] = {
        var table: [String: String] = [:]
        table.reserveCapacity(aliasGroups.values.reduce(0) { $0 + $1.count })
        for (zone, names) in aliasGroups {
            for name in names { table[name] = zone }
        }
        return table
    }()

    private static func label(for zone: TimeZone) -> String {
        if zone.identifier == "GMT" || zone.identifier == "UTC" { return "UTC" }
        guard let city = zone.identifier.split(separator: "/").last else { return zone.identifier }
        return city.replacingOccurrences(of: "_", with: " ")
    }

    private static func clockString(_ date: Date, zone: TimeZone, calendar: Calendar) -> String {
        CalcDateFormatters.clockString(from: date, calendar: calendar, zone: zone)
    }

    private static let localNames: Set<String> = ["local", "here", "my time", "local time", "my timezone", "my time zone"]

    private static func fixedZone(_ phrase: String) -> TimeZone? {
        guard phrase.hasPrefix("utc") || phrase.hasPrefix("gmt") else { return nil }
        let offset = phrase.dropFirst(3)
        guard let sign = offset.first, sign == "+" || sign == "-" else { return nil }
        let parts = offset.dropFirst().split(separator: ":", omittingEmptySubsequences: false)
        guard (1...2).contains(parts.count), let first = parts.first, (1...2).contains(first.count),
            first.allSatisfy({ $0.isASCII && $0.isNumber }), let hours = Int(first), hours <= 14
        else { return nil }
        var minutes = 0
        if parts.count == 2 {
            guard parts[1].count == 2, parts[1].allSatisfy({ $0.isASCII && $0.isNumber }),
                let value = Int(parts[1]), value < 60
            else { return nil }
            minutes = value
        }
        guard hours < 14 || minutes == 0 else { return nil }
        return TimeZone(secondsFromGMT: (hours * 3600 + minutes * 60) * (sign == "-" ? -1 : 1))
    }

    private static func result(
        _ source: SourceMoment, target: TimeZone, isLocalTarget: Bool, echo: String, now: Date, calendar: Calendar
    ) -> CalcResult {
        var from = calendar
        from.timeZone = source.zone
        var to = calendar
        to.timeZone = target
        let components: Set<Calendar.Component> = [.era, .year, .month, .day]
        let changesDate = from.dateComponents(components, from: source.date) != to.dateComponents(components, from: source.date)
        let includesDate = changesDate || !from.isDate(source.date, inSameDayAs: now) || !to.isDate(source.date, inSameDayAs: now)
        let sourcePattern = includesDate ? "EEE, d MMM yyyy, h:mm a" : "h:mm a"
        let sourceText = CalcDateFormatters.string(
            from: source.date, calendar: calendar, zone: source.zone, pattern: sourcePattern)
        let time = clockString(source.date, zone: target, calendar: calendar)
        let display: String
        if includesDate {
            let date = CalcDateFormatters.string(from: source.date, calendar: calendar, zone: target, pattern: "d MMMM yyyy")
            display = "\(date) at \(time)"
        } else {
            display = time
        }
        let targetName = isLocalTarget ? "Your Time" : label(for: target)
        let targetOffset = offsetLabel(target, at: source.date)
        let targetBadge = !isLocalTarget && target.identifier.hasPrefix("GMT") && target.identifier.count > 3
            ? targetOffset : "\(targetName), \(targetOffset)"
        return CalcResult(
            expression: echo,
            sourceBadge: "\(sourceText), \(offsetLabel(source.zone, at: source.date))",
            targetBadge: targetBadge,
            payload: .value(display: display, copyText: display))
    }

    private static func offsetLabel(_ zone: TimeZone, at date: Date) -> String {
        let seconds = zone.secondsFromGMT(for: date)
        guard seconds != 0 else { return "GMT" }
        let hours = abs(seconds) / 3600
        let minutes = (abs(seconds) % 3600) / 60
        let fraction = minutes == 0 ? "" : String(format: ":%02d", minutes)
        return "GMT\(seconds < 0 ? "-" : "+")\(hours)\(fraction)"
    }
}
