import Foundation

public protocol PersistenceProviding: AnyObject, Sendable {
    func saveUser(_ user: User) throws
    func loadUser() throws -> User?
    func saveSession(_ session: Session) throws
    func loadSession() throws -> Session?
    func clear() throws
}

