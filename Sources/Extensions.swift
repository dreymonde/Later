import Dispatch
import Foundation.NSDate

public enum LaterError : Error {
    
    case ensureConditionFailed
    case timeout(TimeInterval)
    
}

extension Later {

    public func dispatch(to queue: DispatchQueue) -> Later<Value> {
        return rawModify { completion in
            self.submit(completion: { result in
                queue.async {
                    completion(result)
                }
            })
        }
    }
    
    @discardableResult
    public func always(_ perform: @escaping () -> ()) -> Later<Value> {
        self.submit(completion: fold(onSuccess: { _ in perform() }, onError: { _ in perform() }))
        return self
    }
    
    public func ensure(_ condition: @escaping (Value) -> Bool) -> Later<Value> {
        return self.map({ (value) in
            if condition(value) {
                return value
            } else {
                throw LaterError.ensureConditionFailed
            }
        })
    }
    
    public func recover(_ recovery: @escaping (Error) throws -> Later<Value>) -> Later<Value> {
        return rawModify { completion in
            let newCompletion: LaterCompletion<Value> = { result in
                switch result {
                case .success:
                    completion(result)
                case .failure(let error):
                    do {
                        let newLater = try recovery(error)
                        newLater.submit(completion: completion)
                    } catch let recoveryError {
                        completion(.failure(recoveryError))
                    }
                }
            }
            self.submit(completion: newCompletion)
        }
    }

}

extension Later {
    
    public static func delay(_ timeInterval: TimeInterval) -> Later<Void> {
        let promise = Promisor<Void>.performing { (fulfill, _) in
            DispatchQueue.main.asyncAfter(deadline: .now() + timeInterval, execute: { 
                fulfill()
            })
        }
        return promise.proxy
    }
    
    public static func timeout(_ timeInterval: TimeInterval) -> Later<Value> {
        let promise = Promisor<Value>.performing { (_, reject) in
            Later.delay(timeInterval).then {
                reject(LaterError.timeout(timeInterval))
            }
        }
        return promise.proxy
    }
    
    public func racing(with laters: Later<Value>...) -> Later<Value> {
        let allPromises = [self] + laters
        let promisor = Promisor<Value>.performing { (fulfill, reject) in
            for promise in allPromises {
                promise.submit(completion: fold(onSuccess: fulfill, onError: reject))
            }
        }
        return promisor.proxy
    }
    
    public func addingTimeout(_ timeInterval: TimeInterval) -> Later<Value> {
        return racing(with: Later.timeout(timeInterval))
    }
    
}

extension Later {
    
    public static func combine(_ promises: [Later<Value>]) -> Later<[Value]> {
        let callbackQueue = DispatchQueue(label: "promises-combine-queue")
        var values: [Value] = []
        var counter = 0
        let promisesCount = promises.count
        let promisor = Promisor<[Value]>.performing { (fulfill, reject) in
            guard !promises.isEmpty else {
                fulfill([])
                return
            }
            promises.forEach { promise in
                promise
                    .dispatch(to: callbackQueue)
                    .then({ (value) in
                        values.append(value)
                        counter += 1
                        if counter == promisesCount {
                            fulfill(values)
                        }
                    }).catch({ (error) in
                        reject(error)
                    })
            }
        }
        promisor.onCancel = {
            promises.forEach({ $0.cancel() })
        }
        return promisor.proxy
    }
    
    public func combined(with promises: Later<Value>...) -> Later<[Value]> {
        return Later.combine([self] + promises)
    }
    
}

public func zip<T, U>(_ first: Later<T>, _ second: Later<U>) -> Later<(T, U)> {
    let callbackQueue = DispatchQueue(label: "promises-zip-queue")
    var firstValue: T?
    var secondValue: U?
    let promisor = Promisor<(T, U)>.performing { (fulfill, reject) in
        first.dispatch(to: callbackQueue)
            .then({ (value) in
                if let secondValue = secondValue {
                    fulfill(value, secondValue)
                } else {
                    firstValue = value
                }
            }).catch({ (error) in
                reject(error)
            })
        second.dispatch(to: callbackQueue)
            .then({ (value) in
                if let firstValue = firstValue {
                    fulfill(firstValue, value)
                } else {
                    secondValue = value
                }
            }).catch({ (error) in
                reject(error)
            })
    }
    promisor.onCancel = {
        first.cancel()
        second.cancel()
    }
    return promisor.proxy
}
