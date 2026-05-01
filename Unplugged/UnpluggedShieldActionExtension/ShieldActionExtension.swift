import Foundation
import ManagedSettings

final class ShieldActionExtension: ShieldActionDelegate {
    override func handle(
        action: ShieldAction,
        for application: ApplicationToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        handle(action: action, completionHandler: completionHandler)
    }

    override func handle(
        action: ShieldAction,
        for category: ActivityCategoryToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        handle(action: action, completionHandler: completionHandler)
    }

    override func handle(
        action: ShieldAction,
        for webDomain: WebDomainToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        handle(action: action, completionHandler: completionHandler)
    }

    private func handle(action: ShieldAction, completionHandler: @escaping (ShieldActionResponse) -> Void) {
        guard action == .secondaryButtonPressed else {
            completionHandler(.close)
            return
        }
        guard let context = ScreenTimeShared.loadActiveContext(),
              !context.isExpired(),
              ScreenTimeShared.claimAttemptReportSlot(sessionID: context.sessionID) else {
            completionHandler(.close)
            return
        }

        Task {
            let reported = await reportAttempt(context: context)
            if !reported {
                ScreenTimeShared.appendPendingShieldAttempt(
                    .init(
                        sessionID: context.sessionID,
                        reason: ScreenTimeShared.shieldActionAttemptReason
                    )
                )
            }
            completionHandler(.close)
        }
    }

    private func reportAttempt(context: ScreenTimeShared.ActiveContext) async -> Bool {
        guard let url = ScreenTimeShared.shieldAttemptURL(baseURL: context.baseURL, sessionID: context.sessionID) else {
            return false
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 8
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(context.bearerToken)", forHTTPHeaderField: "Authorization")

        let body = ShieldAttemptBody(
            reason: ScreenTimeShared.shieldActionAttemptReason,
            occurredAt: Date()
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let encoded = try? encoder.encode(body) else {
            return false
        }
        request.httpBody = encoded

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return false }
            return (200...299).contains(http.statusCode)
        } catch {
            return false
        }
    }
}

private struct ShieldAttemptBody: Encodable {
    let reason: String
    let occurredAt: Date
}
