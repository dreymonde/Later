//
//  Later.swift
//  Later
//
//  Created by Oleg Dreyman on {TODAY}.
//  Copyright © 2017 Later. All rights reserved.
//

public protocol LaterProtocol {
    
    associatedtype Value
    
    var value: Value? { get }
    var error: Error? { get }
    
}

extension LaterProtocol {
    
    public var isFulfilled: Bool {
        return value != nil
    }
    
    public var isRejected: Bool {
        return error != nil
    }
    
    public var isPending: Bool {
        return !isFulfilled && !isRejected
    }
    
}

internal func fold<Resulted>(onSuccess: @escaping (Resulted) -> (), onError: @escaping (Error) -> ()) -> (LaterResult<Resulted>) -> () {
    return { result in
        switch result {
        case .success(let value):
            onSuccess(value)
        case .failure(let error):
            onError(error)
        }
    }
}

public final class Later<Value> : LaterProtocol {
    
    private let _submit: (@escaping LaterCompletion<Value>) -> ()
    private let _cancel: () -> ()
    
    public init(submitCompletion: @escaping (@escaping LaterCompletion<Value>) -> (),
                cancel: @escaping () -> ()) {
        self._submit = submitCompletion
        self._cancel = cancel
        self.requestValues()
    }
    
    public private(set) var value: Value?
    public private(set) var error: Error?
    
    private func requestValues() {
        submit { (result) in
            switch result {
            case .success(let value):
                self.value = value
            case .failure(let error):
                self.error = error
            }
        }
    }
    
    public func rawModify<OtherValue>(submitCompletion: @escaping (@escaping LaterCompletion<OtherValue>) -> ()) -> Later<OtherValue> {
        return Later<OtherValue>(submitCompletion: submitCompletion, cancel: self._cancel)
    }
    
    
    public func submit(completion: @escaping LaterCompletion<Value>) {
        _submit(completion)
    }
        
    public func cancel() {
        _cancel()
    }
    
    @discardableResult
    public func then(_ completion: @escaping (Value) -> ()) -> Later<Value> {
        let completion = fold(onSuccess: completion, onError: { _ in })
        submit(completion: completion)
        return self
    }
    
    @discardableResult
    public func `catch`(_ completion: @escaping (Error) -> ()) -> Later<Value> {
        submit(completion: fold(onSuccess: { _ in }, onError: completion))
        return self
    }
    
    public func map<OtherValue>(_ transform: @escaping (Value) throws -> OtherValue) -> Later<OtherValue> {
        return rawModify { completion in
            let newCompletion: LaterCompletion<Value> = { result in
                let newResult = result.map(transform)
                completion(newResult)
            }
            self.submit(completion: newCompletion)
        }
    }
    
    public func flatMap<OtherValue>(_ transform: @escaping (Value) throws -> Later<OtherValue>) -> Later<OtherValue> {
        return rawModify { completion in
            let newCompletion: LaterCompletion<Value> = { result in
                switch result {
                case .success(let value):
                    do {
                        let newExpect = try transform(value)
                        newExpect.submit(completion: completion)
                    } catch {
                        completion(.failure(error))
                    }
                case .failure(let error):
                    completion(.failure(error))
                }
            }
            self.submit(completion: newCompletion)
        }
    }
    
}
