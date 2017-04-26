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
        
    static var allTests = [
        ("testExample", testExample),
    ]
}
