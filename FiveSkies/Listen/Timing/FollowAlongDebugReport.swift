import Foundation
import os

#if DEBUG
/// The W4 count for one reciter: how many ayahs were checked and how many fall back to ayah level.
/// Numbers only. No Quran text is ever logged.
struct FollowAlongCheck: Equatable, Sendable {
    let reciterID: Int
    let chapters: Int
    let ayahsChecked: Int
    let ayahsFallingBack: Int
    let byReason: [TimingFallbackReason: Int]
    /// Up to `FollowAlongDebugReport.listedKeyLimit` fallback ayahs as "chapter:ayah", in order.
    let sampleKeys: [String]

    var fallbackPercent: Double {
        guard ayahsChecked > 0 else { return 0 }
        return Double(ayahsFallingBack) * 100 / Double(ayahsChecked)
    }

    static func empty(reciterID: Int) -> FollowAlongCheck {
        FollowAlongCheck(reciterID: reciterID, chapters: 0, ayahsChecked: 0, ayahsFallingBack: 0, byReason: [:], sampleKeys: [])
    }

    func adding(_ other: FollowAlongCheck) -> FollowAlongCheck {
        var reasons = byReason
        for (reason, count) in other.byReason {
            reasons[reason, default: 0] += count
        }
        let keys = Array((sampleKeys + other.sampleKeys).prefix(FollowAlongDebugReport.listedKeyLimit))
        return FollowAlongCheck(
            reciterID: reciterID,
            chapters: chapters + other.chapters,
            ayahsChecked: ayahsChecked + other.ayahsChecked,
            ayahsFallingBack: ayahsFallingBack + other.ayahsFallingBack,
            byReason: reasons,
            sampleKeys: keys
        )
    }
}

/// Debug builds only (plan rule W4). Logs with subsystem "app.fiveskies.ios", category "followAlong".
enum FollowAlongDebugReport {
    static let logger = Logger(subsystem: "app.fiveskies.ios", category: "followAlong")
    static let listedKeyLimit = 40
    /// Launch argument for the whole Quran check: `-FSFollowAlongAudit <reciter id>`.
    static let auditArgument = "-FSFollowAlongAudit"
    static let totalAyahs = 6_236

    /// Counts for one surah, without logging.
    static func check(timings: SurahTimings, ayahs: [Ayah]) -> FollowAlongCheck {
        let followAlong = SurahFollowAlong(chapter: timings.chapter, ayahs: ayahs, timings: timings)
        return check(followAlong, reciterID: timings.reciterID)
    }

    static func check(_ followAlong: SurahFollowAlong, reciterID: Int) -> FollowAlongCheck {
        var reasons: [TimingFallbackReason: Int] = [:]
        var keys: [String] = []
        for item in followAlong.fallbackAyahs {
            reasons[item.reason, default: 0] += 1
            if keys.count < listedKeyLimit {
                keys.append("\(followAlong.chapter):\(item.ayah)")
            }
        }
        return FollowAlongCheck(
            reciterID: reciterID,
            chapters: 1,
            ayahsChecked: followAlong.ayahsChecked,
            ayahsFallingBack: followAlong.ayahsFallingBack,
            byReason: reasons,
            sampleKeys: keys
        )
    }

    /// Counts for one surah and logs them. Call when the player's timings arrive.
    @discardableResult
    static func report(timings: SurahTimings, ayahs: [Ayah]) -> FollowAlongCheck {
        let result = check(timings: timings, ayahs: ayahs)
        log(result, scope: "surah \(timings.chapter)")
        return result
    }

    /// Fetches every surah's timings for one reciter, one after another, and logs the total
    /// against the 6,236 ayahs. Surahs with no timings count as falling back (`noTiming`).
    @discardableResult
    static func checkWholeQuran(
        reciterID: Int,
        data: QuranData,
        provider: any SurahTimingProviding
    ) async -> FollowAlongCheck {
        var total = FollowAlongCheck.empty(reciterID: reciterID)
        for sura in data.suras {
            if Task.isCancelled { break }
            let ayahs = data.ayahs(inSura: sura.number)
            let timings = await provider.timings(reciterID: reciterID, chapter: sura.number)
            let followAlong = SurahFollowAlong(chapter: sura.number, ayahs: ayahs, timings: timings)
            let one = check(followAlong, reciterID: reciterID)
            if timings == nil {
                logger.info("Follow along: reciter \(reciterID, privacy: .public), surah \(sura.number, privacy: .public): no timings")
            }
            total = total.adding(one)
        }
        log(total, scope: "whole Quran (\(data.ayahCount) of \(totalAyahs) ayahs)")
        return total
    }

    /// The reciter id after `-FSFollowAlongAudit`, if the app was launched with it.
    static func auditReciterID(processInfo: ProcessInfo = .processInfo) -> Int? {
        let arguments = processInfo.arguments
        guard let index = arguments.firstIndex(of: auditArgument), index + 1 < arguments.count else {
            return nil
        }
        guard let id = Int(arguments[index + 1]), id > 0 else { return nil }
        return id
    }

    static func summary(_ check: FollowAlongCheck, scope: String) -> String {
        let percent = String(format: "%.2f", check.fallbackPercent)
        let reasons = TimingFallbackReason.allCases
            .map { "\($0.rawValue) \(check.byReason[$0] ?? 0)" }
            .joined(separator: ", ")
        let keys = check.sampleKeys.isEmpty ? "none" : check.sampleKeys.joined(separator: " ")
        return "Follow along, reciter \(check.reciterID), \(scope): \(check.ayahsChecked) ayahs checked, "
            + "\(check.ayahsFallingBack) fall back (\(percent) percent). Reasons: \(reasons). Fallback ayahs: \(keys)"
    }

    private static func log(_ check: FollowAlongCheck, scope: String) {
        let line = summary(check, scope: scope)
        logger.info("\(line, privacy: .public)")
    }
}
#endif
