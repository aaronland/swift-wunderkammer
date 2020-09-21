import Foundation
import UIKit

import FMDB
import URITemplate

import Logging

// MARK: - SQLiteOEmbedRecord

public enum SQLiteOEmbedRecordErrors: Error {
        case missingObjectURI
    case missingScheme
    
}

public struct SQLiteOEmbedRecordOptions {
    public var object_url_template: String
    public var collection: String
}

public class SQLiteOEmbedRecord: CollectionOEmbed {
    
    private var options: SQLiteOEmbedRecordOptions
    private var oembed: OEmbedResponse
    // private var scheme: String
    
    // https://github.com/aaronland/ios-wunderkammer/issues/17
    
    public init (options: SQLiteOEmbedRecordOptions, oembed: OEmbedResponse) throws {
        
        guard let _ = oembed.object_uri else {
            throw SQLiteOEmbedRecordErrors.missingObjectURI
        }

        self.options = options
        self.oembed = oembed
    }
    
    public func Collection() -> String {
        return self.options.collection
    }
    
    public func ObjectID() -> String {
        return self.oembed.object_uri!
    }
    
    public func ObjectURL() -> String {
        return self.oembed.author_url!
    }
    
    public func ObjectURI() -> String {
        
        guard let object_uri = self.oembed.object_uri else {
            
            let t = URITemplate(template: self.options.object_url_template)
            let url = t.expand(["object_id": self.ObjectID()])
            
            return url
            //let id = self.ObjectID()
            //return "\(self.scheme)://x/\(id)"
        }
        
        return object_uri
    }
    
    public func ObjectTitle() -> String {
        return self.oembed.title
    }
    
    public func ImageURL() -> String {
        
        guard let data_url = self.oembed.data_url else {
            return self.oembed.url
        }
        
        return data_url
    }
    
    public func ThumbnailURL() -> String? {
                
        guard let data_url = self.oembed.thumbnail_data_url else {
            return self.oembed.thumbnail_url
        }
        
        return data_url
    }
    
    public func Raw() -> OEmbedResponse {
        return self.oembed
    }
    
}

// MARK: - SQLiteCollection

public enum SQLiteCollectionErrors: Error {
    case missingScheme
    case missingDatabaseRoot
    case missingDatabaseFiles
    case databaseOpen
    case invalidURL
    case invalidNFCURL
    case invalidOEmbed
    case missingUnitID
    case missingUnitDatabase
    case missingOEmbedQueryParameter
}

public struct SQLiteCollectionCapabilities {
    public var nfcTags: Bool
    public var bleTags: Bool
    public var randomObject: Bool
    public var saveObject: Bool
    
    public init(nfcTags: Bool = false, bleTags: Bool = false, randomObject: Bool = false, saveObject: Bool = false){
        
        self.nfcTags = nfcTags
        self.bleTags = bleTags
        self.randomObject = randomObject
        self.saveObject = saveObject
    }
}

public class SQLiteCollection: Collection, Sequence {
        
    private var cache = NSCache<NSString,SQLiteOEmbedRecord>()
    private var databases = [String:FMDatabase]()
    
    // private var options: SQLiteCollectionOptions
    
    public var root: String
    public var name: String
    public var resolver: DatabaseResolver
    public var capabilities: SQLiteCollectionCapabilities
    public var object_url_template: String
    public var object_tag_template: String
    public var logger: Logger?
    
    public init(root: String, name: String, resolver: DatabaseResolver, capabilities: SQLiteCollectionCapabilities, object_url_template: String, object_tag_template: String, logger: Logger? = nil) throws {
        
        self.root = root
        self.name = name
        self.resolver = resolver
        self.capabilities = capabilities
        self.object_url_template = object_url_template
        self.object_tag_template = object_tag_template
        self.logger = logger
        
        let fm = FileManager.default
        
        let paths = fm.urls(for: .documentDirectory, in: .userDomainMask)
        let first = paths[0]
        
        let abs_root = first.appendingPathComponent(self.root)

        logger?.debug("Database root is \(abs_root)")
        
        if !fm.fileExists(atPath: abs_root.path){
            throw SQLiteCollectionErrors.missingDatabaseRoot
        }
        
        var db_uris = [URL]()
        
        do {
            
            let contents = try fm.contentsOfDirectory(at: abs_root, includingPropertiesForKeys: nil)
            
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
        
        var results = [FMResultSet]()
        
        for (scheme, db) in self.databases {
            
            var resultset: FMResultSet
            
            do {
                let rs = try db.executeQuery(q, values: nil)
                resultset = rs
            } catch (let error) {
                self.logger?.warning("Failed to create iterator for database \(scheme) : \(error)")
                continue
            }
            
            results.append(resultset)
        }
        
        return SQLiteCollectionIterator(collection: self, results: results, logger: self.logger)
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
            
            guard let url = URL(string: nfc_url) else {
                return .failure(SQLiteCollectionErrors.invalidNFCURL)
            }
            
            let db_result = self.resolver.DeriveDatabase(url: url)
            
            switch db_result {
            case .failure(let error):
                return .failure(error)
            case .success(let db_uid):
                unit = db_uid
            }
            
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
              
            var collection_oe: SQLiteOEmbedRecord
            
            do {
                
                let opts = SQLiteOEmbedRecordOptions(
                    object_url_template: self.object_url_template,
                    collection: self.name
                )
                
                collection_oe = try SQLiteOEmbedRecord(options: opts, oembed: oe_response)
                
            } catch (let error) {
                return .failure(error)
            }
            
            cache.setObject(collection_oe, forKey: cache_key)
            
            return .success(collection_oe)
        }
    }
    
    public func ObjectTagTemplate() -> Result<URITemplate, Error> {
        // let t = URITemplate(template: "\(self.options.scheme)://o/{objectid}")
        let t = URITemplate(template: self.object_tag_template)
        return .success(t)
    }
    
    public func ObjectURLTemplate() -> Result<URITemplate, Error> {
        // let t = URITemplate(template: "\(self.options.scheme)://o/{objectid}")
        let t = URITemplate(template: self.object_url_template)
        return .success(t)
    }
    
    public func OEmbedURLTemplate() -> Result<URITemplate, Error> {
        let t = URITemplate(template: "nfc:///?url={url}")
        return .success(t)
    }
    
    public func HasCapability(capability: CollectionCapabilities) -> Result<Bool, Error> {
                
        switch capability {
        case CollectionCapabilities.bleTags:
            return .success(self.capabilities.bleTags)
        case CollectionCapabilities.nfcTags:
            return .success(self.capabilities.nfcTags)
        case CollectionCapabilities.randomObject:
            return .success(self.capabilities.randomObject)
        case CollectionCapabilities.saveObject:
            return .success(self.capabilities.saveObject)
        default:
            return .success(false)
        }
    }
    
    public func SaveObject(oembed: CollectionOEmbed, image: UIImage?) -> Result<CollectionSaveObjectResponse, Error> {
        return .success(CollectionSaveObjectResponse.noop)
    }
    
}

// MARK: - SQLiteCollectionIterator

public struct SQLiteCollectionIteratorResponse {
    public var url: URL
    public var has_data_url: Bool
    public var has_thumbnail: Bool
    public var has_thumbnail_data_url: Bool
}

public class SQLiteCollectionIterator: IteratorProtocol {
    
    public typealias Element = SQLiteCollectionIteratorResponse
    
    private let collection: Wunderkammer.Collection
    private let results: [ FMResultSet ]
    
    private var logger: Logger?
    private var current = 0
    
    init(collection: Wunderkammer.Collection, results: [ FMResultSet ], logger: Logger? = nil) {
        self.collection = collection
        self.results = results
    }
    
    public func next() -> SQLiteCollectionIteratorResponse? {
        
        var i = self.current
        
        while i < self.results.count {
            
            let rs = self.results[i]
            
            if let rsp = self.nextWithResultSet(rs: rs) {
                return rsp
            }
            
            i += 1
        }
        
        return nil
    }
    
    private func nextWithResultSet(rs: FMResultSet) -> SQLiteCollectionIteratorResponse? {
        
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

