# Unplugged

### Folders

#### Docker

Runs a local PostgreSQL database for development.
Use docker-compose up -d

#### UnpluggedServer

Server built with Vapor. Connects to PostgreSQL, serves the REST API, and manages WebSocket connections.

Each folder has the following purpose:

- **Controllers** — Route handlers grouped by domain. Each controller defines HTTP endpoints and maps incoming requests to database operations. Receive shared DTOs, validate input, and return shared DTOs.

- **Database/Models** — Fluent ORM classes that map to PostgreSQL tables.

- **Database/Migrations** — Schema definitions for each table. One file per table. Create the PostgreSQL tables

- **WebSocket** — Communication during active sessions.

- **Middleware** — Runs before route handlers. AuthMiddleware verifies JWT tokens on protected routes. RateLimitMiddleware prevents abuse by capping requests per user (may be unneccesary we'll see)

- **Services** — TokenService generates and validates JWTs. StatsService computes aggregate stats (streaks, averages, jailbreak counts). NotificationService sends push notifications.

#### UnpluggedShared

A package imported by the iOS app and the server. model, DTO, enum, and validation rule are defined here and shared by both sides for single truth.

Each folder has the following purpose:

- **Models** — Data structs that define what a User, Session, Participant, SessionRecap, and SessionLocation look like.

- **DTOs** — Data Transfer Objects defining every request and response body for the API.

- **Enums** — State definitions. RoomState tracks the session lifecycle (idle, broadcasting, joining, countdown, locked, ending, ended). ParticipantStatus tracks each person's state. AppError is the error types for both client and server.

- **Protocols** — Abstractions for hardware services so we can mock them in tests. ProximityProviding abstracts UWB, ScreenTimeProviding abstracts Screen Time, PersistenceProviding abstracts local storage. Actual implementation is in the IOS app just here so tests don't break

- **Validation** — Shared rules like username length and group name constraints

#### Unplugged

The app: UI, hardware, networking, and local caching

Each folder has the following purpose:

- **App** — UnpluggedApp.swift is the main entry point that sets up the root view. DependencyContainer injects the services into the SwiftUI environment. AppDelegate handles UIKit-level things like push notifications.

- **Services/Hardware** — Wrappers around Apple hardware frameworks. UWBService handles NearbyInteraction for proximity detection. ScreenTimeService handles FamilyControls for locking down apps

- **Services/Feedback** — Haptic and audio output. Haptic: (joinBuzz, lockThud, etc) Audio: (lockClick, broadcastAnnouncement, etc) Make sure each audio has a Haptic fallback for phones on silent (audio should must likely not be actual voices?)

- **Services/Networking** — All communication with the server. APIClient handles auth headers and error mapping. WebSocketClient maintains the connection during active sessions.

- **Services/Persistence** — LocalCacheService gets data for offline caching. Stores recent sessions, profile data, and friend lists so the app loads faster. — this is just a cache for speed, server still is source of truth and can override this 100% of the time.

- **Services/Location** — LocationService wraps CLLocationManager. Grabs a single GPS fix when a session ends and reverse geocodes it to a place name like "Bass Library" for the recap card (Name can be changed, but not the location if activated).

- **Services/Composite** — Orchestration services that coordinate other services. SessionOrchestrator manages the full session lifecycle ProximityMonitor polls UWB distance and emits events

- **Features** — Each contain a View and ViewModel pair. Home is the main screen. Onboarding handles signup and Screen Time permission. Room has CreateRoom (host), JoinRoom (joiner), and ActiveRoom (locked session). Countdown is the 3-2-1 lock animation. Recap is the post-session summary. Profile shows stats and streaks. Friends manages friend lists and groups? History shows past sessions and a map (may most likely be apart of profile we'll see but should be fine for now)

- **SharedUI/Components** — Reusable code used across multiple features. ParticipantAvatar (circular avatar with status ring), CountdownRing (animated progress ring), UnplugAnimation (Lottie Unplug animation), PulseRadar (broadcasting/scanning animation), StatBadge (icon + number + label).

- **SharedUI/Modifiers** — ShakeEffect shakes avatars during jailbreak warnings. GlowEffect adds a glow to the lock button and active session indicator.

- **SharedUI/Styles** — Theme.swift holds all colors, fonts, and spacing. ButtonStyles.swift defines .primary, .destructive, and .ghost button styles.
                                                        
- **Extensions** — Formatting helpers. Date+Formatting adds "2 hours ago" and "Yesterday" display strings. TimeInterval+Display formats durations as "2h 14m", "1:23:05", or "47 minutes"

- **Resources** — Static assets

##### I don't know what to call jailbreak (when a user tries to leave early) now that we renamed it so I called it jailbreaks for now
