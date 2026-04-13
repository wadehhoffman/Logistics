import SwiftUI

/// Visualizes the DOT Hours-of-Service projection attached to a scheduled
/// route by the server. Mirrors the web's breakdown card:
///   - totals row (elapsed / driving / break / rest)
///   - projected delivery ETA
///   - violations banner(s)
///   - per-segment timeline with drive 🚚 / break ☕ / rest 🛌 icons
///     color-coded to match the web (drive=blue, break=orange, rest=purple)
///
/// Pure display — reads `HOSProjection` directly from the `ScheduledRoute`.
struct HOSBreakdownView: View {
    let projection: HOSProjection

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            totalsRow

            etaRow

            ForEach(projection.violations) { v in
                violationBanner(v)
            }

            VStack(spacing: 4) {
                ForEach(projection.segments) { segment in
                    segmentRow(segment)
                }
            }

            Text("Property-carrying CMV rules: 11h daily max · 14h on-duty window · 30min break after 8h · 10h rest · 70/8 weekly cap")
                .font(.caption2).foregroundStyle(.tertiary)
                .multilineTextAlignment(.leading)
                .padding(.top, 4)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "road.lanes")
            Text("DOT Hours-of-Service Projection")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.carterBlue)
        }
    }

    // MARK: - Totals

    private var totalsRow: some View {
        HStack(spacing: 10) {
            totalCell(label: "Elapsed",  value: hours(projection.totalElapsedSec))
            totalCell(label: "Driving",  value: hours(projection.drivingSec))
            totalCell(label: "Break",    value: hours(projection.breakSec))
            totalCell(label: "Rest",     value: hours(projection.restSec))
        }
    }

    @ViewBuilder
    private func totalCell(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.subheadline.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Delivery ETA

    @ViewBuilder
    private var etaRow: some View {
        HStack(spacing: 4) {
            Image(systemName: "flag.checkered").imageScale(.small).foregroundStyle(.green)
            Text("Projected delivery:")
                .font(.caption).foregroundStyle(.secondary)
            Text(formatETA(projection.deliveryEta))
                .font(.caption.weight(.semibold))
        }
    }

    // MARK: - Violations

    @ViewBuilder
    private func violationBanner(_ v: HOSViolation) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(v.type.uppercased()).font(.caption2.weight(.bold))
                Text(v.message).font(.caption)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.orange.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.orange.opacity(0.4), lineWidth: 1)
        )
    }

    // MARK: - Segments

    @ViewBuilder
    private func segmentRow(_ segment: HOSSegment) -> some View {
        let (icon, color) = iconAndColor(for: segment.type)
        HStack(alignment: .top, spacing: 8) {
            Rectangle().fill(color).frame(width: 3)
            Text(icon).font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(segment.type.rawValue.uppercased())
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(color)
                    Text("• \(hours(segment.durationSec))")
                        .font(.caption2).foregroundStyle(.secondary)
                    Spacer()
                }
                Text(timeRange(start: segment.start, end: segment.end))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if let reason = segment.reason, !reason.isEmpty {
                    Text(reason).font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(color.opacity(0.08))
        )
    }

    private func iconAndColor(for type: HOSSegment.SegmentType) -> (String, Color) {
        switch type {
        case .drive:  return ("🚚", .blue)
        case .break:  return ("☕", .orange)
        case .rest:   return ("🛌", .purple)
        }
    }

    // MARK: - Formatting

    private func hours(_ seconds: Double) -> String {
        let h = seconds / 3600
        return String(format: "%.1fh", h)
    }

    private func formatETA(_ iso: String) -> String {
        guard let date = parseISO(iso) else { return iso }
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: date)
    }

    private func timeRange(start: String, end: String) -> String {
        guard let s = parseISO(start), let e = parseISO(end) else { return "\(start) → \(end)" }
        let cal = Calendar.current
        let crossesDay = !cal.isDate(s, inSameDayAs: e)

        let dayFmt = DateFormatter()
        dayFmt.dateFormat = "MMM d"
        let timeFmt = DateFormatter()
        timeFmt.dateFormat = "h:mm a"

        let sLabel = "\(dayFmt.string(from: s)) \(timeFmt.string(from: s))"
        let eLabel = crossesDay
            ? "\(dayFmt.string(from: e)) \(timeFmt.string(from: e))"
            : timeFmt.string(from: e)
        return "\(sLabel) → \(eLabel)"
    }

    private func parseISO(_ str: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: str) { return d }
        f.formatOptions = [.withInternetDateTime]
        if let d = f.date(from: str) { return d }
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
        if let d = df.date(from: str) { return d }
        df.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return df.date(from: str)
    }
}
