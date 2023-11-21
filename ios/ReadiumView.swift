import Combine
import Foundation
import R2Shared
import R2Streamer
import UIKit
import R2Navigator
import ReadiumInternal

class ReadiumView : UIView, Loggable {
    
    var readerService: ReaderService = ReaderService()
    var readerViewController: ReaderViewController?
    var viewController: UIViewController? {
        let viewController = sequence(first: self, next: { $0.next }).first(where: { $0 is UIViewController })
        return viewController as? UIViewController
    }
    private var subscriptions = Set<AnyCancellable>()
    private var searchViewModel: SearchViewModel?
    private var userSearch: PassthroughSubject<String,Never> = .init()
    
    @objc var file: NSDictionary? = nil {
        didSet {
            let initialLocation = file?["initialLocation"] as? NSDictionary
            let highlights = file?["highlights"] as? NSArray
            if let url = file?["url"] as? String {
                self.loadBook(url: url, location: initialLocation, highlights: highlights)
            }
        }
    }

    @objc var location: NSDictionary? = nil {
        didSet {
            self.updateLocation()
        }
    }
    @objc var settings: NSDictionary? = nil {
        didSet {
            self.updateUserSettings(settings)
        }
    }
    @objc var onLocationChange: RCTDirectEventBlock?
    @objc var onTableOfContents: RCTDirectEventBlock?
    @objc var onNewHighlightCreation: RCTDirectEventBlock?
    @objc var onNewHighlightDeletion: RCTDirectEventBlock?
  
    func loadBook(
        url: String,
        location: NSDictionary?,
        highlights: NSArray?
    ) {
        guard let rootViewController = UIApplication.shared.delegate?.window??.rootViewController else { return }
        
        self.readerService.buildViewController(
            url: url,
            bookId: url,
            location: location,
            highLights: highlights,
            sender: rootViewController,
            completion: { vc in
                self.addViewControllerAsSubview(vc)
                self.location = location
            }
        )
    }
    
    func getLocator() -> Locator? {
        return ReaderService.locatorFromLocation(location, readerViewController?.publication)
    }
    
    func updateLocation() {
        guard let navigator = readerViewController?.navigator else {
            return;
        }
        guard let locator = self.getLocator() else {
            return;
        }
        
        let cur = navigator.currentLocation
        if (cur != nil && locator.hashValue == cur?.hashValue) {
            return;
        }
        
        navigator.go(
            to: locator,
            animated: true
        )
    
    }
    
    private func updateHighlights() {
    
        
        
    }
    
    func updateUserSettings(_ settings: NSDictionary?) {
        
        if (readerViewController == nil) {
            // defer setting update as view isn't initialized yet
            return;
        }
        
        if let navigator = readerViewController!.navigator as? EPUBNavigatorViewController {
            let userProperties = navigator.userSettings.userProperties
            
            for property in userProperties.properties {
                let value = settings?[property.reference]
                
                if (value == nil) {
                    continue
                }
                
                if let e = property as? Enumerable {
                    e.index = value as! Int
                    
                    // synchronize background color
                    if property.reference == ReadiumCSSReference.appearance.rawValue {
                        if let vc = readerViewController as? EPUBViewController {
                            vc.setUIColor(for: property)
                        }
                    }
                } else if let i = property as? Incrementable {
                    i.value = value as! Float
                } else if let s = property as? Switchable {
                    s.on = value as! Bool
                }
            }
            
            navigator.updateUserSettingStyle()
        }
    }
    
    override func removeFromSuperview() {
        readerViewController?.willMove(toParent: nil)
        readerViewController?.view.removeFromSuperview()
        readerViewController?.removeFromParent()
        
        // cancel all current subscriptions
        for subscription in subscriptions {
            subscription.cancel()
        }
        subscriptions = Set<AnyCancellable>()
        
        readerViewController = nil
        super.removeFromSuperview()
    }
    
    private func addViewControllerAsSubview(_ vc: ReaderViewController) {
        vc.publisher.sink(
            receiveValue: { locator in
                self.onLocationChange?(locator.json)
            }
        )
        .store(in: &self.subscriptions)
        
        vc.highlightPublisher.sink { highlight in
            switch action {
            case .add(highlight: let highlight):
                self.onNewHighlightCreation?(["highlight": highlight.json])
            case .delete(highlight: let hightlightId):
                self.onNewHighlightDeletion?(["highlightId": hightlightId])
            }

        }.store(in: &self.subscriptions)
        
        self.onTableOfContents?([
            "toc": vc.publication.tableOfContents.map({ link in
                return link.json
            })
        ])
        
        userSearch
            .debounce(for: .milliseconds(500), scheduler: DispatchQueue.main)
            .removeDuplicates()
            .sink { keyword in
                self.searchViewModel?.search(with: keyword)
            }.store(in: &subscriptions)
        
        
        self.searchViewModel = SearchViewModel(publication: vc.publication)
            
        searchViewModel?.$results.sink(receiveValue: { _ in
            print(self.searchViewModel?.results)
        }).store(in: &subscriptions)
        
        readerViewController = vc
        
        // if the controller was just instantiated then apply any existing settings
        if (settings != nil) {
            self.updateUserSettings(settings)
        }
        
        readerViewController!.view.frame = self.superview!.frame
        self.viewController!.addChild(readerViewController!)
        let rootView = self.readerViewController!.view!
        self.addSubview(rootView)
        self.viewController!.addChild(readerViewController!)
        self.readerViewController!.didMove(toParent: self.viewController!)
        
        // bind the reader's view to be constrained to its parent
        rootView.translatesAutoresizingMaskIntoConstraints = false
        rootView.topAnchor.constraint(equalTo: self.topAnchor).isActive = true
        rootView.bottomAnchor.constraint(equalTo: self.bottomAnchor).isActive = true
        rootView.leftAnchor.constraint(equalTo: self.leftAnchor).isActive = true
        rootView.rightAnchor.constraint(equalTo: self.rightAnchor).isActive = true
        
        self.onTableOfContents?([
            "toc": vc.publication.tableOfContents.map({ link in
                return link.json
            })
        ])

    }
}


final class SearchViewModel {
    
    enum State {
        // Empty state / waiting for a search query
        case empty
        // Starting a new search, after calling `cancellable = publication.search(...)`
        case starting(R2Shared.Cancellable)
        // Waiting state after receiving a SearchIterator and waiting for a next() call
        case idle(SearchIterator)
        // Loading the next page of result
        case loadingNext(SearchIterator, R2Shared.Cancellable)
        // We reached the end of the search results
        case end
        // An error occurred, we need to show it to the user
        case failure(LocalizedError)
    }
    
    @Published private(set) var state: State = .empty
    @Published private(set) var results: [Locator] = []
    
    private var publication: Publication
    
    init(publication: Publication) {
        self.publication = publication
    }
    
    /// Starts a new search with the given query.
    func search(with query: String) {
        cancelSearch()
        
        let cancellable = publication._search(query: query) { result in
            switch result {
            case .success(let iterator):
                self.state = .idle(iterator)
                self.loadNextPage()
                
            case .failure(let error):
                self.state = .failure(error)
            }
        }
        
        state = .starting(cancellable)
    }
    
    /// Loads the next page of search results.
    /// Typically, this would be called when the user scrolls towards the end of the results table view.
    func loadNextPage() {
        guard case .idle(let iterator) = state else {
            return
        }

        let cancellable = iterator.next { result in
            switch result {
            case .success(let collection):
                if let collection = collection {
                    self.results.append(contentsOf: collection.locators)
                    self.state = .idle(iterator)
                } else {
                    self.state = .end
                }
                
            case .failure(let error):
                self.state = .failure(error)
            }
        }
        
        state = .loadingNext(iterator, cancellable)
    }
    
    /// Cancels any on-going search and clears the results.
    func cancelSearch() {
        switch state {
        case .idle(let iterator):
            iterator.close()
            
        case .loadingNext(let iterator, let cancellable):
            iterator.close()
            cancellable.cancel()
            
        default:
            break
        }
        
        results.removeAll()
        state = .empty
    }
}


enum HighlightColor: Int, Codable, CaseIterable {
    case red = 1
    case green = 2
    case blue = 3
    case yellow = 4
}

extension HighlightColor {
    var uiColor: UIColor {
        switch self {
        case .red:
            return .red
        case .green:
            return .green
        case .blue:
            return .blue
        case .yellow:
            return .yellow
        }
    }
}

struct Highlight: Codable {
    typealias Id = String

    let id: Id
    /// Foreign key to the publication.
    var bookId: Book.Id
    /// Location in the publication.
    var locator: Locator
    /// Color of the highlight.
    var color: HighlightColor
    /// Date of creation.
    var created: Date = .init()
    /// Total progression in the publication.
    var progression: Double?

    init(id: Id = UUID().uuidString, bookId: Book.Id, locator: Locator, color: HighlightColor, created: Date = Date()) {
        self.id = id
        self.bookId = bookId
        self.locator = locator
        progression = locator.locations.totalProgression
        self.color = color
        self.created = created
    }
    
    public init(json: Any) throws {
        guard let jsonObject = json as? [String: Any] else {
            throw JSONError.parsing(Self.self)
        }
        self.id = jsonObject["id"] as? String ?? ""
        self.bookId = jsonObject["bookId"] as? String ?? ""
        let locator = try Locator(json: jsonObject["locator"]) ?? Locator(href: "", type: "")
        self.locator = locator
        self.progression = locator.locations.totalProgression
        self.color = HighlightColor(rawValue:  jsonObject["color"] as? Int ?? 0) ?? .yellow
        self.created = .init() //  jsonObject["createdAt"] as? String
    }
    
    
    public var json: [String: Any] {
        makeJSON([
            "id": id,
            "bookId": bookId,
            "locator": locator.json,
            "color": color.rawValue,
            
        ])
    }
}

//extension Highlight: TableRecord, FetchableRecord, PersistableRecord {
//    enum Columns: String, ColumnExpression {
//        case id, bookId, locator, color, created, progression
//    }
//}
protocol EntityId: Codable, Hashable, RawRepresentable, ExpressibleByIntegerLiteral, CustomStringConvertible where RawValue == Int64 {}
extension EntityId {
    // MARK: - ExpressibleByIntegerLiteral

    init(integerLiteral value: Int64) {
        self.init(rawValue: value)!
    }

    // MARK: - Codable

    init(from decoder: Decoder) throws {
        try self.init(rawValue: decoder.singleValueContainer().decode(Int64.self))!
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    // MARK: - CustomStringConvertible

    var description: String {
        "\(Self.self)(\(rawValue))"
    }

    // MARK: - DatabaseValueConvertible

//    var databaseValue: DatabaseValue { rawValue.databaseValue }
//
//    static func fromDatabaseValue(_ dbValue: DatabaseValue) -> Self? {
//        Int64.fromDatabaseValue(dbValue).map(Self.init)
//    }
}

struct Book: Codable {
//    struct Id: EntityId { let rawValue: Int64 }
    typealias Id = String

    let id: Id?
    /// Canonical identifier for the publication, extracted from its metadata.
    var identifier: String?
    /// Title of the publication, extracted from its metadata.
    var title: String
    /// Authors of the publication, separated by commas.
    var authors: String?
    /// Media type associated to the publication.
    var type: String
    /// Location of the packaged publication or a manifest.
    var path: String
    /// Location of the cover.
    var coverPath: String?
    /// Last read location in the publication.
    var locator: Locator? {
        didSet { progression = locator?.locations.totalProgression ?? 0 }
    }

    /// Current progression in the publication, extracted from the locator.
    var progression: Double
    /// Date of creation.
    var created: Date
    /// JSON of user preferences specific to this publication (e.g. language,
    /// reading progression, spreads).
    var preferencesJSON: String?

    var mediaType: MediaType { MediaType.of(mediaType: type) ?? .binary }

    init(
        id: Id? = nil,
        identifier: String? = nil,
        title: String,
        authors: String? = nil,
        type: String,
        path: String,
        coverPath: String? = nil,
        locator: Locator? = nil,
        created: Date = Date(),
        preferencesJSON: String? = nil
    ) {
        self.id = id
        self.identifier = identifier
        self.title = title
        self.authors = authors
        self.type = type
        self.path = path
        self.coverPath = coverPath
        self.locator = locator
        progression = locator?.locations.totalProgression ?? 0
        self.created = created
        self.preferencesJSON = preferencesJSON
    }

    var cover: URL? {
        coverPath.map { Paths.covers.appendingPathComponent($0) }
    }

    func preferences<P: Decodable>() throws -> P? {
        guard let data = preferencesJSON.flatMap({ $0.data(using: .utf8) }) else {
            return nil
        }
        return try JSONDecoder().decode(P.self, from: data)
    }

    mutating func setPreferences<P: Encodable>(_ preferences: P) throws {
        let data = try JSONEncoder().encode(preferences)
        preferencesJSON = String(data: data, encoding: .utf8)
    }
}

//extension Book: TableRecord, FetchableRecord, PersistableRecord {
//    enum Columns: String, ColumnExpression {
//        case id, identifier, title, type, path, coverPath, locator, progression, created, preferencesJSON
//    }
//}
