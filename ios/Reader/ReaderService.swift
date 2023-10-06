import Combine
import Foundation
import R2Shared
import R2Streamer
import UIKit

final class ReaderService: Loggable {
  var app: AppModule?
  var streamer = Streamer()
  var publicationServer: PublicationServer?
  private var subscriptions = Set<AnyCancellable>()

  init() {
    do {
      self.app = try AppModule()
      self.publicationServer = PublicationServer()
    } catch {
      print("TODO: An error occurred instantiating the ReaderService")
      print(error)
    }
  }
  
  static func locatorFromLocation(
    _ location: NSDictionary?,
    _ publication: Publication?
  ) -> Locator? {
    guard location != nil else {
      return nil
    }

    let hasLocations = location?["locations"] != nil
    let hasChildren = location?["children"] != nil
    let hasHashHref = (location!["href"] as! String).contains("#")

    // check that we're not dealing with a Link
    if ((hasChildren || hasHashHref) && !hasLocations) {
      guard let publication = publication else {
        return nil
      }
      guard let link = try? Link(json: location) else {
        return nil
      }

      return publication.locate(link)
    } else {
      return try? Locator(json: location)
    }
    
    return nil
  }

  func buildViewController(
    url: String,
    bookId: String,
    location: NSDictionary?,
    highLights: NSArray?,
    sender: UIViewController?,
    completion: @escaping (ReaderViewController) -> Void
  ) {
    guard let reader = self.app?.reader else { return }
    self.url(path: url)
      .flatMap { self.openPublication(at: $0, allowUserInteraction: true, sender: sender ) }
      .flatMap { (pub, media) in self.checkIsReadable(publication: pub, mediaType: media) }
      .sink(
        receiveCompletion: { error in
          print(">>>>>>>>>>> TODO: handle me", error)
        },
        receiveValue: { pub, media in
          self.preparePresentation(of: pub)
          let locator: Locator? = ReaderService.locatorFromLocation(location, pub)
            let highlights = ReaderService.buildHighlights(fromDictionary: highLights)
          let vc = reader.getViewController(
            for: pub,
            bookId: bookId,
            mediaType: media,
            highLights: highlights,
            locator: locator
          )
            
            vc?.buildBook(from: self)

          if (vc != nil) {
            completion(vc!)
          }
        }
      )
      .store(in: &subscriptions)
  }
    
    static func buildHighlights(fromDictionary json: NSArray?) -> [Highlight] {
        guard let jsonArray = json else {
            return []
        }
        return jsonArray.compactMap { try? Highlight(json: $0 as Any)}
    }

  func url(path: String) -> AnyPublisher<URL, ReaderError> {
    // Absolute URL.
    if let url = URL(string: path), url.scheme != nil {
      return .just(url)
    }

    // Absolute file path.
    if path.hasPrefix("/") {
      return .just(URL(fileURLWithPath: path))
    }

    return .fail(ReaderError.fileNotFound(fatalError("Unable to locate file: " + path)))
  }

  private func openPublication(
    at url: URL,
    allowUserInteraction: Bool,
    sender: UIViewController?
  ) -> AnyPublisher<(Publication, MediaType), ReaderError> {
    let openFuture = Future<(Publication, MediaType), ReaderError>(
      on: .global(),
      { promise in
        let asset = FileAsset(url: url)
        guard let mediaType = asset.mediaType() else {
          promise(.failure(.openFailed(Publication.OpeningError.unsupportedFormat)))
          return
        }

        self.streamer.open(
          asset: asset,
          allowUserInteraction: allowUserInteraction,
          sender: sender
        ) { result in
          switch result {
          case .success(let publication):
            promise(.success((publication, mediaType)))
          case .failure(let error):
            promise(.failure(.openFailed(error)))
          case .cancelled:
            promise(.failure(.cancelled))
          }
        }
      }
    )

    return openFuture.eraseToAnyPublisher()
  }

    private func checkIsReadable(publication: Publication, mediaType: MediaType) -> AnyPublisher<(Publication,MediaType), ReaderError> {
    guard !publication.isRestricted else {
      if let error = publication.protectionError {
        return .fail(.openFailed(error))
      } else {
        return .fail(.cancelled)
      }
    }
    return .just((publication,mediaType))
  }

  private func preparePresentation(of publication: Publication) {
    if (self.publicationServer == nil) {
      log(.error, "Whoops")
      return
    }

    publicationServer?.removeAll()
    do {
      try publicationServer?.add(publication)
    } catch {
      log(.error, error)
    }
  }
    
    /// Imports the publication cover and return its path relative to the Covers/ folder.
    private func importCover(of publication: Publication)  -> String? {
        guard let cover = publication.cover?.pngData() else {
            return nil
        }
        let coverURL = Paths.covers.appendingUniquePathComponent()

        do {
            try cover.write(to: coverURL)
            return coverURL.lastPathComponent
        } catch {
            return nil
        }
    }
    
    /// Inserts the given `book` in the bookshelf.
    private func buildBook(at url: URL, publication: Publication, mediaType: MediaType, coverPath: String?) -> Book {
        let book = Book(
            identifier: publication.metadata.identifier,
            title: publication.metadata.title,
            authors: publication.metadata.authors
                .map(\.name)
                .joined(separator: ", "),
            type: mediaType.string,
            path: (url.isFileURL || url.scheme == nil) ? url.lastPathComponent : url.absoluteString,
            coverPath: coverPath
        )

        return book
    }
    
    /// Inserts the given `book` in the bookshelf.
    public func getBook(at url: String, publication: Publication, mediaType: MediaType) throws -> Book {
        guard let url = URL(string: url) else {
            throw  LibraryError.bookNotFound
        }
        let coverPath = importCover(of: publication)
        return buildBook(at: url, publication: publication, mediaType: mediaType, coverPath: coverPath)
    }
}

enum LibraryError: LocalizedError {
    case publicationIsNotValid
    case bookNotFound
    case bookDeletionFailed(Error?)
    case importFailed(Error)
    case openFailed(Error)
    case downloadFailed(Error)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .publicationIsNotValid:
            return NSLocalizedString("library_error_publicationIsNotValid", comment: "Error message used when trying to import a publication that is not valid")
        case .bookNotFound:
            return NSLocalizedString("library_error_bookNotFound", comment: "Error message used when trying to open a book whose file is not found")
        case let .importFailed(error):
            return String(format: NSLocalizedString("library_error_importFailed", comment: "Error message used when a low-level error occured while importing a publication"), error.localizedDescription)
        case let .openFailed(error):
            return String(format: NSLocalizedString("library_error_openFailed", comment: "Error message used when a low-level error occured while opening a publication"), error.localizedDescription)
        case let .downloadFailed(error):
            return String(format: NSLocalizedString("library_error_downloadFailed", comment: "Error message when the download of a publication failed"), error.localizedDescription)
        default:
            return nil
        }
    }
}
