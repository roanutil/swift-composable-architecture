import ComposableArchitecture
import SwiftUI

private let readMe = """
  This screen demonstrates how one can create reusable components in the Composable Architecture.

  The "download component" is a component that can be added to any view to enhance it with the \
  concept of downloading offline content. It facilitates downloading the data, displaying a \
  progress view while downloading, canceling an active download, and deleting previously \
  downloaded data.

  Tap the download icon to start a download, and tap again to cancel an in-flight download or to \
  remove a finished download. While a file is downloading you can tap a row to go to another \
  screen to see that the state is carried over.
  """

@Reducer
struct CityMap {
  @ObservableState
  struct State: Equatable, Identifiable {
    var download: Download
    var downloadComponent: DownloadComponent.State

    init(download: Download) {
      self.download = download
      self.downloadComponent = DownloadComponent.State(
        id: AnyHashableSendable(download.id),
        url: download.downloadVideoUrl
      )
    }

    var id: UUID { download.id }

    struct Download: Equatable, Identifiable {
      var blurb: String
      var downloadVideoUrl: URL
      let id: UUID
      var title: String
    }
  }

  enum Action {
    case downloadComponent(DownloadComponent.Action)
  }

  var body: some Reducer<State, Action> {
    Scope(state: \.downloadComponent, action: \.downloadComponent) {
      DownloadComponent()
    }

    Reduce { state, action in
      switch action {
      case .downloadComponent(.downloadClient(.success(.response))):
        // NB: This is where you could perform the effect to save the data to a file on disk.
        return .none

      case .downloadComponent(.alert(.presented(.deleteButtonTapped))):
        // NB: This is where you could perform the effect to delete the data from disk.
        return .none

      case .downloadComponent:
        return .none
      }
    }
  }
}

struct CityMapRowView: View {
  let store: StoreOf<CityMap>

  var body: some View {
    NavigationLink(
      destination: CityMapDetailView(store: store)
    ) {
      HStack {
        Image(systemName: "map")
        Text(store.download.title)
        Spacer()
        DownloadComponentView(
          store: store.scope(state: \.downloadComponent, action: \.downloadComponent)
        )
      }
    }
  }
}

struct CityMapDetailView: View {
  let store: StoreOf<CityMap>

  var body: some View {
    Form {
      Text(store.download.blurb)

      HStack {
        switch store.downloadComponent.mode {
        case .notDownloaded:
          Text("Download for offline viewing")
        case .downloaded:
          Text("Downloaded")
        case .downloading(let progress):
          Text("Downloading \(Int(100 * progress))%")
        case .startingToDownload:
          Text("Downloading…")
        }

        Spacer()

        DownloadComponentView(
          store: store.scope(state: \.downloadComponent, action: \.downloadComponent)
        )
      }
    }
    .navigationTitle(store.download.title)
  }
}

@Reducer
struct MapApp {
  @ObservableState
  struct State: Equatable {
    var cityMaps: IdentifiedArrayOf<CityMap.State> = .mocks
  }

  enum Action {
    case cityMaps(IdentifiedActionOf<CityMap>)
  }

  var body: some Reducer<State, Action> {
    EmptyReducer().forEach(\.cityMaps, action: \.cityMaps) {
      CityMap()
    }
  }
}

struct CitiesView: View {
  let store: StoreOf<MapApp>

  var body: some View {
    Form {
      Section {
        AboutView(readMe: readMe)
      }
      ForEach(store.scope(state: \.cityMaps, action: \.cityMaps)) { cityMapStore in
        CityMapRowView(store: cityMapStore)
      }
    }
    .navigationTitle("Offline Downloads")
  }
}

extension IdentifiedArray where ID == CityMap.State.ID, Element == CityMap.State {
  static let mocks: Self = [
    CityMap.State(
      download: CityMap.State.Download(
        blurb: """
          New York City (NYC), known colloquially as New York (NY) and officially as the City of \
          New York, is the most populous city in the United States. With an estimated 2018 \
          population of 8,398,748 distributed over about 302.6 square miles (784 km2), New York \
          is also the most densely populated major city in the United States.
          """,
        downloadVideoUrl: URL(string: "http://ipv4.download.thinkbroadband.com/50MB.zip")!,
        id: UUID(),
        title: "New York, NY"
      )
    ),
    CityMap.State(
      download: CityMap.State.Download(
        blurb: """
          Los Angeles, officially the City of Los Angeles and often known by its initials L.A., \
          is the largest city in the U.S. state of California. With an estimated population of \
          nearly four million people, it is the country's second most populous city (after New \
          York City) and the third most populous city in North America (after Mexico City and \
          New York City). Los Angeles is known for its Mediterranean climate, ethnic diversity, \
          Hollywood entertainment industry, and its sprawling metropolis.
          """,
        downloadVideoUrl: URL(string: "http://ipv4.download.thinkbroadband.com/50MB.zip")!,
        id: UUID(),
        title: "Los Angeles, LA"
      )
    ),
    CityMap.State(
      download: CityMap.State.Download(
        blurb: """
          Paris is the capital and most populous city of France, with a population of 2,148,271 \
          residents (official estimate, 1 January 2020) in an area of 105 square kilometres (41 \
          square miles). Since the 17th century, Paris has been one of Europe's major centres of \
          finance, diplomacy, commerce, fashion, science and arts.
          """,
        downloadVideoUrl: URL(string: "http://ipv4.download.thinkbroadband.com/50MB.zip")!,
        id: UUID(),
        title: "Paris, France"
      )
    ),
    CityMap.State(
      download: CityMap.State.Download(
        blurb: """
          Tokyo, officially Tokyo Metropolis (東京都, Tōkyō-to), is the capital of Japan and the \
          most populous of the country's 47 prefectures. Located at the head of Tokyo Bay, the \
          prefecture forms part of the Kantō region on the central Pacific coast of Japan's main \
          island, Honshu. Tokyo is the political, economic, and cultural center of Japan, and \
          houses the seat of the Emperor and the national government.
          """,
        downloadVideoUrl: URL(string: "http://ipv4.download.thinkbroadband.com/50MB.zip")!,
        id: UUID(),
        title: "Tokyo, Japan"
      )
    ),
    CityMap.State(
      download: CityMap.State.Download(
        blurb: """
          Buenos Aires is the capital and largest city of Argentina. The city is located on the \
          western shore of the estuary of the Río de la Plata, on the South American continent's \
          southeastern coast. "Buenos Aires" can be translated as "fair winds" or "good airs", \
          but the former was the meaning intended by the founders in the 16th century, by the \
          use of the original name "Real de Nuestra Señora Santa María del Buen Ayre", named \
          after the Madonna of Bonaria in Sardinia.
          """,
        downloadVideoUrl: URL(string: "http://ipv4.download.thinkbroadband.com/50MB.zip")!,
        id: UUID(),
        title: "Buenos Aires, Argentina"
      )
    ),
  ]
}

#Preview("List") {
  NavigationStack {
    CitiesView(
      store: Store(initialState: MapApp.State(cityMaps: .mocks)) {
        MapApp()
      }
    )
  }
}

#Preview("Detail") {
  NavigationView {
    CityMapDetailView(
      store: Store(initialState: IdentifiedArrayOf<CityMap.State>.mocks[0]) {}
    )
  }
}
