import SwiftUI

/// Pick a goal template, set the target, and add it.
struct GoalCreatorSheet: View {
    static let nameLimit = 40

    let onCreate: (GoalKind, Int, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var kind: GoalKind = .fajrThisMonth
    @State private var target = GoalKind.fajrThisMonth.defaultTarget
    @State private var name = ""

    init(onCreate: @escaping (GoalKind, Int, String) -> Void) {
        self.onCreate = onCreate
    }

    private var canCreate: Bool {
        kind != .custom || !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Spacer()
                    Button("Cancel") {
                        dismiss()
                    }
                    .font(.headline.weight(.bold))
                    .foregroundStyle(MorePalette.gold)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("goalCancel")
                }
                MoreScreenTitle(text: "New goal", identifier: "goalCreatorTitle")
                MoreCaption(text: "Choose a goal")
                    .padding(.top, 4)
                ForEach(GoalKind.allCases) { item in
                    templateRow(item)
                }
                MoreCaption(text: "Target")
                    .padding(.top, 8)
                targetCard
                if kind == .custom {
                    nameField
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .safeAreaInset(edge: .bottom) {
            createButton
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 8)
                .background(MorePalette.ink.opacity(0.7).ignoresSafeArea())
        }
        .moreSkyBackground(.more)
        .onChange(of: kind) { _, newKind in
            target = newKind.defaultTarget
        }
    }

    private func templateRow(_ item: GoalKind) -> some View {
        let selected = item == kind
        return Button {
            kind = item
        } label: {
            HStack(spacing: 12) {
                Image(systemName: item.symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Color.white.opacity(0.14)))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.templateTitle)
                        .font(.subheadline.weight(.heavy))
                    Text(item.detail)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(MorePalette.secondaryText)
                }
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(selected ? MorePalette.gold : Color.white.opacity(0.5))
                    .accessibilityHidden(true)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .moreGlass(selected ? .light : .dark, cornerRadius: 22)
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? AccessibilityTraits.isSelected : AccessibilityTraits())
        .accessibilityIdentifier("goalTemplate-\(item.rawValue)")
    }

    private var targetCard: some View {
        Stepper(value: $target, in: kind.targetRange, step: kind.targetStep) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: String(target))
                    .font(.title2.weight(.black))
                    .monospacedDigit()
                Text(targetUnit)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(MorePalette.secondaryText)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .moreGlass(.dark, cornerRadius: 22)
        .accessibilityIdentifier("goalTarget")
    }

    private var targetUnit: String {
        switch kind {
        case .fajrThisMonth: return "days this month"
        case .allFiveDays: return "days, any days you like"
        case .nightPrayer: return "nights, any nights you like"
        case .dhikrToday: return "times today"
        case .dhikrWeek: return "times this week"
        case .custom: return "times"
        }
    }

    private var nameField: some View {
        TextField("Name", text: $name, prompt: Text("Name your goal"))
            .font(.body.weight(.semibold))
            .textInputAutocapitalization(.sentences)
            .submitLabel(.done)
            .padding(.horizontal, 16)
            .frame(minHeight: 52)
            .moreGlass(.dark, cornerRadius: 22)
            .onChange(of: name) { _, newName in
                if newName.count > Self.nameLimit {
                    name = String(newName.prefix(Self.nameLimit))
                }
            }
            .accessibilityIdentifier("goalName")
    }

    private var createButton: some View {
        Button {
            onCreate(kind, target, name)
            dismiss()
        } label: {
            Text("Add goal")
                .font(.headline.weight(.heavy))
                .foregroundStyle(MorePalette.ink)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(MorePalette.goldGradient)
                )
        }
        .buttonStyle(PressScaleButtonStyle())
        .disabled(!canCreate)
        .opacity(canCreate ? 1 : 0.5)
        .accessibilityIdentifier("goalCreate")
    }
}
