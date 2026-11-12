import Foundation

// MARK: - Entitlement (Free / Plus)
// `plan` is a plain string on the wire ("free" | "plus") — kept as String so an
// unknown future plan degrades gracefully instead of failing to decode.

struct Entitlement: Decodable {
    let plan: String
    let productId: String?
    let expiresAt: Date?
    let isTrial: Bool?
    let autoRenew: Bool?
    /// "purchased" | "family_shared" — set when Plus comes via Apple Family Sharing.
    let ownership: String?

    var isPlus: Bool { plan == "plus" }
    var isFamilyShared: Bool { ownership == "family_shared" }
}

/// `POST /v1/entitlement/link` — attach a StoreKit 2 signed transaction (JWS)
/// to a device after purchase / restore.
struct LinkTransactionRequest: Encodable {
    let deviceId: UUID
    let signedTransaction: String
}

struct LinkTransactionResponse: Decodable {
    let plan: String
}
