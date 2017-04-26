//
//  LaterTests.swift
//  Later
//
//  Created by Oleg Dreyman on {TODAY}.
//  Copyright © 2017 Later. All rights reserved.
//

import Foundation
import XCTest
@testable import Later

enum TestError : Error {
    case a
}

class LaterTests: XCTestCase {
    func testExample() {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct results.
        //// XCTAssertEqual(Later().text, "Hello, World!")
    }
    
    func testOne() {
        let expectation = self.expectation(description: "On fullfill")
        let later = Promisor<Int>()
        let expect = later.proxy
        expect.map({ String($0) }).then { (string) in
            XCTAssertEqual(string, "10")
            expectation.fulfill()
        }
        DispatchQueue.global().async {
            later.fullfill(10)
        }
        waitForExpectations(timeout: 5.0)
    }
    
    func testFulfillTwice() {
        let promisor = Promisor<Int>()
        promisor.proxy.then { (number) in
            print(number)
            if number == 20 {
                XCTFail()
            }
        }
        promisor.fullfill(10)
        promisor.fullfill(20)
    }
    
    func testAlreadyFulfilled() {
        let promisor = Promisor<Int>()
        promisor.fullfill(10)
        promisor.fullfill(25)
        let expectation = self.expectation(description: "On then")
        promisor.proxy.then { (number) in
            XCTAssertEqual(number, 10)
            expectation.fulfill()
        }
        waitForExpectations(timeout: 5.0)
    }
    
    func testFlatMap() {
        func makeLater(from number: Int) -> Later<String> {
            let later = Promisor<String>()
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.12) {
                later.fullfill(String(number))
            }
            return later.proxy
        }
        
        let expectation = self.expectation(description: "On fullfill")
        let later = Promisor<Int>()
        let expect = later.proxy
        expect.flatMap(makeLater(from:)).then { (string) in
            XCTAssertEqual(string, "10")
            expectation.fulfill()
        }
        DispatchQueue.global().async {
            later.fullfill(10)
        }
        waitForExpectations(timeout: 5.0)
    }
    
    func testReject() {
        let expectation = self.expectation(description: "On error")
        let promisor = Promisor<Int>()
        promisor.proxy.catch { (error) in
            if error is TestError {
                expectation.fulfill()
            }
        }.then { (number) in
            XCTFail()
        }
        DispatchQueue.global().async {
            promisor.reject(with: TestError.a)
            promisor.fullfill(15)
        }
        waitForExpectations(timeout: 5.0)
    }
    
    func testPerforming() {
        let expectation = self.expectation(description: "On completion")
        let promise = Promisor<Int>.performing { (fulfill, reject) in
            DispatchQueue.global().async {
                fulfill(10)
            }
        }
        promise.proxy.map(String.init).then { (string) in
            XCTAssertEqual(string, "10")
            expectation.fulfill()
        }
        waitForExpectations(timeout: 5.0)
    }
    
    func testAsync() {
        let expectation = self.expectation(description: "Some")
        let promise = Promisor<Int>()
        promise.proxy.then { (number) in
            print(number)
            expectation.fulfill()
        }
        for i in stride(from: 1, to: 10, by: 1) {
            let queue = DispatchQueue(label: "aaa")
            queue.async {
                promise.fullfill(i)
            }
        }
        waitForExpectations(timeout: 5.0)
    }
    
    func testCombine() {
        let promiseOne = Promisor<Int>()
        let promiseTwo = Promisor<Int>()
        let combined = promiseOne.proxy.combined(with: promiseTwo.proxy)
        let expectation = self.expectation(description: "On combined")
        combined.map(Set.init).then { (set) in
            XCTAssertEqual(set, [10, 5])
            expectation.fulfill()
        }
        DispatchQueue.global().async {
            promiseOne.fullfill(10)
        }
        DispatchQueue.global().async {
            promiseTwo.fullfill(5)
        }
        waitForExpectations(timeout: 5.0)
    }
    
    func testCombineInstant() {
        let promiseOne = Promisor<Int>()
        let promiseTwo = Promisor<Int>()
        let combined = Later.combine([promiseOne.proxy, promiseTwo.proxy])
        let expectation = self.expectation(description: "On error")
        combined.then { (ar) in
            print(ar)
            expectation.fulfill()
        }.catch { (error) in
            XCTFail()
        }
        promiseOne.fullfill(10)
        promiseTwo.fullfill(15)
        waitForExpectations(timeout: 5.0)
    }
    
    func testCombineReject() {
        let promiseOne = Promisor<Int>()
        let promiseTwo = Promisor<Int>()
        let combined = Later.combine([promiseOne.proxy, promiseTwo.proxy])
        let expectation = self.expectation(description: "On error")
        combined.then { (ar) in
            print(ar)
            XCTFail()
        }.catch { (error) in
            expectation.fulfill()
        }
        promiseOne.fullfill(10)
        promiseTwo.reject(with: TestError.a)
        waitForExpectations(timeout: 5.0)
    }
    
    func testZip() {
        for i in (0 ... 10) {
            let promiseOne = Promisor<Int>()
            let promiseTwo = Promisor<String>()
            let zipped = zip(promiseOne.proxy, promiseTwo.proxy)
            let expectation = self.expectation(description: "On zipped")
            zipped.then { (number, string) in
                XCTAssertEqual(number, 10)
                XCTAssertEqual(string, "Sofar")
                expectation.fulfill()
            }
            func fullFirst() {
                DispatchQueue.global().async {
                    promiseOne.fullfill(10)
                }
            }
            func fullSecond() {
                DispatchQueue.global().async {
                    promiseTwo.fullfill("Sofar")
                }
            }
            if i % 2 == 0 {
                fullFirst()
                fullSecond()
            } else {
                fullSecond()
                fullFirst()
            }
            waitForExpectations(timeout: 5.0)
        }
    }
    
    func testZipRejectBoth() {
        let promiseOne = Promisor<Int>()
        let promiseTwo = Promisor<Bool>()
        let expectation = self.expectation(description: "On error")
        zip(promiseOne.proxy, promiseTwo.proxy).catch { (error) in
            expectation.fulfill()
        }.then { (result) in
            XCTFail()
        }
        DispatchQueue.global().async {
            promiseOne.reject(with: TestError.a)
        }
        DispatchQueue.global().async {
            promiseTwo.reject(with: TestError.a)
        }
        waitForExpectations(timeout: 5.0)
    }
    
    func testAlwaysSuccess() {
        let promisor = Promisor<Int>()
        let expectation = self.expectation(description: "On always")
        promisor.proxy.always {
            expectation.fulfill()
        }
        DispatchQueue.global().async {
            promisor.fullfill(10)
        }
        waitForExpectations(timeout: 5.0)
    }
    
    func testAlwaysReject() {
        let promisor = Promisor<Int>()
        let expectation = self.expectation(description: "On always")
        promisor.proxy.always {
            expectation.fulfill()
        }
        DispatchQueue.global().async {
            promisor.reject(with: TestError.a)
        }
        waitForExpectations(timeout: 5.0)
    }
    
    func testEnsureGood() {
        let promisor = Promisor<Int>()
        let expectation = self.expectation(description: "On ensure")
        promisor.proxy.ensure({ $0 > 0 }).then { (number) in
            expectation.fulfill()
        }.catch { (error) in
            XCTFail()
        }
        DispatchQueue.global().async {
            promisor.fullfill(10)
        }
        waitForExpectations(timeout: 5.0)
    }
    
    func testEnsureBad() {
        let promisor = Promisor<Int>()
        let expectation = self.expectation(description: "On ensure")
        promisor.proxy.ensure({ $0 > 0 }).then { (number) in
            XCTFail()
        }.catch { (error) in
            expectation.fulfill()
        }
        DispatchQueue.global().async {
            promisor.fullfill(-15)
        }
        waitForExpectations(timeout: 5.0)
    }
    
    func testRecover() {
        
        func makeGoodPromisor(after error: Error) -> Later<Int> {
            return Promisor.performing(work: { (fulfill, reject) in
                DispatchQueue.global().async {
                    fulfill(10)
                }
            }).proxy
        }
        
        let expectation = self.expectation(description: "On second")
        let promisor = Promisor<Int>()
        promisor
            .proxy
            .then({ _ in XCTFail() })
            .recover(makeGoodPromisor(after:))
            .then { (number) in
                expectation.fulfill()
        }
        DispatchQueue.global().async {
            promisor.reject(with: TestError.a)
        }
        waitForExpectations(timeout: 5.0)
    }
    
    func testTimeout() {
        let promisor = Promisor<Int>()
        let expectation = self.expectation(description: "On timeout")
        promisor.proxy
            .addingTimeout(0.3)
            .catch { (error) in
                switch error {
                case LaterError.timeout:
                    expectation.fulfill()
                default:
                    XCTFail()
                }
            }.then { _ in
                XCTFail()
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
            promisor.fullfill(10)
        }
        waitForExpectations(timeout: 5.0)
    }
        
    static var allTests = [
        ("testExample", testExample),
    ]
}
