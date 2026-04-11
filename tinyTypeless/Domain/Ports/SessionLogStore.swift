import Foundation

protocol SessionLogStore {
    func append(_ record: SessionRecord) async
}
