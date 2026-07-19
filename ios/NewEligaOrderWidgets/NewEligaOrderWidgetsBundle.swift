import SwiftUI
import WidgetKit

@main
struct NewEligaOrderWidgetsBundle: WidgetBundle {
    var body: some Widget {
        DiningNowWidget()
        RecentCafeOrdersWidget()
        FavoriteQuickOrderWidget()
        OrderLiveActivityWidget()
    }
}
