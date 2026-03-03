//
//  Storer.swift
//  cashew
//
//  Created by Joseph Bao on 8/11/25.
//

import CID
import Foundation

public protocol Storer {
    func store(rawCid: String, data: Data) throws
}
