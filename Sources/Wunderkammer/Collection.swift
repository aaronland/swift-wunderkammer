//
//  Collection.swift
//  wunderkammer
//
//  Created by asc on 6/24/20.
//  Copyright © 2020 Aaronland. All rights reserved.
//

import Foundation
import URITemplate
import Cocoa

#if !os(macOS)
import UIKit
#endif

public enum CollectionSaveObjectResponse {
    case success
    case noop
}

public enum CollectionCapabilities {
    case nfcTags
    case bleTags
    case randomObject
    case saveObject
}

public enum CollectionErrors: Error {
    case notImplemented
    case unknownCapability
}

public protocol CollectionOEmbed {
    func ObjectID() -> String
    func ObjectURL() -> String
    func ObjectTitle() -> String
    func ObjectURI() -> String
    func Collection() -> String
    func ImageURL() -> String
    func Raw() -> OEmbedResponse
}

public protocol Collection {
    func GetRandomURL(completion: @escaping (Result<URL, Error>) -> ())
    
    // does this need to be async with a completion handler? probably...
    func SaveObject(oembed: CollectionOEmbed, image: UIImage?) -> Result<CollectionSaveObjectResponse, Error>
    
    // TBD: return multiple OEmbed things to account for objects with multiple
    // representations...
    
    func GetOEmbed(url: URL) -> Result<CollectionOEmbed, Error>
    func HasCapability(capability: CollectionCapabilities) -> Result<Bool, Error>
    func ObjectTagTemplate() -> Result<URITemplate, Error>
    func ObjectURLTemplate() -> Result<URITemplate, Error>
    func OEmbedURLTemplate() -> Result<URITemplate, Error>
}

// https://www.swiftbysundell.com/tips/making-uiimage-macos-compatible/
// Step 1: Typealias UIImage to NSImage

public  typealias UIImage = NSImage

// Step 2: You might want to add these APIs that UIImage has but NSImage doesn't.
extension NSImage {
    var cgImage: CGImage? {
        var proposedRect = CGRect(origin: .zero, size: size)

        return cgImage(forProposedRect: &proposedRect,
                       context: nil,
                       hints: nil)
    }

    convenience init?(named name: String) {
        self.init(named: Name(name))
    }
}
