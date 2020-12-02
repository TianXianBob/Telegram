import Foundation

final class PeerTable: Table {
    static func tableSpec(_ id: Int32) -> ValueBoxTable {
        return ValueBoxTable(id: id, keyType: .int64, compactValuesOnCreation: false)
    }
    
    private let reverseAssociatedTable: ReverseAssociatedPeerTable
    
    private let sharedEncoder = PostboxEncoder()
    private let sharedKey = ValueBoxKey(length: 8)
    
    private var cachedPeers: [PeerId: Peer] = [:]
    private var updatedInitialPeers: [PeerId: Peer?] = [:]
    
    init(valueBox: ValueBox, table: ValueBoxTable, reverseAssociatedTable: ReverseAssociatedPeerTable) {
        self.reverseAssociatedTable = reverseAssociatedTable
        
        super.init(valueBox: valueBox, table: table)
    }
    
    private func key(_ id: PeerId) -> ValueBoxKey {
        self.sharedKey.setInt64(0, value: id.toInt64())
        return self.sharedKey
    }
    
    func set(_ peer: Peer) {
        let previous = self.get(peer.id)
        self.cachedPeers[peer.id] = peer
        if self.updatedInitialPeers[peer.id] == nil {
            self.updatedInitialPeers[peer.id] = previous
        }
    }
    
    func get(_ id: PeerId) -> Peer? {
        if let peer = self.cachedPeers[id] {
            return peer
        }
        if let value = self.valueBox.get(self.table, key: self.key(id)) {
            if let peer = PostboxDecoder(buffer: value).decodeRootObject() as? Peer {
                self.cachedPeers[id] = peer
                return peer
            }
        }
        return nil
    }
    
    override func clearMemoryCache() {
        self.cachedPeers.removeAll()
        assert(self.updatedInitialPeers.isEmpty)
    }
    
    func transactionUpdatedPeers() -> [(Peer?, Peer)] {
        var result: [(Peer?, Peer)] = []
        for (peerId, initialPeer) in self.updatedInitialPeers {
            if let peer = self.get(peerId) {
                result.append((initialPeer, peer))
            } else {
                assertionFailure()
            }
        }
        return result
    }
    
    override func beforeCommit() {
        if !self.updatedInitialPeers.isEmpty {
            for (peerId, previousPeer) in self.updatedInitialPeers {
                if let peer = self.cachedPeers[peerId] {
                    self.sharedEncoder.reset()
                    self.sharedEncoder.encodeRootObject(peer)
                    
                    self.valueBox.set(self.table, key: self.key(peerId), value: self.sharedEncoder.readBufferNoCopy())
                    
                    let previousAssociation = previousPeer?.associatedPeerId
                    if previousAssociation != peer.associatedPeerId {
                        if let previousAssociation = previousAssociation {
                            self.reverseAssociatedTable.removeReverseAssociation(target: previousAssociation, from: peerId)
                        }
                        if let associatedPeerId = peer.associatedPeerId {
                            self.reverseAssociatedTable.addReverseAssociation(target: associatedPeerId, from: peerId)
                        }
                    }
                } else {
                    assertionFailure()
                }
            }
            
            self.updatedInitialPeers.removeAll()
        }
    }
}
