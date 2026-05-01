import Vapor

// routes are intentionally unauthenticated, the client footer and App Store reviewers need them without a token
struct LegalController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        let legal = routes.grouped("legal")
        legal.get("privacy", use: privacy)
        legal.get("terms", use: terms)
    }

    @Sendable
    func privacy(req: Request) async throws -> Response {
        htmlResponse(title: "Privacy Policy", bodyHTML: """
            <h1>Privacy Policy</h1>
            <p><em>Last updated: April 29, 2026</em></p>
            <p>Unplugged helps people start shared lock-in sessions, limit app access during a session, and review their session history.</p>
            <p>We collect account identifiers, usernames, authentication data, device tokens for notifications, friend and block relationships, session membership, session timing, co-lock approvals, early-leave reports, optional session descriptions, optional memory photos, optional location coordinates, optional weather summaries, and Screen Time permission state needed to run the app.</p>
            <p>Optional location, weather, and photo features are not required to create, join, or complete a session. If permission is denied or a user skips a memory photo, the session continues normally.</p>
            <p>We use this data to provide account access, friend features, push notifications, session locking, Live Activities, recaps, share cards, safety/reporting tools, and abuse prevention. We do not sell personal data or use it for third-party advertising.</p>
            <p>Users can delete their account in the app. Deletion disables login, clears the stored device token, and hides the account from public social surfaces, subject to retention needed for security, abuse prevention, and legal obligations.</p>
            <p>Contact: <a href="mailto:unplugged.ios.devs@gmail.com">unplugged.ios.devs@gmail.com</a></p>
            """)
    }

    @Sendable
    func terms(req: Request) async throws -> Response {
        htmlResponse(title: "Terms of Service", bodyHTML: """
            <h1>Terms of Service</h1>
            <p><em>Last updated: April 29, 2026</em></p>
            <p>By using Unplugged, you agree to use the app responsibly, provide accurate account information, and only create or join sessions with people who consent to participate.</p>
            <p>You are responsible for your account and for choosing emergency app allowlists that keep your device usable for safety, health, travel, and other essential needs.</p>
            <p>Do not misuse friend, report, notification, photo, or co-lock features to harass, impersonate, pressure, or track another person. Uploaded session photos must be lawful and must not include content you do not have the right to share.</p>
            <p>Screen Time, Nearby Interaction, Live Activities, push notifications, WeatherKit, and location services depend on Apple platform permissions, device support, connectivity, and operating-system behavior. Unplugged is provided as-is and cannot guarantee uninterrupted blocking or notification delivery.</p>
            <p>Contact: <a href="mailto:unplugged.ios.devs@gmail.com">unplugged.ios.devs@gmail.com</a></p>
            """)
    }

    private func htmlResponse(title: String, bodyHTML: String) -> Response {
        let html = """
        <!doctype html>
        <html lang="en">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>\(title) · Unplugged</title>
          <style>
            body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif;
                   max-width: 680px; margin: 2rem auto; padding: 0 1rem;
                   color: #1a1a1a; line-height: 1.55; }
            h1 { font-size: 1.75rem; margin-bottom: 0.25rem; }
            em { color: #666; }
            a { color: #00356b; }
            footer { margin-top: 3rem; font-size: 0.85rem; color: #888; }
          </style>
        </head>
        <body>
          \(bodyHTML)
          <footer>© Unplugged</footer>
        </body>
        </html>
        """
        var headers = HTTPHeaders()
        headers.contentType = .html
        return Response(status: .ok, headers: headers, body: .init(string: html))
    }
}
