import Dispatch

public enum State<Value> {
    case pending
    case fulfilled(Value)
    case rejected(Error)
    
    public var value: Value? {
        if case .fulfilled(let value) = self {
            return value
        }
        return nil
    }
    
    public var error: Error? {
        if case .rejected(let error) = self {
            return error
        }
        return nil
    }
    
    public var isPending: Bool {
        if case .pending = self {
            return true
        }
        return false
    }
}

public enum LaterResult<Value> {
    case success(Value)
    case failure(Error)
    
    public func map<OtherValue>(_ transform: @escaping (Value) throws -> OtherValue) -> LaterResult<OtherValue> {
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

public final class Promisor<Value> : LaterProtocol {
    
    public init() { }
    
    public static func performing(work: @escaping (_ fulfill: @escaping (Value) -> (), _ reject: @escaping (Error) -> () ) -> ()) -> Promisor<Value> {
        let promisor = Promisor<Value>()
        work(promisor.fullfill, promisor.reject(with:))
        return promisor
    }
    
    public var onCancel: () -> () = {  }
    
    private var callbacks: [LaterCompletion<Value>] = []
    private var state: State<Value> = .pending
    
    private let lockQueue = DispatchQueue(label: "later_lockQueue")
    
    public var value: Value? {
        return lockQueue.sync { state.value }
    }
    
    public var error: Error? {
        return lockQueue.sync { state.error }
    }
    
    public func fullfill(_ value: Value) {
        updateState(.fulfilled(value))
    }
    
    public func reject(with error: Error) {
        updateState(.rejected(error))
    }
    
    private func updateState(_ newState: State<Value>) {
        lockQueue.sync {
            guard self.state.isPending else {
                print("Already fulfilled")
                return
            }
            self.state = newState
            self.fireCompletionHandlersIfFinished()
        }
    }
    
    public func addCompletion(_ completion: @escaping (LaterResult<Value>) -> ()) {
        lockQueue.sync {
            self.callbacks.append(completion)
            self.fireCompletionHandlersIfFinished()
        }
    }
    
    private func fireCompletionHandlersIfFinished() {
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
    
    public var proxy: Later<Value> {
        return Later(submitCompletion: self.addCompletion,
                     cancel: onCancel)
    }
    
}

public typealias LaterCompletion<Value> = (LaterResult<Value>) -> ()
