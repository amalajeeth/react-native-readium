import UIKit
import R2Shared
import R2Navigator

class EPUBViewController: ReaderViewController {

    init(
      publication: Publication,
      locator: Locator?,
      bookId: String,
      mediaType: MediaType,
      highLights: [Highlight],
      resourcesServer: ResourcesServer
    ) {
      let navigator = EPUBNavigatorViewController(
        publication: publication,
        initialLocation: locator,
        resourcesServer: resourcesServer,
        config: EPUBNavigatorViewController.Configuration(
            editingActions: EditingAction.defaultActions
                .appending(EditingAction(
                    title: "Highlight",
                    action: #selector(highlightSelection)
                ))
        )
      )

      super.init(
        navigator: navigator,
        publication: publication,
        bookId: bookId,
        mediaType: mediaType,
        highlights: HighlightRepository(hightLights: highLights)
      )

      navigator.delegate = self
    }

    var epubNavigator: EPUBNavigatorViewController {
      return navigator as! EPUBNavigatorViewController
    }

    override func viewDidLoad() {
      super.viewDidLoad()

      /// Set initial UI appearance.
      if let appearance = publication.userProperties.getProperty(reference: ReadiumCSSReference.appearance.rawValue) {
        setUIColor(for: appearance)
      }
    }

    internal func setUIColor(for appearance: UserProperty) {
      let colors = AssociatedColors.getColors(for: appearance)

      navigator.view.backgroundColor = colors.mainColor
      view.backgroundColor = colors.mainColor
      //
      navigationController?.navigationBar.barTintColor = colors.mainColor
      navigationController?.navigationBar.tintColor = colors.textColor

      navigationController?.navigationBar.titleTextAttributes = [NSAttributedString.Key.foregroundColor: colors.textColor]
    }

    override var currentBookmark: Bookmark? {
      guard let locator = navigator.currentLocation else {
        return nil
      }

      return Bookmark(bookId: bookId, locator: locator)
    }

    @objc func highlightSelection() {
        if let selection = epubNavigator.currentSelection, let bookId = book?.identifier {
            let randomColor = HighlightColor.allCases.randomElement() ?? .yellow
            let highlight = Highlight(bookId: bookId, locator: selection.locator, color: randomColor)
            saveHighlight(highlight)
            epubNavigator.clearSelection()
        }
    }
}

extension EPUBViewController: EPUBNavigatorDelegate {}

extension EPUBViewController: UIGestureRecognizerDelegate {

  func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
    return true
  }

}

extension EPUBViewController {
  // Prevent the popOver to be presented fullscreen on iPhones.
  func adaptivePresentationStyle(for controller: UIPresentationController, traitCollection: UITraitCollection) -> UIModalPresentationStyle
  {
    return .none
  }
}
