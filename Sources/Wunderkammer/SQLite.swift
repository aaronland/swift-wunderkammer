import Foundation
import UIKit

import FMDB
import URITemplate

import Logging

public enum SQLiteCollectionErrors: Error {
    case missingDatabaseRoot
    case missingDatabaseFiles
    case databaseOpen
    case invalidURL
    case invalidOEmbed
    case missingUnitID
    case missingUnitDatabase
    case missingOEmbedQueryParameter
}

public struct SQLiteCollectionOptions {
    public var root: String
    public var scheme: String
    public var resolver: DatabaseResolver
    public var logginer: Logger?
}

public class SQLiteCollection: Collection, Sequence {
    
    // FIX ME
    
    private var cache = NSCache<NSString,CollectionOEmbed>()
    private var databases = [String:FMDatabase]()
    
    private var scheme: String
    
    private var resolver: Wunderkammer.DatabaseResolver
    
    public var logger: Logger?
    
    public init(root: String, resolver: DatabaseResolver, scheme: String? = "sqlite", logger: Logger? = nil) throws {
        
        self.logger = logger
        self.resolver = resolver
        let fm = FileManager.default
        
        let paths = fm.urls(for: .documentDirectory, in: .userDomainMask)
        let first = paths[0]
        
        let root = first.appendingPathComponent(root)

        self.logger?.debug("Database root is \(root)")
        
        if !fm.fileExists(atPath: root.path){
            throw SQLiteCollectionErrors.missingDatabaseRoot
        }
        
        var db_uris = [URL]()
        
        do {
            
            let contents = try fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            
            db_uris = contents.filter{ $0.pathExtension == "db" }
            db_uris = contents
            
        } catch (let error) {
            throw error
        }
        
        if db_uris.count == 0 {
            throw SQLiteCollectionErrors.missingDatabaseFiles
        }
        
        for db_uri in db_uris {
            
            let db = FMDatabase(url: db_uri)
            
            guard db.open() else {
                throw SQLiteCollectionErrors.databaseOpen
            }
            
            let result = getRandomURL(database: db)
            
            switch result {
            case .failure(let error):
                throw error
            case .success(let url):
                
                // Important: We are deriving the "unit" value from a URL
                // for a record returned by a given database and not the
                // URL of the database itself (20200918/thisisaaronland)
                
                let db_result = resolver.DeriveDatabase(url: url)
                
                switch db_result {
                case .failure(let error):
                    throw error
                case .success(let db_uid):
                    self.databases[db_uid] = db
                }
            }
        }
        
    }
    
    public func makeIterator() -> SQLiteCollectionIterator {
        
        // let q = "SELECT url, CASE LENGTH(JSON_EXTRACT(body, '$.thumbnail_url')) WHEN 0 THEN 0 ELSE 1 END AS has_thumbnail, CASE LENGTH(JSON_EXTRACT(body, '$.data_url')) WHEN 0 THEN 0 ELSE 1 END AS has_data_url, CASE LENGTH(JSON_EXTRACT(body, '$.thumbnail_data_url')) WHEN 0 THEN 0 ELSE 1 END AS has_thumbnail_data_url FROM oembed;"
        
        let q = "SELECT url, has_thumbnail, has_data_url, has_thumbnail_data_url FROM oembed"
        var results: FMResultSet?
        
        do {
            
            // FIX ME
            
            let rs = try databases["gallery"]!.executeQuery(q, values: nil)
            results = rs
        } catch (let error) {
            print("SAD", error)
        }
        
        return SQLiteCollectionIterator(collection: self, results: results)
    }
    
    public func GetRandomURL(completion: @escaping (Result<URL, Error>) -> ()) {
        
        let keys = Array(self.databases.keys)
        let idx = keys.randomElement()!
        let database = self.databases[idx]!
        
        let result = self.getRandomURL(database: database)
        completion(result)
    }
    
    private func getRandomURL(database: FMDatabase) -> Result<URL, Error>{
        
        let q = "SELECT url FROM oembed ORDER BY RANDOM() LIMIT 1"
        
        var str_url: String?
        
        do {
            let rs = try database.executeQuery(q, values: nil)
            rs.next()
            
            guard let u = rs.string(forColumn: "url") else {
                return .failure(SQLiteCollectionErrors.invalidURL)
            }
            
            str_url = u
            
        } catch (let error) {
            return .failure(error)
        }
        
        guard let url = URL(string: str_url!) else {
            return .failure(SQLiteCollectionErrors.invalidURL)
        }
        
        return .success(url)
    }
    
    public func GetOEmbed(url: URL) -> Result<CollectionOEmbed, Error> {
        
        let cache_key = url.absoluteString as NSString
        
        if let cached = cache.object(forKey: cache_key) {
            return .success(cached)
        }
        
        var q = "SELECT body FROM oembed WHERE url = ?"
        
        var unit: String?   // the database to read from
        var target: Any     // the value we are going to query against
        
        if url.scheme == "nfc" {
            
            // query for the object
            
            let params = url.queryParameters
            
            guard let nfc_url = params["url"] else {
                return .failure(SQLiteCollectionErrors.missingOEmbedQueryParameter)
            }
            
            q = "SELECT body FROM oembed WHERE object_uri = ?"
            target = nfc_url
            unit = self.scheme
            
        } else {
            
            // query for a particular representation of the object
            
            let db_result = self.resolver.DeriveDatabase(url: url)
            
            switch db_result {
            case .failure(let error):
                return .failure(error)
            case .success(let db_uid):
                unit = db_uid
            }
            
            target = url.absoluteURL
        }
        
        if unit == nil {
            return .failure(SQLiteCollectionErrors.missingUnitID)
        }
        
        guard let database = self.databases[unit!] else {
            return .failure(SQLiteCollectionErrors.missingUnitDatabase)
        }
        
        var oe_data: Data?
        
        do {
            
            let rs = try database.executeQuery(q, values: [target] )
            rs.next()
            
            guard let data = rs.data(forColumn: "body") else {
                return .failure(SQLiteCollectionErrors.invalidOEmbed)
            }
            
            oe_data = data
            
        } catch (let error) {
            return .failure(error)
        }
        
        let oe = OEmbed()
        
        let oe_result = oe.ParseOEmbed(data: oe_data!)
        
        switch oe_result {
        case .failure(let error):
            return .failure(error)
        case .success(let oe_response):
            
            // FIX ME
            
            guard let collection_oe = GalleryOEmbed(oembed: oe_response) else {
                return .failure(SQLiteCollectionErrors.invalidOEmbed)
            }
            
            cache.setObject(collection_oe, forKey: cache_key)
            
            return .success(collection_oe)
        }
    }
    
    public func ObjectTagTemplate() -> Result<URITemplate, Error> {
        let t = URITemplate(template: "\(self.scheme)://o/{objectid}")
        return .success(t)
    }
    
    public func ObjectURLTemplate() -> Result<URITemplate, Error> {
        let t = URITemplate(template: "\(self.scheme)://o/{objectid}")
        return .success(t)
    }
    
    public func OEmbedURLTemplate() -> Result<URITemplate, Error> {
        let t = URITemplate(template: "nfc:///?url={url}")
        return .success(t)
    }
    
    public func HasCapability(capability: CollectionCapabilities) -> Result<Bool, Error> {
        
        // FIX ME
        
        switch capability {
        case CollectionCapabilities.nfcTags:
            return .success(false)
        case CollectionCapabilities.randomObject:
            return .success(true)
        case CollectionCapabilities.saveObject:
            return .success(false)
        default:
            return .success(false)
        }
    }
    
    public func SaveObject(oembed: CollectionOEmbed, image: UIImage?) -> Result<CollectionSaveObjectResponse, Error> {
        return .success(CollectionSaveObjectResponse.noop)
    }
    
}

public struct SQLiteCollectionIteratorResponse {
    public var url: URL
    public var has_data_url: Bool
    public var has_thumbnail: Bool
    public var has_thumbnail_data_url: Bool
}

public class SQLiteCollectionIterator: IteratorProtocol {
    
    public typealias Element = SQLiteCollectionIteratorResponse
    
    private let collection: Collection
    private let results: FMResultSet?
    
    init(collection: Collection, results: FMResultSet?) {
        self.collection = collection
        self.results = results
    }
    
    public func next() -> SQLiteCollectionIteratorResponse? {
        
        guard let rs = self.results else {
            return nil
        }
        
        rs.next()
        
        var str_url: String!
        
        guard let u = rs.string(forColumn: "url") else {
            return nil
        }
        
        str_url = u
        
        guard let url = URL(string: str_url!) else {
            return nil
        }
        
        var has_data_url = false
        var has_thumbnail = false
        var has_thumbnail_data_url = false
        
        guard let data_url = rs.string(forColumn: "has_data_url") else {
            return nil
        }
        
        guard let thumbnail = rs.string(forColumn: "has_thumbnail") else {
            return nil
        }
        
        guard let thumbnail_url = rs.string(forColumn: "has_thumbnail_data_url") else {
            return nil
        }
        
        if data_url == "1" {
            has_data_url = true
        }
        
        if thumbnail == "1" {
            has_thumbnail = true
        }
        
        if thumbnail_url == "1" {
            has_thumbnail_data_url = true
        }
        
        let rsp = SQLiteCollectionIteratorResponse(
            url: url,
            has_data_url: has_data_url,
            has_thumbnail: has_thumbnail,
            has_thumbnail_data_url: has_thumbnail_data_url
        )
        
        return rsp
    }
}

