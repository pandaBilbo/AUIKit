//
//  AUIMapCollection.swift
//  AUIKitCore
//
//  Created by wushengtao on 2024/1/4.
//

import Foundation

private func aui_map_log(_ text: String) {
    aui_info(text, tag: "aui_collection_map")
}

private func aui_map_warn(_ text: String) {
    aui_warn(text, tag: "aui_collection_map")
}

public class AUIMapCollection: NSObject {
    private var channelName: String
    private var observeKey: String
    private var rtmManager: AUIRtmManager
    private var currentMap: [String: Any] = [:]
    private var metadataWillUpdateColsure: AUICollectionUpdateClosure?
    private var metadataWillMergeColsure: AUICollectionUpdateClosure?
    
    deinit {
        rtmManager.unsubscribeAttributes(channelName: channelName, itemKey: observeKey, delegate: self)
        rtmManager.unsubscribeMessage(channelName: channelName, delegate: self)
        aui_map_log("deinit AUIMapCollection")
    }
    
    public required init(channelName: String, observeKey: String, rtmManager: AUIRtmManager) {
        self.rtmManager = rtmManager
        self.observeKey = observeKey
        self.channelName = channelName
        super.init()
        rtmManager.subscribeAttributes(channelName: channelName, itemKey: observeKey, delegate: self)
        rtmManager.subscribeMessage(channelName: channelName, delegate: self)
        aui_map_log("init AUIMapCollection")
    }
}

//MARK: IAUICollection
extension AUIMapCollection: IAUICollection {
    /*
     上层service调用(例如麦位Service)
     collection.subscribeWillSet { publisher, newValue, oldValue in
        if oldValue["owner"] != nil, newValue["owner"] == nil {
            //踢人，需要判断publisher是否是owner.userId一致
        }
     }
     */
    public func subscribeWillUpdate(callback: AUICollectionUpdateClosure?) {
        self.metadataWillUpdateColsure = callback
    }
    
    public func subscribeWillMerge(callback: AUICollectionUpdateClosure?) {
        self.metadataWillMergeColsure = callback
    }
    
    public func getMetaData(callback: AUICollectionGetClosure?) {
        aui_map_log("getMetaData")
        self.rtmManager.getMetadata(channelName: self.channelName) {[weak self] error, map in
            aui_map_log("getMetaData completion: \(error?.localizedDescription ?? "success")")
            guard let self = self else {return}
            if let error = error {
                //TODO: error
                callback?(error, nil)
                return
            }
            
            guard let jsonStr = map?[self.observeKey],
                  let jsonDict = decodeToJsonObj(jsonStr) as? [String: Any] else {
                //TODO: error
                callback?(nil, nil)
                return
            }
            
            callback?(nil, jsonDict)
        }
    }
    
    /// 更新，替换根节点
    /// - Parameters:
    ///   - valueCmd: 命令类型
    ///   - value: <#value description#>
    ///   - filter: <#objectId description#>
    ///   - callback: <#callback description#>
    public func updateMetaData(valueCmd: String?,
                               value: [String: Any],
                               filter: [[String: Any]]?,
                               callback: ((NSError?)->())?) {
        if AUIRoomContext.shared.getArbiter(channelName: channelName)?.isArbiter() ?? false {
            let currentUserId = AUIRoomContext.shared.currentUserInfo.userId
            rtmSetMetaData(publisherId: currentUserId,
                           valueCmd: valueCmd,
                           value: value,
                           callback: callback)
            return
        }
        
        let payload = AUICollectionMessagePayload(type: .update, 
                                                  dataCmd: valueCmd,
                                                  data: AUIAnyType(map: value))
        let message = AUICollectionMessage(channelName: channelName,
                                           messageType: AUIMessageType.normal,
                                           sceneKey: observeKey,
                                           uniqueId: UUID().uuidString,
                                           payload: payload)

        guard let jsonStr = encodeModelToJsonStr(message) else {
            callback?(NSError.auiError("updateMetaData fail"))
            return
        }
        let userId = AUIRoomContext.shared.getArbiter(channelName: channelName)?.lockOwnerId ?? ""
        rtmManager.publishAndWaitReceipt(userId: userId,
                                         channelName: channelName,
                                         message: jsonStr,
                                         uniqueId: message.uniqueId ?? "",
                                         completion: callback)
    }
    
    /// 合并，替换所有子节点
    /// - Parameters:
    ///   - valueCmd: <#valueCmd description#>
    ///   - value: <#value description#>
    ///   - filter: <#objectId description#>
    ///   - callback: <#callback description#>
    public func mergeMetaData(valueCmd: String?,
                              value: [String: Any],
                              filter: [[String: Any]]?,
                              callback: ((NSError?)->())?) {
        if AUIRoomContext.shared.getArbiter(channelName: channelName)?.isArbiter() ?? false {
            let currentUserId = AUIRoomContext.shared.currentUserInfo.userId
            rtmMergeMetaData(publisherId: currentUserId, 
                             valueCmd: valueCmd,
                             value: value,
                             callback: callback)
            return
        }
        
        let payload = AUICollectionMessagePayload(type: .merge, 
                                                  dataCmd: valueCmd,
                                                  data: AUIAnyType(map: value))
        let message = AUICollectionMessage(channelName: channelName,
                                           messageType: AUIMessageType.normal,
                                           sceneKey: observeKey,
                                           uniqueId: UUID().uuidString,
                                           payload: payload)

        guard let jsonStr = encodeModelToJsonStr(message) else {
            callback?(NSError.auiError("updateMetaData fail"))
            return
        }
        let userId = AUIRoomContext.shared.getArbiter(channelName: channelName)?.lockOwnerId ?? ""
        rtmManager.publishAndWaitReceipt(userId: userId,
                                         channelName: channelName,
                                         message: jsonStr,
                                         uniqueId: message.uniqueId ?? "",
                                         completion: callback)
    }
    
    
    /// 添加，mapCollection等价于update metadata
    /// - Parameter value: <#value description#>
    public func addMetaData(valueCmd: String?, 
                            value: [String: Any], 
                            filter: [[String: Any]]?,
                            callback: ((NSError?)->())?) {
        updateMetaData(valueCmd: valueCmd, 
                       value: value,
                       filter: filter,
                       callback: callback)
    }
    
    /// 移除，map collection不支持
    /// - Parameters:
    ///   - valueCmd: <#value description#>
    ///   - filter: <#value description#>
    ///   - callback: <#callback description#>
    public func removeMetaData(valueCmd: String?, 
                               filter: [[String: Any]]?,
                               callback: ((NSError?)->())?) {
        callback?(NSError.auiError("unsupport method"))
    }
    
    
    /// 清理，map collection就是删除该key
    /// - Parameter callback: <#callback description#>
    public func cleanMetaData(callback: ((NSError?)->())?) {
        if AUIRoomContext.shared.getArbiter(channelName: channelName)?.isArbiter() ?? false {
            rtmCleanMetaData(callback: callback)
            return
        }
        
        let payload = AUICollectionMessagePayload(type: .clean, data: nil)
        let message = AUICollectionMessage(channelName: channelName,
                                           messageType: AUIMessageType.normal,
                                           sceneKey: observeKey,
                                           uniqueId: UUID().uuidString,
                                           payload: payload)
        
        guard let jsonStr = encodeModelToJsonStr(message) else {
            callback?(NSError.auiError("removeMetaData fail"))
            return
        }
        let userId = AUIRoomContext.shared.getArbiter(channelName: channelName)?.lockOwnerId ?? ""
        rtmManager.publishAndWaitReceipt(userId: userId,
                                         channelName: channelName,
                                         message: jsonStr,
                                         uniqueId: message.uniqueId ?? "",
                                         completion: callback)
    }
}

//MARK: private
extension AUIMapCollection {
    private func rtmSetMetaData(publisherId: String,
                                valueCmd: String?,
                                value: [String: Any],
                                callback: ((NSError?)->())?) {
        if let err = self.metadataWillUpdateColsure?(publisherId, valueCmd, value, currentMap) {
            callback?(err)
            return
        }
        
        var map = currentMap
        value.forEach { (key: String, value: Any) in
            map[key] = value
        }
        guard let value = encodeToJsonStr(map) else {
            callback?(NSError.auiError("rtmSetMetaData fail"))
            return
        }
        currentMap = map
        aui_map_log("rtmSetMetaData valueCmd: \(valueCmd ?? "") value: \(value)")
        self.rtmManager.setBatchMetadata(channelName: channelName,
                                         lockName: kRTM_Referee_LockName,
                                         metadata: [observeKey: value]) { error in
            aui_map_log("rtmSetMetaData completion: \(error?.localizedDescription ?? "success")")
            callback?(error)
        }
    }
    
    private func rtmMergeMetaData(publisherId: String,
                                  valueCmd: String?,
                                  value: [String: Any],
                                  callback: ((NSError?)->())?) {
        if let err = self.metadataWillMergeColsure?(publisherId, valueCmd, value, currentMap) {
            callback?(err)
            return
        }
        
        let map = mergeMap(origMap: currentMap, newMap: value)
        guard let value = encodeToJsonStr(map) else {
            callback?(NSError.auiError("rtmSetMetaData fail"))
            return
        }
        currentMap = map
        aui_map_log("rtmMergeMetaData valueCmd: \(valueCmd ?? "") value: \(value)")
        self.rtmManager.setBatchMetadata(channelName: channelName,
                                         lockName: kRTM_Referee_LockName,
                                         metadata: [observeKey: value]) { error in
            aui_map_log("rtmMergeMetaData completion: \(error?.localizedDescription ?? "success")")
            callback?(error)
        }
    }
    
    func rtmCleanMetaData(callback: ((NSError?)->())?) {
        aui_map_log("rtmCleanMetaData")
        self.rtmManager.cleanBatchMetadata(channelName: channelName,
                                           lockName: kRTM_Referee_LockName,
                                           removeKeys: [observeKey]) { error in
            aui_map_log("rtmCleanMetaData completion: \(error?.localizedDescription ?? "success")")
            callback?(error)
        }
    }
}

//MARK: AUIRtmAttributesProxyDelegate
extension AUIMapCollection: AUIRtmAttributesProxyDelegate {
    public func onAttributesDidChanged(channelName: String, key: String, value: Any) {
        guard channelName == self.channelName, key == self.observeKey else {return}
        guard let map = value as? [String: [String: Any]] else {return}
        self.currentMap = map
    }
}

//MARK: AUIRtmMessageProxyDelegate
extension AUIMapCollection: AUIRtmMessageProxyDelegate {
    private func sendReceipt(publisher: String, uniqueId: String, error: NSError?) {
        let data: [String: Any] = ["code": error?.code ?? 0,
                                   "reason": error?.localizedDescription ?? ""]
        let payload = AUICollectionMessagePayload(data: AUIAnyType(map: data))
        let message = AUICollectionMessage(channelName: channelName,
                                           messageType: .receipt,
                                           sceneKey: observeKey,
                                           uniqueId: uniqueId,
                                           payload: payload)
        guard let jsonStr = encodeModelToJsonStr(message) else {
            aui_map_warn("sendReceipt fail")
            return
        }
        rtmManager.publish(userId: publisher, 
                           channelName: channelName,
                           message: jsonStr) { err in
        }
    }
    
    public func onMessageReceive(publisher: String, message: String) {
        guard let map = decodeToJsonObj(message) as? [String: Any],
              let collectionMessage: AUICollectionMessage = decodeModel(map),
              collectionMessage.sceneKey == observeKey else {
            return
        }
        aui_map_log("onMessageReceive: \(map)")
        let uniqueId = collectionMessage.uniqueId ?? ""
        let channelName = collectionMessage.channelName ?? ""
        guard channelName == self.channelName else {return}
        if collectionMessage.messageType == .receipt {
            if let callback = rtmManager.receiptCallbackMap[uniqueId]?.closure {
                rtmManager.markReceiptFinished(uniqueId: uniqueId)
                let data = collectionMessage.payload?.data?.toJsonObject() as? [String : Any]
                let code = data?["code"] as? Int ?? 0
                let reason = data?["reason"] as? String ?? "success"
                callback(code == 0 ? nil : NSError.auiError(reason))
            }
            return
        }
        
        guard let updateType = collectionMessage.payload?.type else {
            sendReceipt(publisher: publisher,
                        uniqueId: uniqueId,
                        error: NSError.auiError("updateType not found"))
            return
        }
        
        let valueCmd = collectionMessage.payload?.dataCmd
        var err: NSError? = nil
        switch updateType {
        case .add, .update, .merge:
            if let value = collectionMessage.payload?.data?.toJsonObject() as? [String : Any] {
                if updateType == .merge {
                    rtmMergeMetaData(publisherId: publisher, 
                                     valueCmd: valueCmd,
                                     value: value) {[weak self] error in
                        self?.sendReceipt(publisher: publisher, 
                                          uniqueId: uniqueId,
                                          error: error)
                    }
                } else {
                    rtmSetMetaData(publisherId: publisher, 
                                   valueCmd: valueCmd,
                                   value: value) {[weak self] error in
                        self?.sendReceipt(publisher: publisher, 
                                          uniqueId: uniqueId,
                                          error: error)
                    }
                }
                return
            }
            err = NSError.auiError("payload is not a map")
        case .clean:
            rtmCleanMetaData(callback: {[weak self] error in
                self?.sendReceipt(publisher: publisher,
                                  uniqueId: uniqueId,
                                  error: error)
            })
        case .remove:
            err = NSError.auiError("map collection remove type unsupported")
            break
        case .increase:
            break
        case .decrease:
            break
        }
        
        guard let err = err else {return}
        sendReceipt(publisher: publisher,
                    uniqueId: uniqueId,
                    error: err)
    }
}
