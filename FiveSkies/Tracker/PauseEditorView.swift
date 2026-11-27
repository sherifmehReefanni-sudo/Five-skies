import SwiftUI

/// Sheet for starting a pause: a reason, a start day and an optional end day.
struct PauseEditorView: View {
    let today: Date
    let calculator: StreakCalculator
    let onSave: (TrackerPause) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var reason: PauseReason = .travel
    @State private var start: Date
    @State private var hasEnd = false
    @State private var end: Date

    init(today: Date, calculator: StreakCalculator, onSave: @escaping (TrackerPause) -> Void) {
        self.today = today
        self.calculator = calculator
        self.onSave = onSave
        _start = State(initialValue: today)
        _end = State(initialValue: today)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Reason", selection: $reason) {
                        ForEach(PauseReason.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("pauseReason")
                } footer: {
                    Text("Paused days keep your streak safe. They are not counted either way.")
                }

                Section {
                    DatePicker("Starts", selection: $start, in: startRange, displayedComponents: .date)
                        .accessibilityIdentifier("pauseStart")
                    Toggle("Set an end day", isOn: $hasEnd)
                        .accessibilityIdentifier("pauseHasEnd")
                    if hasEnd {
                        DatePicker("Ends", selection: $end, in: endRange, displayedComponents: .date)
                            .accessibilityIdentifier("pauseEnd")
                    }
                } footer: {
                    Text(hasEnd ? "Tracking picks up again the day after." : "You can resume any time from the tracker.")
                }
            }
            .navigationTitle("Pause tracking")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                    }
                    .accessibilityIdentifier("pauseSave")
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var calendar: Calendar { calculator.calendar }

    private var startRange: ClosedRange<Date> {
        let day = calendar.startOfDay(for: today)
        let lower = calendar.date(byAdding: .day, value: -365, to: day) ?? day
        let upper = calendar.date(byAdding: .day, value: 60, to: today) ?? today
        return lower...max(upper, lower)
    }

    private var endRange: ClosedRange<Date> {
        let lower = calendar.startOfDay(for: start)
        let upper = calendar.date(byAdding: .day, value: 365, to: start) ?? start
        return lower...max(upper, lower)
    }

    private func save() {
        let startKey = calculator.dayKey(for: start)
        var endKey: String?
        if hasEnd {
            endKey = max(calculator.dayKey(for: end), startKey)
        }
        onSave(TrackerPause(reason: reason, startKey: startKey, endKey: endKey))
        dismiss()
    }
}
