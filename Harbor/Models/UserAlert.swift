import Foundation

struct UserAlert: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let message: String
}
