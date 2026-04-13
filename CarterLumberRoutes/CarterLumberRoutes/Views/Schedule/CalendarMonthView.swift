import SwiftUI

/// Monthly calendar grid with status-colored line items per day cell.
///
/// Lays out as a 7-column LazyVGrid (Sun–Sat). Each cell shows the day
/// number plus up to 5 line items (`HH:mm Yard (Truck)`) color-coded by
/// the schedule's status. If more routes exist, a "+N more" link at the
/// bottom of the cell opens the day drawer. Today's cell is highlighted.
///
/// Tapping anywhere in a day cell (or the +more link) opens the day
/// drawer sheet via the `onOpenDay` callback. Tapping a single line item
/// opens the per-route detail via `onOpenRoute`.
struct CalendarMonthView: View {
    let month: Date                                          // Any date within the month to render
    let routesByDay: [String: [ScheduledRoute]]
    let onOpenDay: (Date) -> Void
    let onOpenRoute: (ScheduledRoute) -> Void

    private let maxLineItems = 5
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 7)

    var body: some View {
        VStack(spacing: 6) {
            // Weekday header
            HStack(spacing: 2) {
                ForEach(["Sun","Mon","Tue","Wed","Thu","Fri","Sat"], id: \.self) { label in
                    Text(label)
                        .font(.caption2.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .foregroundStyle(.secondary)
                }
            }

            LazyVGrid(columns: columns, spacing: 2) {
                // Leading empty cells
                ForEach(0..<leadingEmptyCount, id: \.self) { _ in
                    Color.clear.frame(height: cellHeight)
                }
                // Day cells
                ForEach(1...daysInMonth, id: \.self) { day in
                    if let date = dateForDay(day) {
                        dayCell(date: date)
                    }
                }
            }
        }
    }

    // MARK: - Day cell

    @ViewBuilder
    private func dayCell(date: Date) -> some View {
        let key = dayKey(for: date)
        let dayRoutes = (routesByDay[key] ?? []).sorted { $0.scheduledAt < $1.scheduledAt }
        let shown = Array(dayRoutes.prefix(maxLineItems))
        let extra = max(0, dayRoutes.count - maxLineItems)
        let isToday = Calendar.current.isDateInToday(date)

        VStack(alignment: .leading, spacing: 2) {
            Text("\(Calendar.current.component(.day, from: date))")
                .font(.caption2.weight(.bold))
                .foregroundStyle(isToday ? Color.orange : .primary)

            ForEach(shown) { route in
                lineItem(route: route)
                    .onTapGesture { onOpenRoute(route) }
            }

            if extra > 0 {
                Text("+\(extra) more")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.carterBlue)
                    .padding(.top, 1)
            }

            Spacer(minLength: 0)
        }
        .padding(3)
        .frame(height: cellHeight, alignment: .topLeading)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isToday ? Color.yellow.opacity(0.12) : Color(.systemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(isToday ? Color.orange : Color(.separator), lineWidth: isToday ? 1.5 : 0.5)
        )
        .contentShape(Rectangle())
        .onTapGesture { onOpenDay(date) }
    }

    @ViewBuilder
    private func lineItem(route: ScheduledRoute) -> some View {
        let status = route.statusEnum
        let tint = color(for: status)
        let yardLabel = route.yard?.posNumber ?? ""
        let time = route.timeString.replacingOccurrences(of: " ", with: "")  // shorter
        let hosFlag = route.requiresOvernightRest ? "🛌" : (route.hasHosViolations ? "⚠️" : "")
        let label = "\(time) \(yardLabel)\(hosFlag.isEmpty ? "" : " \(hosFlag)")"

        HStack(spacing: 0) {
            Rectangle().fill(tint).frame(width: 2)
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(status == .cancelled ? .secondary : .primary)
                .strikethrough(status == .cancelled)
                .lineLimit(1)
                .padding(.leading, 3)
                .padding(.vertical, 1)
                .padding(.trailing, 2)
        }
        .background(tint.opacity(0.12))
        .cornerRadius(2)
    }

    // MARK: - Color mapping

    private func color(for status: ScheduledRoute.Status) -> Color {
        switch status {
        case .scheduled:             return .blue
        case .inProgress:            return .orange
        case .delivered, .completed: return .green
        case .cancelled:             return .red
        }
    }

    // MARK: - Layout math

    private var cellHeight: CGFloat {
        // Enough for day number + 5 line items + more link, compact but legible
        CGFloat(14 + (maxLineItems * 14) + 14)
    }

    private var daysInMonth: Int {
        let range = Calendar.current.range(of: .day, in: .month, for: month) ?? 1..<31
        return range.count
    }

    private var leadingEmptyCount: Int {
        let comps = Calendar.current.dateComponents([.year, .month], from: month)
        let first = Calendar.current.date(from: comps) ?? month
        let weekday = Calendar.current.component(.weekday, from: first)  // 1 = Sunday
        return weekday - 1
    }

    private func dateForDay(_ day: Int) -> Date? {
        var comps = Calendar.current.dateComponents([.year, .month], from: month)
        comps.day = day
        return Calendar.current.date(from: comps)
    }

    private func dayKey(for date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%d-%02d-%02d", c.year!, c.month!, c.day!)
    }
}
