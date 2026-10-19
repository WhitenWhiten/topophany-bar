import Foundation
import SwiftUI
import TopophanySections

/// A zone's clock: drawn live in a widget, where WidgetKit turns it each
/// minute without a reload; as of the model's time in a snapshot.
struct ZoneClock: View {
    enum Part { case time, period }

    var zone: ZonesSection.Zone
    var part: Part
    var live: Bool

    var body: some View {
        if live {
            // A date's text takes its time zone from the environment, not
            // from its format.
            Group {
                switch part {
                case .time: Text(.currentDate, format: Self.time(zone.timeZone))
                case .period: Text(.currentDate, format: Self.period(zone.timeZone))
                }
            }
            .environment(\.timeZone, zone.timeZone)
        } else {
            Text(verbatim: part == .time ? zone.time : zone.period)
        }
    }

    /// "6:30", or "18:30" on a 24-hour clock: as `Words.time` writes it.
    static func time(_ tz: TimeZone) -> Date.FormatStyle {
        Date.FormatStyle(locale: L10n.locale, timeZone: tz).hour(.defaultDigits(amPM: .omitted)).minute(.twoDigits)
    }

    /// "AM".
    static func period(_ tz: TimeZone) -> Date.VerbatimFormatStyle {
        Date.VerbatimFormatStyle(format: "\(dayPeriod: .standard(.abbreviated))", locale: L10n.locale, timeZone: tz,
                                 calendar: Calendar(identifier: .gregorian))
    }
}

/// The Time zones widget: the panel's zones, as many as the size holds,
/// This Mac's always among them; those left out are counted at the foot,
/// their servers' marks kept, trouble first. The clocks are this Mac's;
/// every mark is `topo`'s.
struct WidgetZones: View {
    var zones: ZonesSection
    var size: WidgetSize
    /// The room inside the widget's padding.
    var room: CGSize
    var p: CardsPalette
    var t: CardsType
    var live: Bool

    var compact: Bool { size == .small }
    /// The least a row takes; with room to spare, rows spread up to half as
    /// much again, rather than pooling above the foot.
    var minRow: Double { compact ? 25.5 : size == .medium ? 24 : 30 }
    static let heading = 19.0
    static let foot = 17.0

    /// The zones shown and those left out, whether a foot line fits, and
    /// each row's height.
    var layout: (shown: [ZonesSection.Zone], rest: [ZonesSection.Zone], foot: Bool, row: Double) {
        let n = zones.zones.count
        let room = self.room.height - Self.heading
        let wants = !zones.isCurrent || zones.unplaced > 0
        if Double(n) * minRow + (wants ? Self.foot : 0) <= room || (!wants && Double(n) * minRow <= room) {
            let foot = wants && Double(n) * minRow + Self.foot <= room
            return (zones.zones, [], foot, min(minRow * 1.5, (room - (foot ? Self.foot : 0)) / Double(max(1, n))))
        }
        let (shown, rest) = zones.cut(keeping: max(1, Int((room - Self.foot) / minRow)))
        return (shown, rest, true, minRow)
    }

    var body: some View {
        let l = layout
        let row = l.row
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                WidgetHeading(symbol: "clock", title: tr("Time zones"), meta: compact ? "" : meta, p: p, t: t)
                WidgetMark().padding(.leading, compact ? 0 : 8).alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
            }
            .frame(height: Self.heading, alignment: .top)
            if compact {
                ForEach(l.shown) { z in compactRow(z).frame(height: row, alignment: .center) }
            } else if size == .medium {
                Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                    ForEach(l.shown) { z in
                        GridRow {
                            inlineTime(z)
                            middle(z).padding(.horizontal, 10)
                            right(z).gridColumnAlignment(.trailing)
                        }
                        .frame(height: row)
                    }
                }
            } else {
                Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                    ForEach(l.shown) { z in
                        GridRow {
                            time(z)
                            middle(z).padding(.horizontal, 10)
                            right(z).gridColumnAlignment(.trailing)
                        }
                        .frame(height: row)
                    }
                }
            }
            Spacer(minLength: 0)
            if l.foot { foot(l.rest) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(spoken(l.shown)))
    }

    var meta: String { Words.join([tr("\(zones.zones.count) zones"), tr("\(zones.serverCount) servers")]) }

    /// Cut short, trouble first, so trouble left out still shows.
    func marks(_ servers: [ZonesSection.Server], _ n: Int, size: Double) -> some View {
        let servers = servers.count > n ? Mark.troubleFirst(servers, by: \.mark) : servers
        return HStack(spacing: 2.5) {
            ForEach(Array(servers.prefix(n).enumerated()), id: \.offset) { _, s in CardMark(mark: s.mark, size: size, color: p.color(s.mark)) }
            if servers.count > n {
                Text(verbatim: "+\(servers.count - n)").font(t.font(9.5)).foregroundStyle(p.l3).padding(.leading, 1)
            }
        }
        .fixedSize()
    }

    func title(_ z: ZonesSection.Zone, _ size: Double) -> some View {
        HStack(spacing: 4) {
            if z.isHere { Image(systemName: "location.fill").font(.system(size: size - 3)).foregroundStyle(p.accent) }
            Text(z.title).font(t.font(size)).foregroundStyle(p.l1).lineLimit(1).truncationMode(.tail)
        }
    }

    /// Small: the time over its period, the places over their marks.
    func compactRow(_ z: ZonesSection.Zone) -> some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 0) {
                ZoneClock(zone: z, part: .time, live: live).font(t.mono(14, .semibold)).foregroundStyle(p.l1).fixedSize()
                if !z.period.isEmpty {
                    ZoneClock(zone: z, part: .period, live: live).font(t.font(9, .medium)).foregroundStyle(p.l3)
                }
            }
            // As wide as "12:00": every clock comes to two-digit hours.
            .frame(width: 45 * t.scale, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                title(z, 11.5)
                marks(z.servers, 6, size: 7)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .lineLimit(1)
    }

    func time(_ z: ZonesSection.Zone) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            ZoneClock(zone: z, part: .time, live: live).font(t.mono(15, .semibold)).tracking(-0.15).foregroundStyle(p.l1)
            HStack(spacing: 0) {
                if !z.period.isEmpty {
                    ZoneClock(zone: z, part: .period, live: live)
                    Text(verbatim: " · ")
                }
                Text(z.zoneName)
            }
            .font(t.font(9.5, .medium)).foregroundStyle(p.l3).lineLimit(1)
        }
        .fixedSize()
    }

    /// The time and its period on one line, for rows a line tall.
    func inlineTime(_ z: ZonesSection.Zone) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 2.5) {
            ZoneClock(zone: z, part: .time, live: live).font(t.mono(14.5, .semibold)).tracking(-0.15).foregroundStyle(p.l1)
            if !z.period.isEmpty { ZoneClock(zone: z, part: .period, live: live).font(t.font(9, .medium)).foregroundStyle(p.l3) }
        }
        .fixedSize()
    }

    func middle(_ z: ZonesSection.Zone) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                title(z, 12)
                Spacer(minLength: 4)
                marks(z.servers, 8, size: 7.5)
            }
            // Long past a reload, its now would be an hour gone by.
            if !zones.clocksOnly { DayRibbon(zone: z, dark: p.isDark, now: p.accent, contrast: p.increaseContrast, band: 3.5) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The offset, over the day where it isn't this Mac's.
    func right(_ z: ZonesSection.Zone) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(z.relative).font(t.mono(10.5, .medium)).foregroundStyle(z.isHere ? p.l2 : p.l3)
            if !z.day.isEmpty, !zones.clocksOnly {
                Text(z.day).font(t.font(9.5)).foregroundStyle(p.l3)
            }
        }
        .lineLimit(1)
        .fixedSize()
        .frame(minWidth: 26, alignment: .trailing)
    }

    /// Zones left out, with their servers' marks; else what isn't known.
    @ViewBuilder func foot(_ rest: [ZonesSection.Zone]) -> some View {
        HStack(spacing: 5) {
            if !rest.isEmpty {
                Text(tr("+\(rest.count) more")).foregroundStyle(p.l2)
                Spacer(minLength: 4)
                marks(ZonesSection.servers(rest), compact ? 6 : 10, size: 7)
            } else if !zones.isCurrent {
                CardMark(mark: .offline, size: 8, color: p.unknown)
                Text(tr("Servers not known now"))
            } else if zones.unplaced > 0 {
                Text(tr("\(zones.unplaced) without a time zone"))
            }
        }
        .font(t.font(10.5)).foregroundStyle(p.l3).lineLimit(1)
        .frame(height: Self.foot)
    }

    func spoken(_ shown: [ZonesSection.Zone]) -> String {
        shown.map { z in Words.join([z.title, live ? "" : z.clock, z.relative, tr("\(z.servers.count) servers")]) }
            .joined(separator: ". ")
    }
}
