import XCTest
@testable import FiveSkies

private struct FakeTipProduct: TipProduct {
    let id: String
    let displayName: String
    let displayPrice: String
    let outcome: TipPurchaseOutcome
    var throwsOnPurchase = false

    struct PurchaseError: Error {}

    func purchase() async throws -> TipPurchaseOutcome {
        if throwsOnPurchase {
            throw PurchaseError()
        }
        return outcome
    }
}

private struct FakeTipLoader: TipProductLoading {
    struct LoadError: Error {}

    let products: [FakeTipProduct]
    var fails = false

    func loadProducts(ids: [String]) async throws -> [TipProduct] {
        if fails {
            throw LoadError()
        }
        return products
    }

    func listenForTransactions(onFinished: @escaping @Sendable () async -> Void) async {}
}

final class TipStoreTests: XCTestCase {
    private func product(_ id: String, outcome: TipPurchaseOutcome = .success, throwsOnPurchase: Bool = false) -> FakeTipProduct {
        FakeTipProduct(
            id: id,
            displayName: "Name \(id)",
            displayPrice: "Price \(id)",
            outcome: outcome,
            throwsOnPurchase: throwsOnPurchase
        )
    }

    func testProductIdentifiers() {
        XCTAssertEqual(TipProductID.all, [
            "app.fiveskies.ios.tip.small",
            "app.fiveskies.ios.tip.medium",
            "app.fiveskies.ios.tip.large"
        ])
    }

    @MainActor
    func testStartsLoading() {
        let store = TipStore(loader: FakeTipLoader(products: []))
        XCTAssertEqual(store.loadState, .loading)
        XCTAssertEqual(store.purchaseState, .idle)
    }

    @MainActor
    func testUnavailableWhenNoProductsLoad() async {
        let store = TipStore(loader: FakeTipLoader(products: []))
        await store.loadProducts()
        XCTAssertEqual(store.loadState, .unavailable)
        XCTAssertTrue(store.options.isEmpty)
    }

    @MainActor
    func testUnavailableWhenLoadingFails() async {
        let store = TipStore(loader: FakeTipLoader(products: [product(TipProductID.small)], fails: true))
        await store.loadProducts()
        XCTAssertEqual(store.loadState, .unavailable)
    }

    @MainActor
    func testUnavailableWhenOnlyUnknownProductsLoad() async {
        let store = TipStore(loader: FakeTipLoader(products: [product("some.other.product")]))
        await store.loadProducts()
        XCTAssertEqual(store.loadState, .unavailable)
    }

    @MainActor
    func testLoadedKeepsSmallMediumLargeOrderAndStoreKitText() async {
        let loader = FakeTipLoader(products: [
            product(TipProductID.large),
            product(TipProductID.small),
            product(TipProductID.medium)
        ])
        let store = TipStore(loader: loader)
        await store.loadProducts()
        XCTAssertEqual(store.loadState, .loaded)
        XCTAssertEqual(store.options.map(\.id), TipProductID.all)
        XCTAssertEqual(store.options.first?.displayName, "Name \(TipProductID.small)")
        XCTAssertEqual(store.options.first?.displayPrice, "Price \(TipProductID.small)")
    }

    @MainActor
    private func loadedStore(outcome: TipPurchaseOutcome, throwsOnPurchase: Bool = false) async -> TipStore {
        let store = TipStore(loader: FakeTipLoader(products: [
            product(TipProductID.small, outcome: outcome, throwsOnPurchase: throwsOnPurchase)
        ]))
        await store.loadProducts()
        return store
    }

    @MainActor
    func testSuccessShowsThanks() async {
        let store = await loadedStore(outcome: .success)
        await store.purchase(TipProductID.small)
        XCTAssertEqual(store.purchaseState, .thankYou)
        store.reset()
        XCTAssertEqual(store.purchaseState, .idle)
    }

    @MainActor
    func testCancelledReturnsToIdle() async {
        let store = await loadedStore(outcome: .userCancelled)
        await store.purchase(TipProductID.small)
        XCTAssertEqual(store.purchaseState, .idle)
    }

    @MainActor
    func testPendingIsReported() async {
        let store = await loadedStore(outcome: .pending)
        await store.purchase(TipProductID.small)
        XCTAssertEqual(store.purchaseState, .pending)
    }

    @MainActor
    func testUnverifiedOrThrowingPurchaseFails() async {
        let unverified = await loadedStore(outcome: .failed)
        await unverified.purchase(TipProductID.small)
        XCTAssertEqual(unverified.purchaseState, .failed)

        let throwing = await loadedStore(outcome: .success, throwsOnPurchase: true)
        await throwing.purchase(TipProductID.small)
        XCTAssertEqual(throwing.purchaseState, .failed)
    }

    @MainActor
    func testUnknownProductDoesNothing() async {
        let store = await loadedStore(outcome: .success)
        await store.purchase(TipProductID.large)
        XCTAssertEqual(store.purchaseState, .idle)
    }
}
