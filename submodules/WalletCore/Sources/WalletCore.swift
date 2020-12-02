import Foundation
import SwiftSignalKit
import TonBinding


public struct TonKeychainEncryptedData: Codable, Equatable {
    public let publicKey: Data
    public let data: Data
    
    public init(publicKey: Data, data: Data) {
        self.publicKey = publicKey
        self.data = data
    }
}

public enum TonKeychainEncryptDataError {
    case generic
}

public enum TonKeychainDecryptDataError {
    case generic
    case publicKeyMismatch
    case cancelled
}

public struct TonKeychain {
    public let encryptionPublicKey: () -> Signal<Data?, NoError>
    public let encrypt: (Data) -> Signal<TonKeychainEncryptedData, TonKeychainEncryptDataError>
    public let decrypt: (TonKeychainEncryptedData) -> Signal<Data, TonKeychainDecryptDataError>
    
    public init(encryptionPublicKey: @escaping () -> Signal<Data?, NoError>, encrypt: @escaping (Data) -> Signal<TonKeychainEncryptedData, TonKeychainEncryptDataError>, decrypt: @escaping (TonKeychainEncryptedData) -> Signal<Data, TonKeychainDecryptDataError>) {
        self.encryptionPublicKey = encryptionPublicKey
        self.encrypt = encrypt
        self.decrypt = decrypt
    }
}

public enum TonNetworkProxyResult {
    case reponse(Data)
    case error(String)
}

public protocol TonNetworkProxy: class {
    func request(data: Data, timeout: Double, completion: @escaping (TonNetworkProxyResult) -> Void) -> Disposable
}

private final class TonInstanceImpl {
    private let queue: Queue
    private let basePath: String
    fileprivate var config: String
    fileprivate var blockchainName: String
    private let proxy: TonNetworkProxy?
    private var instance: TON?
    fileprivate let syncStateProgress = ValuePromise<Float>(0.0)
    
    init(queue: Queue, basePath: String, config: String, blockchainName: String, proxy: TonNetworkProxy?) {
        self.queue = queue
        self.basePath = basePath
        self.config = config
        self.blockchainName = blockchainName
        self.proxy = proxy
    }
    
    func withInstance(_ f: (TON) -> Void) {
        let instance: TON
        if let current = self.instance {
            instance = current
        } else {
            let proxy = self.proxy
            let syncStateProgress = self.syncStateProgress
            instance = TON(keystoreDirectory: self.basePath + "/ton-keystore", config: self.config, blockchainName: self.blockchainName, performExternalRequest: { request in
                if let proxy = proxy {
                    let _ = proxy.request(data: request.data, timeout: 20.0, completion: { result in
                        switch result {
                        case let .reponse(data):
                            request.onResult(data, nil)
                        case let .error(description):
                            request.onResult(nil, description)
                        }
                    })
                } else {
                    request.onResult(nil, "NETWORK_DISABLED")
                }
            }, enableExternalRequests: proxy != nil, syncStateUpdated: { progress in
                syncStateProgress.set(progress)
            })
            self.instance = instance
        }
        f(instance)
    }
}

public final class TonInstance {
    private let queue: Queue
    private let impl: QueueLocalObject<TonInstanceImpl>
    
    public var syncProgress: Signal<Float, NoError> {
        return Signal { subscriber in
            let disposable = MetaDisposable()
            self.impl.with { impl in
                disposable.set(impl.syncStateProgress.get().start(next: { value in
                    subscriber.putNext(value)
                }))
            }
            return disposable
        }
    }
    
    public init(basePath: String, config: String, blockchainName: String, proxy: TonNetworkProxy?) {
        self.queue = .mainQueue()
        let queue = self.queue
        self.impl = QueueLocalObject(queue: queue, generate: {
            return TonInstanceImpl(queue: queue, basePath: basePath, config: config, blockchainName: blockchainName, proxy: proxy)
        })
    }
    
    public func updateConfig(config: String, blockchainName: String) -> Signal<Never, NoError> {
        return Signal { subscriber in
            let disposable = MetaDisposable()
            self.impl.with { impl in
                impl.config = config
                impl.blockchainName = blockchainName
                impl.withInstance { ton in
                    let cancel = ton.updateConfig(config, blockchainName: blockchainName).start(next: nil, error: { _ in
                    }, completed: {
                        subscriber.putCompletion()
                    })
                    disposable.set(ActionDisposable {
                        cancel?.dispose()
                    })
                }
            }
            return disposable
        }
    }
    
    public func validateConfig(config: String, blockchainName: String) -> Signal<WalletValidateConfigResult, WalletValidateConfigError> {
        return Signal { subscriber in
            let disposable = MetaDisposable()
            self.impl.with { impl in
                impl.withInstance { ton in
                    let cancel = ton.validateConfig(config, blockchainName: blockchainName).start(next: { result in
                        guard let result = result as? TONValidatedConfig else {
                            subscriber.putError(.generic)
                            return
                        }
                        subscriber.putNext(WalletValidateConfigResult(defaultWalletId: result.defaultWalletId))
                        subscriber.putCompletion()
                    }, error: { error in
                        guard let _ = error as? TONError else {
                            subscriber.putError(.generic)
                            return
                        }
                        subscriber.putError(.generic)
                    }, completed: nil)
                    disposable.set(ActionDisposable {
                        cancel?.dispose()
                    })
                }
            }
            return disposable
        }
    }
    
    fileprivate func exportKey(key: TONKey, localPassword: Data) -> Signal<[String], NoError> {
        return Signal { subscriber in
            let disposable = MetaDisposable()
            
            self.impl.with { impl in
                impl.withInstance { ton in
                    let cancel = ton.export(key, localPassword: localPassword).start(next: { wordList in
                        guard let wordList = wordList as? [String] else {
                            assertionFailure()
                            return
                        }
                        subscriber.putNext(wordList)
                        subscriber.putCompletion()
                    })
                    disposable.set(ActionDisposable {
                        cancel?.dispose()
                    })
                }
            }
            
            return disposable
        }
    }
    
    fileprivate func createWallet(keychain: TonKeychain, localPassword: Data) -> Signal<(WalletInfo, [String]), CreateWalletError> {
        return Signal { subscriber in
            let disposable = MetaDisposable()
            self.impl.with { impl in
                impl.withInstance { ton in
                    let cancel = ton.createKey(withLocalPassword: localPassword, mnemonicPassword: Data()).start(next: { key in
                        guard let key = key as? TONKey else {
                            assertionFailure()
                            return
                        }
                        let cancel = keychain.encrypt(key.secret).start(next: { encryptedSecretData in
                            let _ = self.exportKey(key: key, localPassword: localPassword).start(next: { wordList in
                                subscriber.putNext((WalletInfo(publicKey: WalletPublicKey(rawValue: key.publicKey), encryptedSecret: encryptedSecretData), wordList))
                                subscriber.putCompletion()
                            }, error: { error in
                                subscriber.putError(.generic)
                            })
                        }, error: { _ in
                            subscriber.putError(.generic)
                        }, completed: {
                        })
                    }, error: { _ in
                    }, completed: {
                    })
                    disposable.set(ActionDisposable {
                        cancel?.dispose()
                    })
                }
            }
            
            return disposable
        }
    }
    
    fileprivate func importWallet(keychain: TonKeychain, wordList: [String], localPassword: Data) -> Signal<WalletInfo, ImportWalletInternalError> {
        return Signal { subscriber in
            let disposable = MetaDisposable()
            
            self.impl.with { impl in
                impl.withInstance { ton in
                    let cancel = ton.importKey(withLocalPassword: localPassword, mnemonicPassword: Data(), wordList: wordList).start(next: { key in
                        guard let key = key as? TONKey else {
                            subscriber.putError(.generic)
                            return
                        }
                        let cancel = keychain.encrypt(key.secret).start(next: { encryptedSecretData in
                            subscriber.putNext(WalletInfo(publicKey: WalletPublicKey(rawValue: key.publicKey), encryptedSecret: encryptedSecretData))
                            subscriber.putCompletion()
                        }, error: { _ in
                            subscriber.putError(.generic)
                        }, completed: {
                        })
                    }, error: { _ in
                        subscriber.putError(.generic)
                    }, completed: {
                    })
                    disposable.set(ActionDisposable {
                        cancel?.dispose()
                    })
                }
            }
            
            return disposable
        }
    }
    
    fileprivate func getInitialWalletId() -> Signal<Int64, WalletValidateConfigError> {
        return Signal { subscriber in
            let disposable = MetaDisposable()
            self.impl.with { impl in
                let config = impl.config
                let blockchainName = impl.blockchainName
                
                impl.withInstance { ton in
                    let cancel = ton.validateConfig(config, blockchainName: blockchainName).start(next: { result in
                        guard let result = result as? TONValidatedConfig else {
                            subscriber.putError(.generic)
                            return
                        }
                        subscriber.putNext(result.defaultWalletId)
                        subscriber.putCompletion()
                    }, error: { error in
                        guard let _ = error as? TONError else {
                            subscriber.putError(.generic)
                            return
                        }
                        subscriber.putError(.generic)
                    }, completed: nil)
                    disposable.set(ActionDisposable {
                        cancel?.dispose()
                    })
                }
            }
            return disposable
        }
    }
    
    fileprivate func walletAddress(publicKey: WalletPublicKey) -> Signal<String, NoError> {
        return self.getInitialWalletId()
        |> `catch` { _ -> Signal<Int64, NoError> in
            return .single(0)
        }
        |> mapToSignal { initialWalletId -> Signal<String, NoError> in
            return Signal { subscriber in
                let disposable = MetaDisposable()
                
                self.impl.with { impl in
                    impl.withInstance { ton in
                        let cancel = ton.getWalletAccountAddress(withPublicKey: publicKey.rawValue, initialWalletId: initialWalletId).start(next: { address in
                            guard let address = address as? String else {
                                return
                            }
                            subscriber.putNext(address)
                            subscriber.putCompletion()
                        }, error: { _ in
                            subscriber.putNext("ERROR")
                            subscriber.putCompletion()
                        }, completed: {
                        })
                        disposable.set(ActionDisposable {
                            cancel?.dispose()
                        })
                    }
                }
                
                return disposable
            }
        }
    }
    
    private func getWalletStateRaw(address: String) -> Signal<TONAccountState, GetWalletStateError> {
        return Signal { subscriber in
            let disposable = MetaDisposable()
            
            self.impl.with { impl in
                impl.withInstance { ton in
                    let cancel = ton.getAccountState(withAddress: address).start(next: { state in
                        guard let state = state as? TONAccountState else {
                            return
                        }
                        subscriber.putNext(state)
                    }, error: { error in
                        if let error = error as? TONError {
                            if error.text.hasPrefix("LITE_SERVER_") {
                                subscriber.putError(.network)
                            } else {
                                subscriber.putError(.generic)
                            }
                        } else {
                            subscriber.putError(.generic)
                        }
                    }, completed: {
                        subscriber.putCompletion()
                    })
                    disposable.set(ActionDisposable {
                        cancel?.dispose()
                    })
                }
            }
            
            return disposable
        }
    }
    
    fileprivate func getWalletState(address: String) -> Signal<(WalletState, Int64), GetWalletStateError> {
        return self.getWalletStateRaw(address: address)
        |> map { state in
            return (WalletState(balance: state.balance, lastTransactionId: state.lastTransactionId.flatMap(WalletTransactionId.init(tonTransactionId:))), state.syncUtime)
        }
    }
    
    fileprivate func walletLastTransactionId(address: String) -> Signal<WalletTransactionId?, WalletLastTransactionIdError> {
        return Signal { subscriber in
            let disposable = MetaDisposable()
            
            self.impl.with { impl in
                impl.withInstance { ton in
                    let cancel = ton.getAccountState(withAddress: address).start(next: { state in
                        guard let state = state as? TONAccountState else {
                            subscriber.putNext(nil)
                            return
                        }
                        subscriber.putNext(state.lastTransactionId.flatMap(WalletTransactionId.init(tonTransactionId:)))
                    }, error: { error in
                        if let error = error as? TONError {
                            if error.text.hasPrefix("LITE_SERVER_") {
                                subscriber.putError(.network)
                            } else {
                                subscriber.putError(.generic)
                            }
                        } else {
                            subscriber.putError(.generic)
                        }
                    }, completed: {
                        subscriber.putCompletion()
                    })
                    disposable.set(ActionDisposable {
                        cancel?.dispose()
                    })
                }
            }
            
            return disposable
        }
    }
    
    fileprivate func getWalletTransactions(address: String, previousId: WalletTransactionId) -> Signal<[WalletTransaction], GetWalletTransactionsError> {
        return Signal { subscriber in
            let disposable = MetaDisposable()
            
            self.impl.with { impl in
                impl.withInstance { ton in
                    let cancel = ton.getTransactionList(withAddress: address, lt: previousId.lt, hash: previousId.transactionHash).start(next: { transactions in
                        guard let transactions = transactions as? [TONTransaction] else {
                            subscriber.putError(.generic)
                            return
                        }
                        subscriber.putNext(transactions.map(WalletTransaction.init(tonTransaction:)))
                    }, error: { error in
                        if let error = error as? TONError {
                            if error.text.hasPrefix("LITE_SERVER_") {
                                subscriber.putError(.network)
                            } else {
                                subscriber.putError(.generic)
                            }
                        } else {
                            subscriber.putError(.generic)
                        }
                    }, completed: {
                        subscriber.putCompletion()
                    })
                    disposable.set(ActionDisposable {
                        cancel?.dispose()
                    })
                }
            }
            
            return disposable
        }
    }
    
    fileprivate func prepareSendGramsFromWalletQuery(decryptedSecret: Data, localPassword: Data, walletInfo: WalletInfo, fromAddress: String, toAddress: String, amount: Int64, textMessage: Data, forceIfDestinationNotInitialized: Bool, timeout: Int32, randomId: Int64) -> Signal<TONPreparedSendGramsQuery, SendGramsFromWalletError> {
        let key = TONKey(publicKey: walletInfo.publicKey.rawValue, secret: decryptedSecret)
        return Signal { subscriber in
            let disposable = MetaDisposable()
            
            self.impl.with { impl in
                impl.withInstance { ton in
                    let cancel = ton.generateSendGramsQuery(from: key, localPassword: localPassword, fromAddress: fromAddress, toAddress: toAddress, amount: amount, textMessage: textMessage, forceIfDestinationNotInitialized: forceIfDestinationNotInitialized, timeout: timeout, randomId: randomId).start(next: { result in
                        guard let result = result as? TONPreparedSendGramsQuery else {
                            subscriber.putError(.generic)
                            return
                        }
                        subscriber.putNext(result)
                        subscriber.putCompletion()
                    }, error: { error in
                        if let error = error as? TONError {
                            if error.text.hasPrefix("INVALID_ACCOUNT_ADDRESS") {
                                subscriber.putError(.invalidAddress)
                            } else if error.text.hasPrefix("DANGEROUS_TRANSACTION") {
                                subscriber.putError(.destinationIsNotInitialized)
                            } else if error.text.hasPrefix("MESSAGE_TOO_LONG") {
                                subscriber.putError(.messageTooLong)
                            } else if error.text.hasPrefix("NOT_ENOUGH_FUNDS") {
                                subscriber.putError(.notEnoughFunds)
                            } else if error.text.hasPrefix("LITE_SERVER_") {
                                subscriber.putError(.network)
                            } else {
                                subscriber.putError(.generic)
                            }
                        } else {
                            subscriber.putError(.generic)
                        }
                    }, completed: {
                        subscriber.putCompletion()
                    })
                    disposable.set(ActionDisposable {
                        cancel?.dispose()
                    })
                }
            }
            
            return disposable
        }
    }
    
    fileprivate func prepareFakeSendGramsFromWalletQuery(walletInfo: WalletInfo, fromAddress: String, toAddress: String, amount: Int64, textMessage: Data, timeout: Int32) -> Signal<TONPreparedSendGramsQuery, SendGramsFromWalletError> {
        return Signal { subscriber in
            let disposable = MetaDisposable()
            
            self.impl.with { impl in
                impl.withInstance { ton in
                    let cancel = ton.generateFakeSendGramsQuery(fromAddress: fromAddress, toAddress: toAddress, amount: amount, textMessage: textMessage, forceIfDestinationNotInitialized: true, timeout: timeout).start(next: { result in
                        guard let result = result as? TONPreparedSendGramsQuery else {
                            subscriber.putError(.generic)
                            return
                        }
                        subscriber.putNext(result)
                        subscriber.putCompletion()
                    }, error: { error in
                        if let error = error as? TONError {
                            if error.text.hasPrefix("INVALID_ACCOUNT_ADDRESS") {
                                subscriber.putError(.invalidAddress)
                            } else if error.text.hasPrefix("DANGEROUS_TRANSACTION") {
                                subscriber.putError(.destinationIsNotInitialized)
                            } else if error.text.hasPrefix("MESSAGE_TOO_LONG") {
                                subscriber.putError(.messageTooLong)
                            } else if error.text.hasPrefix("NOT_ENOUGH_FUNDS") {
                                subscriber.putError(.notEnoughFunds)
                            } else if error.text.hasPrefix("LITE_SERVER_") {
                                subscriber.putError(.network)
                            } else {
                                subscriber.putError(.generic)
                            }
                        } else {
                            subscriber.putError(.generic)
                        }
                    }, completed: {
                        subscriber.putCompletion()
                    })
                    disposable.set(ActionDisposable {
                        cancel?.dispose()
                    })
                }
            }
            
            return disposable
        }
    }
    
    fileprivate func estimateSendGramsQueryFees(preparedQuery: TONPreparedSendGramsQuery) -> Signal<TONSendGramsQueryFees, SendGramsFromWalletError> {
        return Signal { subscriber in
            let disposable = MetaDisposable()
            
            self.impl.with { impl in
                impl.withInstance { ton in
                    let cancel = ton.estimateSendGramsQueryFees(preparedQuery).start(next: { result in
                        guard let result = result as? TONSendGramsQueryFees else {
                            subscriber.putError(.generic)
                            return
                        }
                        subscriber.putNext(result)
                        subscriber.putCompletion()
                    }, error: { error in
                        if let error = error as? TONError {
                            if error.text.hasPrefix("INVALID_ACCOUNT_ADDRESS") {
                                subscriber.putError(.invalidAddress)
                            } else if error.text.hasPrefix("DANGEROUS_TRANSACTION") {
                                subscriber.putError(.destinationIsNotInitialized)
                            } else if error.text.hasPrefix("MESSAGE_TOO_LONG") {
                                subscriber.putError(.messageTooLong)
                            } else if error.text.hasPrefix("NOT_ENOUGH_FUNDS") {
                                subscriber.putError(.notEnoughFunds)
                            } else if error.text.hasPrefix("LITE_SERVER_") {
                                subscriber.putError(.network)
                            } else {
                                subscriber.putError(.generic)
                            }
                        } else {
                            subscriber.putError(.generic)
                        }
                    }, completed: nil)
                    disposable.set(ActionDisposable {
                        cancel?.dispose()
                    })
                }
            }
            
            return disposable
        }
    }
    
    fileprivate func commitPreparedSendGramsQuery(_ preparedQuery: TONPreparedSendGramsQuery) -> Signal<Never, SendGramsFromWalletError> {
        return Signal { subscriber in
            let disposable = MetaDisposable()
            
            self.impl.with { impl in
                impl.withInstance { ton in
                    let cancel = ton.commit(preparedQuery).start(next: { result in
                        preconditionFailure()
                    }, error: { error in
                        if let error = error as? TONError {
                            if error.text.hasPrefix("INVALID_ACCOUNT_ADDRESS") {
                                subscriber.putError(.invalidAddress)
                            } else if error.text.hasPrefix("DANGEROUS_TRANSACTION") {
                                subscriber.putError(.destinationIsNotInitialized)
                            } else if error.text.hasPrefix("MESSAGE_TOO_LONG") {
                                subscriber.putError(.messageTooLong)
                            } else if error.text.hasPrefix("NOT_ENOUGH_FUNDS") {
                                subscriber.putError(.notEnoughFunds)
                            } else if error.text.hasPrefix("LITE_SERVER_") {
                                subscriber.putError(.network)
                            } else {
                                subscriber.putError(.generic)
                            }
                        } else {
                            subscriber.putError(.generic)
                        }
                    }, completed: {
                        subscriber.putCompletion()
                    })
                    disposable.set(ActionDisposable {
                        cancel?.dispose()
                    })
                }
            }
            
            return disposable
        }
    }
    
    fileprivate func walletRestoreWords(publicKey: WalletPublicKey, decryptedSecret: Data, localPassword: Data) -> Signal<[String], WalletRestoreWordsError> {
        return Signal { subscriber in
            let disposable = MetaDisposable()
            
            self.impl.with { impl in
                impl.withInstance { ton in
                    let cancel = ton.export(TONKey(publicKey: publicKey.rawValue, secret: decryptedSecret), localPassword: localPassword).start(next: { wordList in
                        guard let wordList = wordList as? [String] else {
                            subscriber.putError(.generic)
                            return
                        }
                        subscriber.putNext(wordList)
                    }, error: { _ in
                        subscriber.putError(.generic)
                    }, completed: {
                        subscriber.putCompletion()
                    })
                    disposable.set(ActionDisposable {
                        cancel?.dispose()
                    })
                }
            }
            
            return disposable
        }
    }
    
    fileprivate func deleteAllLocalWalletsData() -> Signal<Never, DeleteAllLocalWalletsDataError> {
        return Signal { subscriber in
            let disposable = MetaDisposable()
            
            self.impl.with { impl in
                impl.withInstance { ton in
                    let cancel = ton.deleteAllKeys().start(next: { _ in
                        assertionFailure()
                    }, error: { _ in
                        subscriber.putError(.generic)
                    }, completed: {
                        subscriber.putCompletion()
                    })
                    disposable.set(ActionDisposable {
                        cancel?.dispose()
                    })
                }
            }
            
            return disposable
        }
    }
    fileprivate func encrypt(_ decryptedData: Data, secret: Data) -> Signal<Data, NoError> {
        return Signal { subscriber in
            let disposable = MetaDisposable()
            
            self.impl.with { impl in
                impl.withInstance { ton in
                    subscriber.putNext(ton.encrypt(decryptedData, secret: secret))
                    subscriber.putCompletion()
                }
            }
            
            return disposable
        }
    }
    fileprivate func decrypt(_ encryptedData: Data, secret: Data) -> Signal<Data?, NoError> {
        return Signal { subscriber in
            let disposable = MetaDisposable()
            
            self.impl.with { impl in
                impl.withInstance { ton in
                    subscriber.putNext(ton.decrypt(encryptedData, secret: secret))
                    subscriber.putCompletion()
                }
            }
            
            return disposable
        }
    }
}

public struct WalletPublicKey: Codable, Hashable {
    public var rawValue: String
    
    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

public struct WalletInfo: Codable, Equatable {
    public let publicKey: WalletPublicKey
    public let encryptedSecret: TonKeychainEncryptedData
    
    public init(publicKey: WalletPublicKey, encryptedSecret: TonKeychainEncryptedData) {
        self.publicKey = publicKey
        self.encryptedSecret = encryptedSecret
    }
}

public struct CombinedWalletState: Codable, Equatable {
    public var walletState: WalletState
    public var timestamp: Int64
    public var topTransactions: [WalletTransaction]
    public var pendingTransactions: [PendingWalletTransaction]
}

public struct WalletStateRecord: Codable, Equatable {
    public let info: WalletInfo
    public var exportCompleted: Bool
    public var state: CombinedWalletState?
    
    public init(info: WalletInfo, exportCompleted: Bool, state: CombinedWalletState?) {
        self.info = info
        self.exportCompleted = exportCompleted
        self.state = state
    }
}

public enum CreateWalletError {
    case generic
}

public func tonlibEncrypt(tonInstance: TonInstance, decryptedData: Data, secret: Data) -> Signal<Data, NoError> {
    return tonInstance.encrypt(decryptedData, secret: secret)
}
public func tonlibDecrypt(tonInstance: TonInstance, encryptedData: Data, secret: Data) -> Signal<Data?, NoError> {
    return tonInstance.decrypt(encryptedData, secret: secret)
}

public func createWallet(storage: WalletStorageInterface, tonInstance: TonInstance, keychain: TonKeychain, localPassword: Data) -> Signal<(WalletInfo, [String]), CreateWalletError> {
    return tonInstance.createWallet(keychain: keychain, localPassword: localPassword)
    |> mapToSignal { walletInfo, wordList -> Signal<(WalletInfo, [String]), CreateWalletError> in
        return storage.updateWalletRecords({ records in
            var records = records
            records.append(WalletStateRecord(info: walletInfo, exportCompleted: false, state: nil))
            return records
        })
        |> map { _ -> (WalletInfo, [String]) in
            return (walletInfo, wordList)
        }
        |> castError(CreateWalletError.self)
    }
}

public func confirmWalletExported(storage: WalletStorageInterface, publicKey: WalletPublicKey) -> Signal<Never, NoError> {
    return storage.updateWalletRecords { records in
        var records = records
        for i in 0 ..< records.count {
            if records[i].info.publicKey == publicKey {
                records[i].exportCompleted = true
            }
        }
        return records
    }
    |> ignoreValues
}

private enum ImportWalletInternalError {
    case generic
}

public enum ImportWalletError {
    case generic
}

public func importWallet(storage: WalletStorageInterface, tonInstance: TonInstance, keychain: TonKeychain, wordList: [String], localPassword: Data) -> Signal<WalletInfo, ImportWalletError> {
    return tonInstance.importWallet(keychain: keychain, wordList: wordList, localPassword: localPassword)
    |> `catch` { error -> Signal<WalletInfo, ImportWalletError> in
        switch error {
        case .generic:
            return .fail(.generic)
        }
    }
    |> mapToSignal { walletInfo -> Signal<WalletInfo, ImportWalletError> in
        return storage.updateWalletRecords { records in
            var records = records
            records.append(WalletStateRecord(info: walletInfo, exportCompleted: true, state: nil))
            return records
        }
        |> map { _ -> WalletInfo in
            return walletInfo
        }
        |> castError(ImportWalletError.self)
    }
}

public enum DeleteAllLocalWalletsDataError {
    case generic
}

public func deleteAllLocalWalletsData(storage: WalletStorageInterface, tonInstance: TonInstance) -> Signal<Never, DeleteAllLocalWalletsDataError> {
    return tonInstance.deleteAllLocalWalletsData()
    |> `catch` { _ -> Signal<Never, DeleteAllLocalWalletsDataError> in
        return .complete()
    }
    |> then(
        storage.updateWalletRecords { _ in [] }
        |> castError(DeleteAllLocalWalletsDataError.self)
        |> ignoreValues
    )
}

public enum WalletRestoreWordsError {
    case generic
}

public func walletRestoreWords(tonInstance: TonInstance, publicKey: WalletPublicKey, decryptedSecret: Data, localPassword: Data) -> Signal<[String], WalletRestoreWordsError> {
    return tonInstance.walletRestoreWords(publicKey: publicKey, decryptedSecret: decryptedSecret, localPassword: localPassword)
}

public struct WalletState: Codable, Equatable {
    public let balance: Int64
    public let lastTransactionId: WalletTransactionId?
    
    public init(balance: Int64, lastTransactionId: WalletTransactionId?) {
        self.balance = balance
        self.lastTransactionId = lastTransactionId
    }
}

public func walletAddress(publicKey: WalletPublicKey, tonInstance: TonInstance) -> Signal<String, NoError> {
    return tonInstance.walletAddress(publicKey: publicKey)
}

private enum GetWalletStateError {
    case generic
    case network
}

private func getWalletState(address: String, tonInstance: TonInstance) -> Signal<(WalletState, Int64), GetWalletStateError> {
    return tonInstance.getWalletState(address: address)
}

public enum GetCombinedWalletStateError {
    case generic
    case network
}

public enum CombinedWalletStateResult {
    case cached(CombinedWalletState?)
    case updated(CombinedWalletState)
}

public enum CombinedWalletStateSubject {
    case wallet(WalletInfo)
    case address(String)
}

public func getCombinedWalletState(storage: WalletStorageInterface, subject: CombinedWalletStateSubject, tonInstance: TonInstance, onlyCached: Bool = false) -> Signal<CombinedWalletStateResult, GetCombinedWalletStateError> {
    switch subject {
    case let .wallet(walletInfo):
        return storage.getWalletRecords()
        |> map { records -> CombinedWalletState? in
            for item in records {
                if item.info.publicKey == walletInfo.publicKey {
                    return item.state
                }
            }
            return nil
        }
        |> castError(GetCombinedWalletStateError.self)
        |> mapToSignal { cachedState -> Signal<CombinedWalletStateResult, GetCombinedWalletStateError> in
            if onlyCached {
                return .single(.cached(cachedState))
            }
            return .single(.cached(cachedState))
            |> then(
                tonInstance.walletAddress(publicKey: walletInfo.publicKey)
                |> castError(GetCombinedWalletStateError.self)
                |> mapToSignal { address -> Signal<CombinedWalletStateResult, GetCombinedWalletStateError> in
                    
                    let walletState: Signal<(WalletState, Int64), GetCombinedWalletStateError>
                    if cachedState == nil {
                        walletState = getWalletState(address: address, tonInstance: tonInstance)
                        |> retry(1.0, maxDelay: 5.0, onQueue: .concurrentDefaultQueue())
                        |> castError(GetCombinedWalletStateError.self)
                    } else {
                        walletState = getWalletState(address: address, tonInstance: tonInstance)
                        |> retryTonRequest(isNetworkError: { error in
                            if case .network = error {
                                return true
                            } else {
                                return false
                            }
                        })
                        |> mapError { error -> GetCombinedWalletStateError in
                            if case .network = error {
                                return .network
                            } else {
                                return .generic
                            }
                        }
                    }
                    
                    return walletState
                    |> mapToSignal { walletState, syncUtime -> Signal<CombinedWalletStateResult, GetCombinedWalletStateError> in
                        let topTransactions: Signal<[WalletTransaction], GetCombinedWalletStateError>
                        if walletState.lastTransactionId == cachedState?.walletState.lastTransactionId {
                            topTransactions = .single(cachedState?.topTransactions ?? [])
                        } else {
                            if cachedState == nil {
                                topTransactions = getWalletTransactions(address: address, previousId: nil, tonInstance: tonInstance)
                                |> retry(1.0, maxDelay: 5.0, onQueue: .concurrentDefaultQueue())
                                |> castError(GetCombinedWalletStateError.self)
                            } else {
                                topTransactions = getWalletTransactions(address: address, previousId: nil, tonInstance: tonInstance)
                                |> mapError { error -> GetCombinedWalletStateError in
                                    if case .network = error {
                                        return .network
                                    } else {
                                        return .generic
                                    }
                                }
                            }
                        }
                        return topTransactions
                        |> mapToSignal { topTransactions -> Signal<CombinedWalletStateResult, GetCombinedWalletStateError> in
                            let lastTransactionTimestamp = topTransactions.last?.timestamp
                            var listTransactionBodyHashes = Set<Data>()
                            for transaction in topTransactions {
                                if let message = transaction.inMessage {
                                    listTransactionBodyHashes.insert(message.bodyHash)
                                }
                                for message in transaction.outMessages {
                                    listTransactionBodyHashes.insert(message.bodyHash)
                                }
                            }
                            let pendingTransactions = (cachedState?.pendingTransactions ?? []).filter { transaction in
                                if transaction.validUntilTimestamp <= syncUtime {
                                    return false
                                } else if let lastTransactionTimestamp = lastTransactionTimestamp, transaction.validUntilTimestamp <= lastTransactionTimestamp {
                                    return false
                                } else {
                                    if listTransactionBodyHashes.contains(transaction.bodyHash) {
                                        return false
                                    }
                                    return true
                                }
                            }
                            let combinedState = CombinedWalletState(walletState: walletState, timestamp: syncUtime, topTransactions: topTransactions, pendingTransactions: pendingTransactions)
                            
                            return storage.updateWalletRecords { records in
                                var records = records
                                for i in 0 ..< records.count {
                                    if records[i].info.publicKey == walletInfo.publicKey {
                                        records[i].state = combinedState
                                    }
                                }
                                return records
                            }
                            |> map { _ -> CombinedWalletStateResult in
                                return .updated(combinedState)
                            }
                            |> castError(GetCombinedWalletStateError.self)
                        }
                    }
                }
            )
        }
    case let .address(address):
        let updated = getWalletState(address: address, tonInstance: tonInstance)
        |> mapError { _ -> GetCombinedWalletStateError in
            return .generic
        }
        |> mapToSignal { walletState, syncUtime -> Signal<CombinedWalletStateResult, GetCombinedWalletStateError> in
            let topTransactions: Signal<[WalletTransaction], GetCombinedWalletStateError>
            
            topTransactions = getWalletTransactions(address: address, previousId: nil, tonInstance: tonInstance)
            |> mapError { _ -> GetCombinedWalletStateError in
                return .generic
            }
            return topTransactions
            |> mapToSignal { topTransactions -> Signal<CombinedWalletStateResult, GetCombinedWalletStateError> in
                let combinedState = CombinedWalletState(walletState: walletState, timestamp: syncUtime, topTransactions: topTransactions, pendingTransactions: [])
                return .single(.updated(combinedState))
            }
        }
        return .single(.cached(nil))
        |> then(updated)
    }
}

public enum SendGramsFromWalletError {
    case generic
    case secretDecryptionFailed
    case invalidAddress
    case destinationIsNotInitialized
    case messageTooLong
    case notEnoughFunds
    case network
}

public struct EstimatedSendGramsFees {
    public let inFwdFee: Int64
    public let storageFee: Int64
    public let gasFee: Int64
    public let fwdFee: Int64
}

public func verifySendGramsRequestAndEstimateFees(tonInstance: TonInstance, walletInfo: WalletInfo, toAddress: String, amount: Int64, textMessage: Data, timeout: Int32) -> Signal<EstimatedSendGramsFees, SendGramsFromWalletError> {
    return walletAddress(publicKey: walletInfo.publicKey, tonInstance: tonInstance)
    |> castError(SendGramsFromWalletError.self)
    |> mapToSignal { fromAddress -> Signal<EstimatedSendGramsFees, SendGramsFromWalletError> in
        return tonInstance.prepareFakeSendGramsFromWalletQuery(walletInfo: walletInfo, fromAddress: fromAddress, toAddress: toAddress, amount: amount, textMessage: textMessage, timeout: timeout)
        |> mapToSignal { preparedQuery -> Signal<EstimatedSendGramsFees, SendGramsFromWalletError> in
            return tonInstance.estimateSendGramsQueryFees(preparedQuery: preparedQuery)
            |> map { result -> EstimatedSendGramsFees in
                return EstimatedSendGramsFees(inFwdFee: result.sourceFees.inFwdFee, storageFee: result.sourceFees.storageFee, gasFee: result.sourceFees.gasFee, fwdFee: result.sourceFees.fwdFee)
            }
        }
    }
}

public func sendGramsFromWallet(storage: WalletStorageInterface, tonInstance: TonInstance, walletInfo: WalletInfo, decryptedSecret: Data, localPassword: Data, toAddress: String, amount: Int64, textMessage: Data, forceIfDestinationNotInitialized: Bool, timeout: Int32, randomId: Int64) -> Signal<PendingWalletTransaction, SendGramsFromWalletError> {
    return walletAddress(publicKey: walletInfo.publicKey, tonInstance: tonInstance)
    |> castError(SendGramsFromWalletError.self)
    |> mapToSignal { fromAddress -> Signal<PendingWalletTransaction, SendGramsFromWalletError> in
        return tonInstance.prepareSendGramsFromWalletQuery(decryptedSecret: decryptedSecret, localPassword: localPassword, walletInfo: walletInfo, fromAddress: fromAddress, toAddress: toAddress, amount: amount, textMessage: textMessage, forceIfDestinationNotInitialized: forceIfDestinationNotInitialized, timeout: timeout, randomId: randomId)
        |> mapToSignal { preparedQuery -> Signal<PendingWalletTransaction, SendGramsFromWalletError> in
            return tonInstance.commitPreparedSendGramsQuery(preparedQuery)
            |> retryTonRequest(isNetworkError: { error in
                if case .network = error {
                    return true
                } else {
                    return false
                }
            })
            |> mapToSignal { _ -> Signal<PendingWalletTransaction, SendGramsFromWalletError> in
                return .complete()
            }
            |> then(.single(PendingWalletTransaction(timestamp: Int64(Date().timeIntervalSince1970), validUntilTimestamp: preparedQuery.validUntil, bodyHash: preparedQuery.bodyHash, address: toAddress, value: amount, comment: textMessage)))
            |> mapToSignal { result in
                return storage.updateWalletRecords { records in
                    var records = records
                    for i in 0 ..< records.count {
                        if records[i].info.publicKey == walletInfo.publicKey {
                            if var state = records[i].state {
                                state.pendingTransactions.insert(result, at: 0)
                                records[i].state = state
                            }
                        }
                    }
                    return records
                }
                |> map { _ -> PendingWalletTransaction in
                    return result
                }
                |> castError(SendGramsFromWalletError.self)
            }
        }
    }
}

public struct WalletTransactionId: Codable, Hashable {
    public var lt: Int64
    public var transactionHash: Data
}

private extension WalletTransactionId {
    init(tonTransactionId: TONTransactionId) {
        self.lt = tonTransactionId.lt
        self.transactionHash = tonTransactionId.transactionHash
    }
}

public final class WalletTransactionMessage: Codable, Equatable {
    public let value: Int64
    public let source: String
    public let destination: String
    public let textMessage: String
    public let bodyHash: Data
    
    init(value: Int64, source: String, destination: String, textMessage: String, bodyHash: Data) {
        self.value = value
        self.source = source
        self.destination = destination
        self.textMessage = textMessage
        self.bodyHash = bodyHash
    }
    
    public static func ==(lhs: WalletTransactionMessage, rhs: WalletTransactionMessage) -> Bool {
        if lhs.value != rhs.value {
            return false
        }
        if lhs.source != rhs.source {
            return false
        }
        if lhs.destination != rhs.destination {
            return false
        }
        if lhs.textMessage != rhs.textMessage {
            return false
        }
        if lhs.bodyHash != rhs.bodyHash {
            return false
        }
        return true
    }
}

private extension WalletTransactionMessage {
    convenience init(tonTransactionMessage: TONTransactionMessage) {
        self.init(value: tonTransactionMessage.value, source: tonTransactionMessage.source, destination: tonTransactionMessage.destination, textMessage: tonTransactionMessage.textMessage, bodyHash: tonTransactionMessage.bodyHash)
    }
}

public final class PendingWalletTransaction: Codable, Equatable {
    public let timestamp: Int64
    public let validUntilTimestamp: Int64
    public let bodyHash: Data
    public let address: String
    public let value: Int64
    public let comment: Data
    
    public init(timestamp: Int64, validUntilTimestamp: Int64, bodyHash: Data, address: String, value: Int64, comment: Data) {
        self.timestamp = timestamp
        self.validUntilTimestamp = validUntilTimestamp
        self.bodyHash = bodyHash
        self.address = address
        self.value = value
        self.comment = comment
    }
    
    public static func ==(lhs: PendingWalletTransaction, rhs: PendingWalletTransaction) -> Bool {
        if lhs.timestamp != rhs.timestamp {
            return false
        }
        if lhs.validUntilTimestamp != rhs.validUntilTimestamp {
            return false
        }
        if lhs.bodyHash != rhs.bodyHash {
            return false
        }
        if lhs.value != rhs.value {
            return false
        }
        if lhs.comment != rhs.comment {
            return false
        }
        return true
    }
}

public final class WalletTransaction: Codable, Equatable {
    public let data: Data
    public let transactionId: WalletTransactionId
    public let timestamp: Int64
    public let storageFee: Int64
    public let otherFee: Int64
    public let inMessage: WalletTransactionMessage?
    public let outMessages: [WalletTransactionMessage]
    
    public var transferredValueWithoutFees: Int64 {
        var value: Int64 = 0
        if let inMessage = self.inMessage {
            value += inMessage.value
        }
        for message in self.outMessages {
            value -= message.value
        }
        return value
    }
    
    init(data: Data, transactionId: WalletTransactionId, timestamp: Int64, storageFee: Int64, otherFee: Int64, inMessage: WalletTransactionMessage?, outMessages: [WalletTransactionMessage]) {
        self.data = data
        self.transactionId = transactionId
        self.timestamp = timestamp
        self.storageFee = storageFee
        self.otherFee = otherFee
        self.inMessage = inMessage
        self.outMessages = outMessages
    }
    
    public static func ==(lhs: WalletTransaction, rhs: WalletTransaction) -> Bool {
        if lhs.data != rhs.data {
            return false
        }
        if lhs.transactionId != rhs.transactionId {
            return false
        }
        if lhs.timestamp != rhs.timestamp {
            return false
        }
        if lhs.storageFee != rhs.storageFee {
            return false
        }
        if lhs.otherFee != rhs.otherFee {
            return false
        }
        if lhs.inMessage != rhs.inMessage {
            return false
        }
        if lhs.outMessages != rhs.outMessages {
            return false
        }
        return true
    }
}

private extension WalletTransaction {
    convenience init(tonTransaction: TONTransaction) {
        self.init(data: tonTransaction.data, transactionId: WalletTransactionId(tonTransactionId: tonTransaction.transactionId), timestamp: tonTransaction.timestamp, storageFee: tonTransaction.storageFee, otherFee: tonTransaction.otherFee, inMessage: tonTransaction.inMessage.flatMap(WalletTransactionMessage.init(tonTransactionMessage:)), outMessages: tonTransaction.outMessages.map(WalletTransactionMessage.init(tonTransactionMessage:)))
    }
}

public enum GetWalletTransactionsError {
    case generic
    case network
}

public func getWalletTransactions(address: String, previousId: WalletTransactionId?, tonInstance: TonInstance) -> Signal<[WalletTransaction], GetWalletTransactionsError> {
    return getWalletTransactionsOnce(address: address, previousId: previousId, tonInstance: tonInstance)
    |> mapToSignal { transactions in
        guard let lastTransaction = transactions.last, transactions.count >= 2 else {
            return .single(transactions)
        }
        return getWalletTransactionsOnce(address: address, previousId: lastTransaction.transactionId, tonInstance: tonInstance)
        |> map { additionalTransactions in
            var result = transactions
            var existingIds = Set(result.map { $0.transactionId })
            for transaction in additionalTransactions {
                if !existingIds.contains(transaction.transactionId) {
                    existingIds.insert(transaction.transactionId)
                    result.append(transaction)
                }
            }
            return result
        }
    }
}

private func retryTonRequest<T, E>(isNetworkError: @escaping (E) -> Bool) -> (Signal<T, E>) -> Signal<T, E> {
    return { signal in
        return signal
        |> retry(retryOnError: isNetworkError, delayIncrement: 0.2, maxDelay: 5.0, maxRetries: 3, onQueue: Queue.concurrentDefaultQueue())
    }
}

private enum WalletLastTransactionIdError {
    case generic
    case network
}

private func getWalletTransactionsOnce(address: String, previousId: WalletTransactionId?, tonInstance: TonInstance) -> Signal<[WalletTransaction], GetWalletTransactionsError> {
    let previousIdValue: Signal<WalletTransactionId?, GetWalletTransactionsError>
    if let previousId = previousId {
        previousIdValue = .single(previousId)
    } else {
        previousIdValue = tonInstance.walletLastTransactionId(address: address)
        |> retryTonRequest(isNetworkError: { error in
            if case .network = error {
                return true
            } else {
                return false
            }
        })
        |> mapError { error -> GetWalletTransactionsError in
            if case .network = error {
                return .network
            } else {
                return .generic
            }
        }
    }
    return previousIdValue
    |> mapToSignal { previousId in
        if let previousId = previousId {
            return tonInstance.getWalletTransactions(address: address, previousId: previousId)
            |> retryTonRequest(isNetworkError: { error in
                if case .network = error {
                    return true
                } else {
                    return false
                }
            })
        } else {
            return .single([])
        }
    }
}

public enum LocalWalletConfigurationDecodingError: Error {
    case generic
}

public enum LocalWalletConfigurationSource: Codable, Equatable {
    enum Key: CodingKey {
        case url
        case string
    }
    
    case url(String)
    case string(String)
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Key.self)
        if let url = try? container.decode(String.self, forKey: .url) {
            self = .url(url)
        } else if let string = try? container.decode(String.self, forKey: .string) {
            self = .string(string)
        } else {
            throw LocalWalletConfigurationDecodingError.generic
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = try encoder.container(keyedBy: Key.self)
        switch self {
        case let .url(url):
            try container.encode(url, forKey: .url)
        case let .string(string):
            try container.encode(string, forKey: .string)
        }
    }
}

public struct LocalWalletConfiguration: Codable, Equatable {
    public var source: LocalWalletConfigurationSource
    public var blockchainName: String
    
    public init(source: LocalWalletConfigurationSource, blockchainName: String) {
        self.source = source
        self.blockchainName = blockchainName
    }
}

public protocol WalletStorageInterface {
    func watchWalletRecords() -> Signal<[WalletStateRecord], NoError>
    func getWalletRecords() -> Signal<[WalletStateRecord], NoError>
    func updateWalletRecords(_ f: @escaping ([WalletStateRecord]) -> [WalletStateRecord]) -> Signal<[WalletStateRecord], NoError>
    func localWalletConfiguration() -> Signal<LocalWalletConfiguration, NoError>
    func updateLocalWalletConfiguration(_ f: @escaping (LocalWalletConfiguration) -> LocalWalletConfiguration) -> Signal<Never, NoError>
}

public struct WalletValidateConfigResult {
    public var defaultWalletId: Int64
}

public enum WalletValidateConfigError {
    case generic
    
}
