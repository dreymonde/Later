//
//  Later.swift
//  Later
//
//  Created by Oleg Dreyman on {TODAY}.
//  Copyright © 2017 Later. All rights reserved.
//

import Foundation

enum State<Value> {
    case pending
    case fulfilled(Value)
    case rejected(Error)
    
    var value: Value? {
        if case .fulfilled(let value) = self {
            return value
        }
        return nil
    }
    
    var error: Error? {
        if case .rejected(let error) = self {
            return error
        }
        return nil
    }
    
    var isPending: Bool {
        if case .pending = self {
            return true
        }
        return false
    }
}

enum LaterResult<Value> {
    case success(Value)
    case failure(Error)
    
    func map<OtherValue>(_ transform: @escaping (Value) throws -> OtherValue) -> LaterResult<OtherValue> {
        switch self {
        case .success(let value):
            do {
                let newValue = try transform(value)
                return .success(newValue)
            } catch {
                return .failure(error)
            }
        case .failure(let error):
            return .failure(error)
        }
    }
}

final class Promisor<Value> {
    
    init() { }
    
    static func performing(work: @escaping (_ fulfill: @escaping (Value) -> (), _ reject: @escaping (Error) -> () ) -> ()) -> Promisor<Value> {
        let promisor = Promisor<Value>()
        work(promisor.fullfill, promisor.reject(with:))
        return promisor
    }
    
    var onCancel: () -> () = {  }
    
    private var callbacks: [LaterCompletion<Value>] = []
    private var state: State<Value> = .pending
    
    private let lockQueue = DispatchQueue(label: "later_lockQueue")

    
    var value: Value? {
        return lockQueue.sync { state.value }
    }
    
    var error: Error? {
        return lockQueue.sync { state.error }
    }
    
    var isFulfilled: Bool {
        return value != nil
    }
    
    var isFailed: Bool {
        return error != nil
    }
    
    var isPending: Bool {
        return !isFulfilled && !isFailed
    }
    
    func fullfill(_ value: Value) {
        updateState(.fulfilled(value))
    }
    
    func reject(with error: Error) {
        updateState(.rejected(error))
    }
    
    private func updateState(_ newState: State<Value>) {
//        guard isPending else {
//            print("Already fullfilled")
//            return
//        }
//        stateAccessQueue.sync {
//            state = newState
//        }
//        fireCompletionHandlers()
        lockQueue.async {
            guard self.state.isPending else {
                print("Already fulfilled")
                return
            }
            self.state = newState
            self.fireCompletionHandlers()
        }
    }
    
    func addCompletion(_ completion: @escaping (LaterResult<Value>) -> ()) {
        lockQueue.async {
            self.callbacks.append(completion)
            self.fireCompletionHandlers()
        }
    }
    
    private func fireCompletionHandlers() {
        let actualState = state
        if actualState.isPending {
            return
        }
        for callback in callbacks {
            switch actualState {
            case .fulfilled(let value):
                callback(.success(value))
            case .rejected(let error):
                callback(.failure(error))
            default:
                break
            }
        }
        self.callbacks.removeAll()
    }
    
    var proxy: Later<Value> {
        return Later(submitCompletion: self.addCompletion,
                     cancel: onCancel)
    }
    
}

typealias LaterCompletion<Value> = (LaterResult<Value>) -> ()

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

struct Later<Value> {
    
    private let _submit: (@escaping LaterCompletion<Value>) -> ()
    private let _cancel: () -> ()
    
    init(submitCompletion: @escaping (@escaping LaterCompletion<Value>) -> (),
         cancel: @escaping () -> ()) {
        self._submit = submitCompletion
        self._cancel = cancel
    }
    
    func rawModify<OtherValue>(submitCompletion: @escaping (@escaping LaterCompletion<OtherValue>) -> ()) -> Later<OtherValue> {
        return Later<OtherValue>(submitCompletion: submitCompletion, cancel: self._cancel)
    }
    
    fileprivate func submit(completion: @escaping LaterCompletion<Value>) {
        _submit(completion)
    }
    
    func dispatch(to queue: DispatchQueue) -> Later<Value> {
        return rawModify { completion in
            self.submit(completion: { result in queue.async(execute: { completion(result) }) })
        }
    }
    
    func cancel() {
        _cancel()
    }
    
    @discardableResult
    func then(_ completion: @escaping (Value) -> ()) -> Later<Value> {
        let completion = fold(onSuccess: completion, onError: { _ in })
        submit(completion: completion)
        return self
    }
    
    @discardableResult
    func `catch`(_ completion: @escaping (Error) -> ()) -> Later<Value> {
        submit(completion: fold(onSuccess: { _ in }, onError: completion))
        return self
    }
    
    func map<OtherValue>(_ transform: @escaping (Value) throws -> OtherValue) -> Later<OtherValue> {
        return rawModify { completion in
            let newCompletion: LaterCompletion<Value> = { result in
                let newResult = result.map(transform)
                completion(newResult)
            }
            self.submit(completion: newCompletion)
        }
    }
    
    func flatMap<OtherValue>(_ transform: @escaping (Value) -> Later<OtherValue>) -> Later<OtherValue> {
        return rawModify { completion in
            let newCompletion: LaterCompletion<Value> = { result in
                switch result {
                case .success(let value):
                    let newExpect = transform(value)
                    newExpect.submit(completion: completion)
                case .failure(let error):
                    completion(.failure(error))
                }
            }
            self.submit(completion: newCompletion)
        }
    }
    
}
