//
//  FileDecoder.swift
//  
//
//  Created by Alberto Espinilla Garrido on 3/4/23.
//

import Foundation

struct FileDecoder {
    func decode(_ data: Data) -> [[UInt8]: Int] {
        guard let decoded = String(data: data, encoding: .utf8) else { return [:] }
        var result: [[UInt8]: Int] = .init()
        decoded.split(separator: "\n").forEach({
            let lineSplit = $0.split(separator: " ")
            guard let first = lineSplit.first,
                  let keyData = String(first).base64DecodedData(),
                  let value = lineSplit.last,
                  let intValue = Int(value) else {
                return
            }
            result[[UInt8](keyData)] = intValue
        })
        return result
    }
}
