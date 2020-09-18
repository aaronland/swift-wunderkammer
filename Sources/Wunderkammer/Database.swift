import Foundation

public protocol DatabaseResolver {
    func DeriveDatabase(url: URL) -> Result<String, Error>
}

public class StringDatabaseResolver: DatabaseResolver {

    private var db_uid: String
    
    public init(database: String) throws {
        self.db_uid = database
    }

    public func DeriveDatabase(url: URL) -> Result<String, Error> {
        return .success(self.db_uid)
    }
}

public enum URIDatabaseResolverErrors: Error {
    case invalidMode
    case missingFragment
    case missingID
}

public class URIDatabaseResolver: DatabaseResolver {
    
    private var mode: String
    
    public init(mode: String = "fragment") throws {
        
        switch mode {
        case "fragment":
            self.mode = mode
        case "id":
            self.mode = mode
        default:
            throw URIDatabaseResolverErrors.invalidMode
        }
    }
    
    public func DeriveDatabase(url: URL) -> Result<String, Error> {
        
        switch self.mode {
        case "fragment":
            return self.deriveDatabaseFromFragment(url: url)
        case "id":
            return self.deriveDatabaseFromID(url: url)
        default:
            return .failure(URIDatabaseResolverErrors.invalidMode)
        }
        
    }
    
    private func deriveDatabaseFromFragment(url: URL) -> Result<String, Error> {
        
        guard let fragment = url.fragment else {
            return .failure(URIDatabaseResolverErrors.missingFragment)
        }
        
        return .success(fragment)
    }
    
    private func deriveDatabaseFromID(url: URL) -> Result<String, Error> {
            
            guard let id = url.queryParameters["id"] else {
                return .failure(URIDatabaseResolverErrors.missingID)
            }
            
            let parts = id.components(separatedBy: "-")
            let unit = parts[0]
            
            return .success(unit)
        }
}
