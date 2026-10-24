import SwiftUI

/// Navigation bars can retain their original title after an environment locale
/// change. Resolve the title whenever the locale changes without resetting the
/// NavigationStack, selected tab or active voice session.
private struct LocalizedNavigationTitle: ViewModifier {
    @Environment(\.locale) private var locale
    let title: String.LocalizationValue

    func body(content: Content) -> some View {
        content.navigationTitle(L10n.text(title, locale: locale))
    }
}

extension View {
    func localizedNavigationTitle(_ title: String.LocalizationValue) -> some View {
        modifier(LocalizedNavigationTitle(title: title))
    }
}
