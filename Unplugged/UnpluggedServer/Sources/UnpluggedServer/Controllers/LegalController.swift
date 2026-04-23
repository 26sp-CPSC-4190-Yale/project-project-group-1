import Vapor

// TODO copy is placeholder, replace before App Store submission
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
            <p><em>Last updated: placeholder</em></p>
            <p>This is a placeholder for the Privacy Policy. The real text will describe what data Unplugged collects, how it is used, how long it is retained, and the choices users have over their data.</p>
            <p>Contact: placeholder@unplugged.name</p>
            """)
    }

    @Sendable
    func terms(req: Request) async throws -> Response {
        htmlResponse(title: "Terms of Service", bodyHTML: """
            <h1>Terms of Service</h1>
            <p><em>Last updated: placeholder</em></p>
            <p>This is a placeholder for the Terms of Service. The real text will cover acceptable use, account responsibilities, limitations of liability, and the governing law.</p>
            <p>Contact: placeholder@unplugged.name</p>
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
