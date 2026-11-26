import SwiftUI

/// Zakat calculator: five amounts in, an estimate of zakat due out.
struct ZakatView: View {
    @State private var entries: [ZakatField: String] = [:]
    @FocusState private var focusedField: ZakatField?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                MoreScreenTitle(text: "Zakat calculator", identifier: "zakatTitle")
                form
                resultCard
                notes
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .moreSkyBackground(.zakat)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focusedField = nil }
            }
        }
    }

    private var form: some View {
        VStack(spacing: 0) {
            ForEach(ZakatField.allCases) { field in
                HStack(spacing: 10) {
                    Text(field.label)
                        .font(.subheadline.weight(.bold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    TextField("0", text: binding(for: field))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .font(.headline.weight(.heavy))
                        .focused($focusedField, equals: field)
                        .frame(minWidth: 100, maxWidth: 150, minHeight: 44)
                        .accessibilityLabel(Text(field.label))
                        .accessibilityIdentifier("zakat-\(field.rawValue)")
                }
                .frame(minHeight: 52)
                if field != ZakatField.allCases.last {
                    Divider().overlay(Color.white.opacity(0.12))
                }
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, 12)
        .padding(.vertical, 4)
        .moreGlass(.light, cornerRadius: 24)
    }

    private var resultCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Zakat due")
                .font(.subheadline.weight(.heavy))
            Text(ZakatCalculator.formatted(ZakatCalculator.zakatDue(inputs)))
                .font(.system(size: 44, weight: .black))
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .accessibilityIdentifier("zakatDue")
            Text("2.5% of net zakatable wealth")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(MorePalette.ink.opacity(0.72))
        }
        .foregroundStyle(MorePalette.ink)
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(MorePalette.goldGradient)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(Color.white, lineWidth: 1)
        )
        .shadow(color: MorePalette.gold.opacity(0.35), radius: 18, y: 14)
        .accessibilityElement(children: .combine)
    }

    private var notes: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("This is an estimate of 2.5% of net zakatable wealth. It does not check the nisab threshold yet.")
            Text("Ask a scholar about your situation.")
        }
        .font(.footnote.weight(.semibold))
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .moreGlass(.dark, cornerRadius: 22)
    }

    private var inputs: ZakatInputs {
        ZakatInputs(
            cash: amount(.cash),
            goldAndSilver: amount(.goldAndSilver),
            investments: amount(.investments),
            owedToYou: amount(.owedToYou),
            debts: amount(.debts)
        )
    }

    private func amount(_ field: ZakatField) -> Decimal {
        ZakatCalculator.parse(entries[field] ?? "", locale: .current)
    }

    private func binding(for field: ZakatField) -> Binding<String> {
        Binding(
            get: { entries[field] ?? "" },
            set: { entries[field] = $0 }
        )
    }
}

/// The five zakat inputs, in form order.
enum ZakatField: String, CaseIterable, Identifiable, Hashable {
    case cash
    case goldAndSilver
    case investments
    case owedToYou
    case debts

    var id: String { rawValue }

    var label: String {
        switch self {
        case .cash: return "Cash and savings"
        case .goldAndSilver: return "Gold and silver value"
        case .investments: return "Investments"
        case .owedToYou: return "Money owed to you"
        case .debts: return "Debts you owe"
        }
    }
}
