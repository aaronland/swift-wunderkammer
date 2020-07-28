//
//  OEmbed.swift
//  shoebox
//
//  Created by asc on 6/10/20.
//  Copyright © 2020 Aaronland. All rights reserved.
//

import Foundation

public struct OEmbedResponse: Codable {
    public var version: String
    public var type: String
    public var provider_name: String
    public var title: String
    public var author_url: String? // SFO Museum but not Cooper Hewitt
    public var url: String
    public var height: Int
    public var width: Int
    public var thumbnail_url: String?
    public var object_url: String? // Cooper Hewitt
    public var object_id: String?  // Cooper Hewitt
    public var object_uri: String? // wunderkammer
    public var data_url: String? // wunderkammer
}

public class OEmbed {
    
    public init() {
        
    }
    
    public func Fetch(url: URL) -> Result<OEmbedResponse, Error> {
        
        var oembed_data: Data?
        
        do {
            oembed_data = try Data(contentsOf: url)
        } catch(let error){
            return .failure(error)
        }
        
        return self.ParseOEmbed(data: oembed_data!)
    }
    
    public func ParseOEmbed(data: Data) -> Result<OEmbedResponse, Error> {
        
        let decoder = JSONDecoder()
        var oembed: OEmbedResponse
        
        do {
            oembed = try decoder.decode(OEmbedResponse.self, from: data)
        } catch(let error) {
            return .failure(error)
        }
        
        return .success(oembed)
    }
}

