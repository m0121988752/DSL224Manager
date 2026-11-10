import WidgetKit
import SwiftUI

// MARK: - Timeline Entry
struct QuotaWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

// MARK: - Timeline Provider
struct QuotaWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> QuotaWidgetEntry {
        QuotaWidgetEntry(date: Date(), snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (QuotaWidgetEntry) -> Void) {
        let snapshot = SharedStorage.loadWidgetSnapshot()
        completion(QuotaWidgetEntry(date: Date(), snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<QuotaWidgetEntry>) -> Void) {
        let snapshot = SharedStorage.loadWidgetSnapshot()
        let entry = QuotaWidgetEntry(date: Date(), snapshot: snapshot)
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 20, to: Date()) ?? Date().addingTimeInterval(1200)
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
}

// MARK: - Widget Views
struct DSL224WidgetEntryView: View {
    var entry: QuotaWidgetProvider.Entry
    @Environment(\.widgetFamily) var family

    var body: some View {
        Group {
            switch family {
            case .systemSmall:
                SmallQuotaWidgetView(snapshot: entry.snapshot)
            case .systemMedium:
                MediumQuotaWidgetView(snapshot: entry.snapshot)
            case .accessoryCircular:
                CircularLockScreenWidgetView(snapshot: entry.snapshot)
            case .accessoryRectangular:
                RectangularLockScreenWidgetView(snapshot: entry.snapshot)
            default:
                SmallQuotaWidgetView(snapshot: entry.snapshot)
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
        .widgetBackground(Color(red: 0.08, green: 0.08, blue: 0.09))
    }
}

// MARK: - 1. Small Home Screen Widget
struct SmallQuotaWidgetView: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "wifi.router.fill")
                    .font(.caption)
                    .foregroundColor(statusColor)
                Text(snapshot.carrierName ?? snapshot.routerName)
                    .font(.caption.bold())
                    .foregroundColor(.white)
                    .lineLimit(1)
                Spacer()
            }

            Spacer(minLength: 2)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(String(format: "%.1f", snapshot.remainingGB)) GB")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Text("متبقي من \(Int(snapshot.totalPlanGB)) GB")
                    .font(.system(size: 10))
                    .foregroundColor(.gray)
            }

            // شريط النسبة
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(white: 0.22))
                        .frame(height: 6)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(statusColor)
                        .frame(width: max(0, min(geo.size.width, geo.size.width * CGFloat(snapshot.usedPercentage / 100.0))), height: 6)
                }
            }
            .frame(height: 6)

            HStack {
                Text("\(Int(snapshot.usedPercentage))% مستهلك")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(statusColor)
                Spacer()
                HStack(spacing: 2) {
                    Image(systemName: "laptopcomputer.and.iphone")
                        .font(.system(size: 9))
                    Text("\(snapshot.onlineDevicesCount)")
                        .font(.system(size: 10, weight: .bold))
                }
                .foregroundColor(.gray)
            }
        }
        .padding(12)
        .widgetURL(URL(string: "dsl224://sync"))
    }

    private var statusColor: Color {
        if snapshot.usedPercentage >= 85 { return .red }
        if snapshot.usedPercentage >= 70 { return .orange }
        return .blue
    }
}

// MARK: - 2. Medium Home Screen Widget
struct MediumQuotaWidgetView: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // السطر العلوي
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "wifi.router.fill")
                        .foregroundColor(statusColor)
                    Text(snapshot.routerName)
                        .font(.subheadline.bold())
                        .foregroundColor(.white)
                    if let carrier = snapshot.carrierName {
                        Text("[\(carrier)]")
                            .font(.caption2.bold())
                            .foregroundColor(.orange)
                    } else {
                        Text("(\(snapshot.routerIP))")
                            .font(.caption2)
                            .foregroundColor(.gray)
                    }
                }
                Spacer()
                Link(destination: URL(string: "dsl224://sync")!) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                        Text("تحديث")
                    }
                    .font(.caption2.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(white: 0.2))
                    .foregroundColor(.white)
                    .cornerRadius(6)
                }
            }

            // شريط الباقة
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(white: 0.2))
                        .frame(height: 8)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(statusColor)
                        .frame(width: max(0, min(geo.size.width, geo.size.width * CGFloat(snapshot.usedPercentage / 100.0))), height: 8)
                }
            }
            .frame(height: 8)

            // إحصائيات تفصيلية
            HStack(spacing: 12) {
                StatMiniColumn(title: "المستهلك", value: "\(String(format: "%.1f", snapshot.usedGB)) GB", color: .white)
                Divider().background(Color(white: 0.25))
                StatMiniColumn(title: "المتبقي", value: "\(String(format: "%.1f", snapshot.remainingGB)) GB", color: statusColor)
                Divider().background(Color(white: 0.25))
                StatMiniColumn(title: "المسموح يومياً", value: "\(String(format: "%.1f", snapshot.recommendedDailyGB)) GB", color: .green)
                Divider().background(Color(white: 0.25))
                StatMiniColumn(title: "السرعة اللحظية", value: snapshot.liveSpeedFormatted ?? "\(snapshot.onlineDevicesCount) متصل", color: .cyan)
            }
            .frame(maxHeight: 38)
        }
        .padding(14)
    }

    private var statusColor: Color {
        if snapshot.usedPercentage >= 85 { return .red }
        if snapshot.usedPercentage >= 70 { return .orange }
        return .blue
    }
}

struct StatMiniColumn: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 10))
                .foregroundColor(.gray)
            Text(value)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(color)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - 3. Lock Screen Widgets (شاشة القفل)
struct CircularLockScreenWidgetView: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        Gauge(value: snapshot.usedPercentage, in: 0...100) {
            Image(systemName: "wifi")
        } currentValueLabel: {
            Text("\(Int(snapshot.usedPercentage))%")
                .font(.system(size: 12, weight: .bold))
        }
        .gaugeStyle(.accessoryCircular)
    }
}

struct RectangularLockScreenWidgetView: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Image(systemName: "wifi.router")
                Text(snapshot.carrierName ?? snapshot.routerName)
                    .font(.caption.bold())
                Spacer()
                Text("\(Int(snapshot.usedPercentage))%")
                    .font(.caption.bold())
            }
            ProgressView(value: snapshot.usedPercentage, total: 100)
            Text("متبقي \(String(format: "%.1f", snapshot.remainingGB)) GB • \(snapshot.liveSpeedFormatted ?? "\(snapshot.onlineDevicesCount) متصل")")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - التوافق مع خلفيات iOS 16 و iOS 17+
extension View {
    @ViewBuilder
    func widgetBackground(_ backgroundView: some View) -> some View {
        if #available(iOSApplicationExtension 17.0, *) {
            containerBackground(for: .widget) {
                backgroundView
            }
        } else {
            background(backgroundView)
        }
    }
}

// MARK: - Widget Definition
@main
struct DSL224Widget: Widget {
    let kind: String = "DSL224Widget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: QuotaWidgetProvider()) { entry in
            DSL224WidgetEntryView(entry: entry)
        }
        .configurationDisplayName("مراقب باقة الراوتر")
        .description("يعرض استهلاك باقة الإنترنت والأجهزة المتصلة للراوتر النشط.")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .accessoryCircular,
            .accessoryRectangular
        ])
    }
}
