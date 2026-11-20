import Foundation


extension APIClient {
   
    func createPlan(_ request: PlanCreateRequest) async throws -> ServerPlan {
        try await send(.post, "/v1/plans", body: request)
    }


    func plans() async throws -> [ServerPlan] {
        let list: ServerPlanList = try await get("/v1/plans", enveloped: true)
        return list.items
    }

    func cancelPlan(id: UUID) async throws {
        try await delete("/v1/plans/\(id.uuidString.lowercased())")
    }

    
    func followPlan(token: String) async throws -> ServerPlan {
        try await send(.post, "/v1/plan-follows/\(token)", body: EmptyBody())
    }

    /// `DELETE /v1/plan-follows/{token}` → always 204.
    func unfollowPlan(token: String) async throws {
        try await delete("/v1/plan-follows/\(token)")
    }

    /// `GET /v1/shared-plans/{token}` — 404 `not_found` for unknown, canceled
    /// and ended plans alike.
    func sharedPlan(token: String) async throws -> SharedPlan {
        try await get("/v1/shared-plans/\(token)", enveloped: true)
    }
}
