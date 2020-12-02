import Foundation

public struct GalleryItemOriginData: Equatable {
    public var title: String?
    public var timestamp: Int32?
    
    public init(title: String?, timestamp: Int32?) {
        self.title = title
        self.timestamp = timestamp
    }
}

public struct GalleryItemIndexData: Equatable {
    public var position: Int32
    public var totalCount: Int32
    
    public init(position: Int32, totalCount: Int32) {
        self.position = position
        self.totalCount = totalCount
    }
}

public protocol GalleryItem {
    func node() -> GalleryItemNode
    func updateNode(node: GalleryItemNode)
    func thumbnailItem() -> (Int64, GalleryThumbnailItem)?
}
