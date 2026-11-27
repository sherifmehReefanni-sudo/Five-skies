import Foundation
import StoreKit

/// How one purchase attempt ended.
enum TipPurchaseOutcome: Equatable, Sendable {
    case success
    case userCancelled
    case pending
    case failed
}

/// A tip product as the tip jar needs it. Prices come from the App Store, never from the app.
protocol TipProduct {
    var id: String { get }
    var displayName: String { get }
    var displayPrice: String { get }
    func purchase() async throws -> TipPurchaseOutcome
}

/// Loads tip products and listens for transactions that finish outside a purchase call.
protocol TipProductLoading {
    func loadProducts(ids: [String]) async throws -> [TipProduct]
    /// Runs until the calling task is cancelled. Calls `onFinished` for each verified transaction it finishes.
    func listenForTransactions(onFinished: @escaping @Sendable () async -> Void) async
}

/// The tip products, consumables in App Store Connect. Tips unlock nothing.
enum TipProductID {
    static let small = "app.fiveskies.ios.tip.small"
    static let medium = "app.fiveskies.ios.tip.medium"
    static let large = "app.fiveskies.ios.tip.large"

    static let all = [small, medium, large]
}

/// The tip jar's model, behind a product loader so it can be tested without StoreKit.
final class TipStore: ObservableObject {
    enum LoadState: Equatable {
        case loading
        case loaded
        case unavailable
    }

    enum PurchaseState: Equatable {
        case idle
        case purchasing(String)
        case pending
        case thankYou
        case failed
    }

    /// One button's worth of product, for display.
    struct Option: Identifiable, Equatable {
        let id: String
        let displayName: String
        let displayPrice: String
    }

    @Published private(set) var loadState: LoadState = .loading
    @Published private(set) var purchaseState: PurchaseState = .idle
    @Published private(set) var options: [Option] = []

    private let loader: TipProductLoading
    private let productIDs: [String]
    private var products: [String: TipProduct] = [:]
    private var updatesTask: Task<Void, Never>?
    private var hasLoaded = false

    init(loader: TipProductLoading = StoreKitTipLoader(), productIDs: [String] = TipProductID.all) {
        self.loader = loader
        self.productIDs = productIDs
        updatesTask = Task { [weak self] in
            await loader.listenForTransactions { [weak self] in
                await self?.transactionFinished()
            }
        }
    }

    deinit {
        updatesTask?.cancel()
    }

    /// Loads the products once. Later calls do nothing unless the first load found none.
    @MainActor
    func loadProducts() async {
        if hasLoaded, loadState == .loaded { return }
        hasLoaded = true
        loadState = .loading
        do {
            let loaded = try await loader.loadProducts(ids: productIDs)
            var byID: [String: TipProduct] = [:]
            for product in loaded where productIDs.contains(product.id) {
                byID[product.id] = product
            }
            products = byID
            // Shown in the order of `productIDs`: small, medium, large.
            options = productIDs.compactMap { id in
                byID[id].map { Option(id: $0.id, displayName: $0.displayName, displayPrice: $0.displayPrice) }
            }
            loadState = options.isEmpty ? .unavailable : .loaded
        } catch {
            products = [:]
            options = []
            loadState = .unavailable
        }
    }

    @MainActor
    func purchase(_ id: String) async {
        guard let product = products[id] else { return }
        if case .purchasing = purchaseState { return }
        purchaseState = .purchasing(id)
        do {
            let outcome = try await product.purchase()
            switch outcome {
            case .success:
                purchaseState = .thankYou
            case .userCancelled:
                purchaseState = .idle
            case .pending:
                purchaseState = .pending
            case .failed:
                purchaseState = .failed
            }
        } catch {
            purchaseState = .failed
        }
    }

    /// Back to the buttons after a thank you or a failure.
    @MainActor
    func reset() {
        purchaseState = .idle
    }

    /// A pending tip that was approved later, or any other transaction finished by the listener.
    @MainActor
    private func transactionFinished() {
        purchaseState = .thankYou
    }
}

// MARK: - StoreKit

/// The App Store, through StoreKit 2.
struct StoreKitTipLoader: TipProductLoading {
    func loadProducts(ids: [String]) async throws -> [TipProduct] {
        let products = try await Product.products(for: ids)
        return products.map { StoreKitTipProduct(product: $0) }
    }

    func listenForTransactions(onFinished: @escaping @Sendable () async -> Void) async {
        for await result in Transaction.updates {
            if Task.isCancelled { return }
            if case .verified(let transaction) = result {
                await transaction.finish()
                if TipProductID.all.contains(transaction.productID) {
                    await onFinished()
                }
            }
        }
    }
}

struct StoreKitTipProduct: TipProduct {
    let product: Product

    var id: String { product.id }
    var displayName: String { product.displayName }
    var displayPrice: String { product.displayPrice }

    func purchase() async throws -> TipPurchaseOutcome {
        let result = try await product.purchase()
        switch result {
        case .success(let verification):
            switch verification {
            case .verified(let transaction):
                await transaction.finish()
                return .success
            case .unverified:
                // Not delivered and not finished: the App Store could not vouch for it.
                return .failed
            }
        case .userCancelled:
            return .userCancelled
        case .pending:
            return .pending
        @unknown default:
            return .failed
        }
    }
}

/// A loader with no products, for the fixed screenshot mode. Nothing is sent to the App Store.
struct UnavailableTipLoader: TipProductLoading {
    func loadProducts(ids: [String]) async throws -> [TipProduct] {
        []
    }

    func listenForTransactions(onFinished: @escaping @Sendable () async -> Void) async {}
}
