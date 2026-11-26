import Foundation

/// The amounts a person enters into the zakat calculator.
struct ZakatInputs: Equatable {
    var cash: Decimal = 0
    var goldAndSilver: Decimal = 0
    var investments: Decimal = 0
    var owedToYou: Decimal = 0
    var debts: Decimal = 0
}

/// Pure zakat arithmetic in Decimal. 2.5% of net zakatable wealth, never below zero.
/// It does not apply a nisab threshold.
enum ZakatCalculator {
    /// Assets minus debts. Can be negative.
    static func netWealth(_ inputs: ZakatInputs) -> Decimal {
        inputs.cash + inputs.goldAndSilver + inputs.investments + inputs.owedToYou - inputs.debts
    }

    /// 2.5% of net wealth, or zero when debts meet or exceed assets.
    static func zakatDue(_ inputs: ZakatInputs) -> Decimal {
        let net = netWealth(inputs)
        guard net > 0 else { return 0 }
        return net * Decimal(25) / Decimal(1000)
    }

    /// Reads a typed amount using the locale's decimal and grouping separators.
    /// Empty, unreadable or negative text counts as zero.
    static func parse(_ text: String, locale: Locale = .current) -> Decimal {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let grouping = locale.groupingSeparator, !grouping.isEmpty {
            cleaned = cleaned.replacingOccurrences(of: grouping, with: "")
        }
        cleaned = cleaned.replacingOccurrences(of: "\u{00A0}", with: "")
        cleaned = cleaned.replacingOccurrences(of: "\u{202F}", with: "")
        cleaned = cleaned.replacingOccurrences(of: " ", with: "")
        guard !cleaned.isEmpty,
              let value = Decimal(string: cleaned, locale: locale),
              !value.isNaN,
              value > 0
        else {
            return 0
        }
        return value
    }

    /// The amount as currency for the locale, falling back to US dollars when the locale has no currency.
    static func formatted(_ amount: Decimal, locale: Locale = .current) -> String {
        let code = locale.currency?.identifier ?? "USD"
        return amount.formatted(Decimal.FormatStyle.Currency(code: code, locale: locale))
    }
}
