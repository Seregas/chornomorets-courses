import Foundation

/// Типізовані маршрути навігації каталогу.
enum Route: Hashable {
    case course(String)
    case stream(String)
    /// Щоденник практик — локальний, без параметрів.
    case journal
}
