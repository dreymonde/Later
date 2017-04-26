import Dispatch

extension Later {

    public func dispatch(to queue: DispatchQueue) -> Later<Value> {
        return rawModify { completion in
            self.submit(completion: { result in queue.async(execute: { completion(result) }) })
        }
    }
    
    @discardableResult
    public func always(_ perform: @escaping () -> ()) -> Later<Value> {
        self.submit(completion: fold(onSuccess: { _ in perform() }, onError: { _ in perform() }))
        return self
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
    
    public static func combine(_ promises: [Later<Value>]) -> Later<[Value]> {
        return Later<[Value]>(submitCompletion: { (completion) in
            promises.forEach { promise in
                promise.then({ (value) in
                    if !promises.contains(where: { !$0.isFulfilled }) {
                        let values = promises.flatMap({ $0.value })
                        assert(values.count == promises.count)
                        completion(.success(values))
                    }
                }).catch({ (error) in
                    completion(.failure(error))
                })
            }
        }, cancel: { 
            promises.forEach({ $0.cancel() })
        })
    }
    
    public func combined(with promises: Later<Value>...) -> Later<[Value]> {
        return Later.combine([self] + promises)
    }

}

