import Fluent
import SQLKit

func caseInsensitiveLikeOperator(for db: Database) -> DatabaseQuery.Filter.Method {
    guard let sql = db as? any SQLDatabase else {
        return .custom("ILIKE")
    }

    let dialectName = String(describing: type(of: sql.dialect)).lowercased()
    if dialectName.contains("sqlite") {
        return .custom("LIKE")
    }
    return .custom("ILIKE")
}
