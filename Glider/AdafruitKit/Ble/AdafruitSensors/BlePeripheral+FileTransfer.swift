//
//  BlePeripheral+FileTransfer.swift
//  Glider
//
//  Created by Antonio García on 13/5/21.
//

import Foundation
import CoreBluetooth

extension BlePeripheral {
    // Config
    private static let kDebugLog = true
 
    // Constants
    static let kFileTransferServiceUUID = CBUUID(string: "FEBB")
    private static let kFileTransferVersionCharacteristicUUID = CBUUID(string: "ADAF0100-4669-6C65-5472-616E73666572")
    private static let kFileTransferDataCharacteristicUUID = CBUUID(string: "ADAF0200-4669-6C65-5472-616E73666572")
    private static let kAdafruitFileTransferVersion = 1

    // Data types
    struct DirectoryEntry {
        enum EntryType {
            case file(size: Int)
            case directory
        }
        
        let name: String
        let type: EntryType
    }
    
 
    private struct FileTransferReadStatus {
        var data = Data()
        var completion: ((Result<Data, Error>) -> Void)?
    }
    
    private struct FileTransferWriteStatus {
        var data: Data
        var completion: ((Result<Void, Error>) -> Void)?
    }

    private struct FileTransferDeleteStatus {
        var completion: ((Result<Bool, Error>) -> Void)?
    }

    private struct FileTransferListDirectoryStatus {
        var entries = [DirectoryEntry]()
        var completion: ((Result<[DirectoryEntry]?, Error>) -> Void)?
    }

    private struct FileTransferMakeDirectoryStatus {
        var completion: ((Result<Bool, Error>) -> Void)?
    }

    // MARK: - Errors
    enum FileTransferError: Error {
        case invalidData
        case unknownCommand
        case invalidInternalState
        case statusFailed
    }
    
    // MARK: - Custom properties
    private struct CustomPropertiesKeys {
        static var adafruitFileTransferDataCharacteristic: CBCharacteristic?
        static var adafruitFileTransferReadStatus: FileTransferReadStatus?
        static var adafruitFileTransferWriteStatus: FileTransferWriteStatus?
        static var adafruitFileTransferDeleteStatus: FileTransferDeleteStatus?
        static var adafruitFileTransferListDirectoryStatus: FileTransferListDirectoryStatus?
        static var adafruitFileTransferMakeDirectoryStatus: FileTransferMakeDirectoryStatus?
    }

    private var adafruitFileTransferDataCharacteristic: CBCharacteristic? {
        get {
            return objc_getAssociatedObject(self, &CustomPropertiesKeys.adafruitFileTransferDataCharacteristic) as? CBCharacteristic
        }
        set {
            objc_setAssociatedObject(self, &CustomPropertiesKeys.adafruitFileTransferDataCharacteristic, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }

    private var adafruitFileTransferReadStatus: FileTransferReadStatus? {
        get {
            return objc_getAssociatedObject(self, &CustomPropertiesKeys.adafruitFileTransferReadStatus) as? FileTransferReadStatus
        }
        set {
            objc_setAssociatedObject(self, &CustomPropertiesKeys.adafruitFileTransferReadStatus, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }
    
    private var adafruitFileTransferWriteStatus: FileTransferWriteStatus? {
        get {
            return objc_getAssociatedObject(self, &CustomPropertiesKeys.adafruitFileTransferWriteStatus) as? FileTransferWriteStatus
        }
        set {
            objc_setAssociatedObject(self, &CustomPropertiesKeys.adafruitFileTransferWriteStatus, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }

    private var adafruitFileTransferDeleteStatus: FileTransferDeleteStatus? {
        get {
            return objc_getAssociatedObject(self, &CustomPropertiesKeys.adafruitFileTransferDeleteStatus) as? FileTransferDeleteStatus
        }
        set {
            objc_setAssociatedObject(self, &CustomPropertiesKeys.adafruitFileTransferDeleteStatus, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }
    
    private var adafruitFileTransferListDirectoryStatus: FileTransferListDirectoryStatus? {
        get {
            return objc_getAssociatedObject(self, &CustomPropertiesKeys.adafruitFileTransferListDirectoryStatus) as? FileTransferListDirectoryStatus
        }
        set {
            objc_setAssociatedObject(self, &CustomPropertiesKeys.adafruitFileTransferListDirectoryStatus, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }
    
    private var adafruitFileTransferMakeDirectoryStatus: FileTransferMakeDirectoryStatus? {
        get {
            return objc_getAssociatedObject(self, &CustomPropertiesKeys.adafruitFileTransferMakeDirectoryStatus) as? FileTransferMakeDirectoryStatus
        }
        set {
            objc_setAssociatedObject(self, &CustomPropertiesKeys.adafruitFileTransferMakeDirectoryStatus, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }


    
    // MARK: - Actions
    func adafruitFileTransferEnable(completion: ((Result<Void, Error>) -> Void)?) {
        
        // Note: don't check version because version characteristic is not available yet
        self.adafruitServiceEnable(serviceUuid: Self.kFileTransferServiceUUID, mainCharacteristicUuid: Self.kFileTransferDataCharacteristicUUID) { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case let .success((_, characteristic)):
                self.adafruitFileTransferDataCharacteristic = characteristic
                
                self.adafruitServiceSetNotifyResponse(characteristic: characteristic, responseHandler: self.receiveFileTransferData, completion: completion)
                
            case let .failure(error):
                self.adafruitFileTransferDataCharacteristic = nil
                completion?(.failure(error))
            }
        }
            
        /* TODO: restore version check when a readable version characteristic is added to the firmware 
        self.adafruitServiceEnableIfVersion(version: Self.kAdafruitFileTransferVersion, serviceUuid: Self.kFileTransferServiceUUID, versionCharacteristicUUID: Self.kFileTransferVersionCharacteristicUUID, mainCharacteristicUuid: Self.kFileTransferDataCharacteristicUUID) { result in
            switch result {
            case let .success(characteristic):
                self.adafruitFileTransferDataCharacteristic = characteristic
                completion?(.success(()))
                
            case let .failure(error):
                self.adafruitFileTransferDataCharacteristic = nil
                completion?(.failure(error))
            }
        }*/
    }
    
    func adafruitFileTransferIsEnabled() -> Bool {
        return adafruitFileTransferDataCharacteristic != nil
    }
    
    func adafruitFileTransferDisable() {
        // Clear all specific data
        adafruitFileTransferDataCharacteristic = nil
    }
    
    static let readDataHeaderLength = 16
    
    // MARK: - Commands
    func readFile(filename: String, completion: ((Result<Data, Error>) -> Void)?) {
        self.adafruitFileTransferReadStatus = FileTransferReadStatus(completion: completion)
        
        let mtu = self.maximumWriteValueLength(for: .withoutResponse)
        
        let offset = 0
        let chunkSize = mtu - Self.readDataHeaderLength //self.maximumWriteValueLength(for: .withoutResponse)
        let data = ([UInt8]([0x10, 0x00])).data
            + UInt16(filename.count).littleEndian.data
            + UInt32(offset).littleEndian.data
            + UInt32(chunkSize).littleEndian.data
            + Data(filename.utf8)
       
        sendCommand(data: data) { result in
            if case .failure(let error) = result {
                completion?(.failure(error))
            }
        }
    }
    
    func readFileChunk(offset: UInt32, chunkSize: UInt32, completion: ((Result<Void, Error>) -> Void)?) {
        let data = ([UInt8]([0x12, 0x01, 0x00, 0x00])).data
            + UInt32(offset).littleEndian.data
            + UInt32(chunkSize).littleEndian.data
       
        sendCommand(data: data, completion: completion)
    }
    
    func writeFile(data: Data, filename: String, completion: ((Result<Void, Error>) -> Void)?) {
        let fileStatus = FileTransferWriteStatus(data: data, completion: completion)
        self.adafruitFileTransferWriteStatus = fileStatus

        let offset = 0
        let totalSize = fileStatus.data.count
        
        let data = ([UInt8]([0x20, 0x00])).data
            + UInt16(filename.count).littleEndian.data
            + UInt32(offset).littleEndian.data
            + UInt32(totalSize).littleEndian.data
            + Data(filename.utf8)
       
        sendCommand(data: data) { result in
            if case .failure(let error) = result {
                completion?(.failure(error))
            }
        }
    }

    // Note: uses info stored in adafruitFileTransferFileStatus to resume writing data
    private func writeFileChunk(offset: UInt32, chunkSize: UInt32, completion: ((Result<Void, Error>) -> Void)?) {
        guard let adafruitFileTransferWriteStatus = adafruitFileTransferWriteStatus else { completion?(.failure(FileTransferError.invalidInternalState)); return; }

        let chunkData = adafruitFileTransferWriteStatus.data.subdata(in: Int(offset)..<(Int(offset)+Int(chunkSize)))
    
        let data = ([UInt8]([0x22, 0x01, 0x00, 0x00])).data
            + UInt32(offset).littleEndian.data
            + UInt32(chunkSize).littleEndian.data
            + chunkData
       
        DLog("\twrite chunk at offset \(offset) chunkSize: \(chunkSize). message size: \(data.count) mtu: \(self.maximumWriteValueLength(for: .withoutResponse))")
        //DLog("\t\t\(String(data: chunkData, encoding: .utf8))")
        sendCommand(data: data, completion: completion)
    }
    
    func deleteFile(filename: String, completion: ((Result<Bool, Error>) -> Void)?) {
        self.adafruitFileTransferDeleteStatus = FileTransferDeleteStatus(completion: completion)
        
        let data = ([UInt8]([0x30, 0x00])).data
            + UInt16(filename.count).littleEndian.data
            + Data(filename.utf8)
       
        sendCommand(data: data) { result in
            if case .failure(let error) = result {
                completion?(.failure(error))
            }
        }
    }
    
    func listDirectory(_ directory: String, completion: ((Result<[DirectoryEntry]?, Error>) -> Void)?) {
        self.adafruitFileTransferListDirectoryStatus = FileTransferListDirectoryStatus(completion: completion)
                
        let data = ([UInt8]([0x50, 0x00])).data
            + UInt16(directory.count).littleEndian.data
            + Data(directory.utf8)
        
        sendCommand(data: data)  { result in
            if case .failure(let error) = result {
                completion?(.failure(error))
            }
        }
    }
    
    func makeDirectory(_ directory: String, completion: ((Result<Bool, Error>) -> Void)?) {
        self.adafruitFileTransferMakeDirectoryStatus = FileTransferMakeDirectoryStatus(completion: completion)
                
        let data = ([UInt8]([0x40, 0x00])).data
            + UInt16(directory.count).littleEndian.data
            + Data(directory.utf8)
        
        sendCommand(data: data)  { result in
            if case .failure(let error) = result {
                completion?(.failure(error))
            }
        }
    }
    
    private func sendCommand(data: Data, completion: ((Result<Void, Error>) -> Void)?) {
        guard let adafruitFileTransferDataCharacteristic = adafruitFileTransferDataCharacteristic else {
            completion?(.failure(PeripheralAdafruitError.invalidCharacteristic))
            return
        }

        self.write(data: data, for: adafruitFileTransferDataCharacteristic, type: .withoutResponse) { error in
            guard error == nil else {
                completion?(.failure(error!))
                return
            }

            completion?(.success(()))
        }
    }
    
    // MARK: - Receive Data
    private func receiveFileTransferData(response: Result<(Data, UUID), Error>) {
        switch response {
        case .success(let (data, _)):
            
            var remainingData: Data? = data
            while remainingData != nil && remainingData!.count > 0 {
                remainingData = decodeResponseChunk(data: remainingData!)
            }
                                
        case .failure(let error):
            DLog("receiveFileTransferData error: \(error)")
        }
    }
    
    // TODO: return remaining data from each command
    // Note: Take into accoutn that data can be a Data-slice
    private func decodeResponseChunk(data: Data) -> Data? {
        guard let command = data.first else { DLog("Error: response invalid data"); return nil }
        
        //DLog("received command: \(command)")
        switch command {
        case 0x11:
            decodeReadFile(data: data)

        case 0x21:
            decodeWriteFile(data: data)

        case 0x31:
            decodeDeleteFile(data: data)

        case 0x41:
            decodeMakeDirectory(data: data)

        case 0x51:
            return decodeListDirectory(data: data)

        default:
            DLog("unknown command: \(command)")
        }

        return nil
    }

    private func decodeWriteFile(data: Data) {
        guard let adafruitFileTransferWriteStatus = adafruitFileTransferWriteStatus else { DLog("Error: invalid internal status"); return }
        let completion = adafruitFileTransferWriteStatus.completion
        
        guard data.count >= 12 else { completion?(.failure(FileTransferError.invalidData)); return }
        
        let status = data[1]
        let isStatusOk = status == 0x01
        
        let offset: UInt32 = data.scanValue(start: 4, length: 4)
        let freeSpace: UInt32 = data.scanValue(start: 8, length: 4)

        DLog("\twrite \(isStatusOk ? "ok":"error") at offset: \(offset) free space: \(freeSpace)")
        guard isStatusOk else {
            completion?(.failure(FileTransferError.statusFailed))
            return
        }
        
        if offset >= adafruitFileTransferWriteStatus.data.count  {
            self.adafruitFileTransferWriteStatus = nil
            completion?(.success(()))
        }
        else {
            writeFileChunk(offset: offset, chunkSize: freeSpace) { result in
                if case .failure(let error) = result {
                    completion?(.failure(error))
                }
            }
        }
    }
    
    private func decodeReadFile(data: Data) {
        guard let adafruitFileTransferReadStatus = adafruitFileTransferReadStatus else { DLog("Error: invalid internal status"); return }
        let completion = adafruitFileTransferReadStatus.completion
        
        guard data.count > 3 else { completion?(.failure(FileTransferError.invalidData)); return }

        let status = data[1]
        let isStatusOk = status == 0x01
        
        let offset: UInt32 = data.scanValue(start: 4, length: 4)
        let totalLenght: UInt32 = data.scanValue(start: 8, length: 4)
        let chunkSize: UInt32 = data.scanValue(start: 12, length: 4)
        
        DLog("\tread \(isStatusOk ? "ok":"error") at offset \(offset) chunkSize: \(chunkSize) totalLength: \(totalLenght)")
        guard isStatusOk else {
            completion?(.failure(FileTransferError.statusFailed))
            return
        }

        let chunkData = data.subdata(in: Self.readDataHeaderLength..<Self.readDataHeaderLength + Int(chunkSize))
        self.adafruitFileTransferReadStatus!.data.append(chunkData)
        
        if offset + chunkSize < totalLenght {
            let mtu = self.maximumWriteValueLength(for: .withoutResponse)
            let maxChunkLength = mtu - Self.readDataHeaderLength
            readFileChunk(offset: offset + chunkSize, chunkSize: UInt32(maxChunkLength)) { result in
                if case .failure(let error) = result {
                    completion?(.failure(error))
                }
            }
        }
        else {
            let fileData = self.adafruitFileTransferReadStatus!.data
            self.adafruitFileTransferReadStatus = nil
            completion?(.success(fileData))
        }
    }
    
    private func decodeDeleteFile(data: Data) {
        guard let adafruitFileTransferDeleteStatus = adafruitFileTransferDeleteStatus else { DLog("Error: invalid internal status"); return }
        let completion = adafruitFileTransferDeleteStatus.completion

        guard data.count >= 1 else { completion?(.failure(FileTransferError.invalidData)); return }

        let status = data[1]
        let isDeleted = status == 0x01
        
        completion?(.success(isDeleted))
    }
    
    private func decodeListDirectory(data: Data) -> Data? {
        guard let adafruitFileTransferListDirectoryStatus = adafruitFileTransferListDirectoryStatus else { DLog("Error: invalid internal status"); return nil }
        let completion = adafruitFileTransferListDirectoryStatus.completion
        var chunkSize = 20      // Chunk size processed (can be less that data.count if several chunks are included in the data)
        
        guard data.count > 1 else { completion?(.failure(FileTransferError.invalidData)); return nil }
        let directoryExists = data[data.startIndex + 1] == 0x1
        if directoryExists, data.count >= 20 {
            let entryCount: UInt32 = data.scanValue(start: 8, length: 4)
            if entryCount == 0  {             // Empty directory
                self.adafruitFileTransferListDirectoryStatus = nil
                completion?(.success([]))
            }
            else {
                let pathLength: UInt16 = data.scanValue(start: 2, length: 2)
                let entryIndex: UInt32 = data.scanValue(start: 4, length: 4)
                
                if entryIndex >= entryCount  {     // Finished. Return entries
                    DLog("list: finished")
                    completion?(.success(self.adafruitFileTransferListDirectoryStatus!.entries))
                    self.adafruitFileTransferListDirectoryStatus = nil
                }
                else {
                    let flags: UInt32 = data.scanValue(start: 12, length: 4)
                    let isDirectory = flags & 0x1 == 1
                    let fileSize: UInt32 = data.scanValue(start: 16, length: 4)        // Ignore for directories
                    
                    if pathLength > 0, let path = String(data: data[(data.startIndex + 20)..<(data.startIndex + 20 + Int(pathLength))], encoding: .utf8) {
                        chunkSize += Int(pathLength)        // chunk includes the variable length path, so add it
                        
                        DLog("list: \(entryIndex+1)/\(entryCount) \(isDirectory ? "Directory":"File") size: \(fileSize) bytes path: /\(path)")
                        let entry = DirectoryEntry(name: path, type: isDirectory ? .directory : .file(size: Int(fileSize)))
                        
                        // Add entry
                        self.adafruitFileTransferListDirectoryStatus?.entries.append(entry)
                    }
                    else {
                        self.adafruitFileTransferListDirectoryStatus = nil
                        completion?(.failure(FileTransferError.invalidData))
                    }
                }
            }
            
        }
        else {
            self.adafruitFileTransferListDirectoryStatus = nil
            completion?(.success(nil))      // nil means directory does not exist
        }
        
        return data[(data.startIndex + chunkSize)..<(data.startIndex + data.count)]
    }
    
    private func decodeMakeDirectory(data: Data) {
        guard let adafruitFileTransferMakeDirectoryStatus = adafruitFileTransferMakeDirectoryStatus else { DLog("Error: invalid internal status"); return }
        let completion = adafruitFileTransferMakeDirectoryStatus.completion

        guard data.count >= 1 else { completion?(.failure(FileTransferError.invalidData)); return }

        let status = data[1]
        let isCreated = status == 0x01
        
        completion?(.success(isCreated))
    }
}
