// Copyright 2023 The Brave Authors. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI
import DesignSystem
import Preferences
import BraveCore

struct NFTView: View {
  var cryptoStore: CryptoStore
  @ObservedObject var keyringStore: KeyringStore
  @ObservedObject var networkStore: NetworkStore
  @ObservedObject var nftStore: NFTStore
  
  @State private var isPresentingFiltersDisplaySettings: Bool = false
  @State private var isPresentingEditUserAssets: Bool = false
  @State private var selectedNFTViewModel: NFTAssetViewModel?
  @State private var isShowingNFTDiscoveryAlert: Bool = false
  @State private var isShowingAddCustomNFT: Bool = false
  @State private var isNFTDiscoveryEnabled: Bool = false
  @State private var nftToBeRemoved: NFTAssetViewModel?
  @State private var groupToggleState: [NFTGroupViewModel.ID: Bool] = [:]
  
  @Environment(\.buySendSwapDestination)
  private var buySendSwapDestination: Binding<BuySendSwapDestination?>
  @Environment(\.openURL) private var openWalletURL
  
  private var emptyView: some View {
    VStack(alignment: .center, spacing: 10) {
      Text(nftStore.displayType.emptyTitle)
        .font(.headline.weight(.semibold))
        .foregroundColor(Color(.braveLabel))
      if let description = nftStore.displayType.emptyDescription {
        Text(description)
          .font(.subheadline.weight(.semibold))
          .foregroundColor(Color(.secondaryLabel))
      }
      Button(Strings.Wallet.nftEmptyImportNFT) {
        isShowingAddCustomNFT = true
      }
      .buttonStyle(BraveFilledButtonStyle(size: .normal))
      .hidden(isHidden: nftStore.displayType != .visible)
      .padding(.top, 8)
    }
    .multilineTextAlignment(.center)
    .frame(maxWidth: .infinity)
    .padding(.vertical, 60)
    .padding(.horizontal, 32)
  }
  
  private var editUserAssetsButton: some View {
    Button(action: { isPresentingEditUserAssets = true }) {
      Text(Strings.Wallet.editVisibleAssetsButtonTitle)
        .multilineTextAlignment(.center)
        .font(.footnote.weight(.semibold))
        .foregroundColor(Color(.braveBlurpleTint))
        .frame(maxWidth: .infinity)
    }
    .sheet(isPresented: $isPresentingEditUserAssets) {
      EditUserAssetsView(
        networkStore: networkStore,
        keyringStore: keyringStore,
        userAssetsStore: nftStore.userAssetsStore
      ) {
        cryptoStore.updateAssets()
      }
    }
  }
  
  private let nftGrids = [GridItem(.adaptive(minimum: 120), spacing: 16, alignment: .top)]
  
  @ViewBuilder private func nftLogo(_ nftViewModel: NFTAssetViewModel) -> some View {
    if let image = nftViewModel.network.nativeTokenLogoImage, nftStore.filters.isShowingNFTNetworkLogo {
      Image(uiImage: image)
        .resizable()
        .frame(width: 20, height: 20)
        .padding(4)
    }
  }
  
  @ViewBuilder private func nftImage(_ nftViewModel: NFTAssetViewModel) -> some View {
    Group {
      if let urlString = nftViewModel.nftMetadata?.imageURLString {
        NFTImageView(urlString: urlString) {
          noImageView(nftViewModel)
        }
      } else {
        noImageView(nftViewModel)
      }
    }
    .overlay(nftLogo(nftViewModel), alignment: .bottomTrailing)
    .cornerRadius(4)
  }
  
  @ViewBuilder private func noImageView(_ nftViewModel: NFTAssetViewModel) -> some View {
    Blockie(address: nftViewModel.token.contractAddress, shape: .rectangle)
      .overlay(
        Text(nftViewModel.token.symbol.first?.uppercased() ?? "")
          .font(.system(size: 80, weight: .bold, design: .rounded))
          .foregroundColor(.white)
          .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
      )
      .aspectRatio(1.0, contentMode: .fit)
  }
  
  private var filtersButton: some View {
    AssetButton(braveSystemName: "leo.filter.settings", action: {
      isPresentingFiltersDisplaySettings = true
    })
  }
  
  private var nftHeaderView: some View {
    HStack {
      Menu {
        Picker("", selection: $nftStore.displayType) {
          ForEach(NFTStore.NFTDisplayType.allCases) { type in
            Text(type.dropdownTitle)
              .foregroundColor(Color(.secondaryBraveLabel))
              .tag(type)
          }
        }
        .pickerStyle(.inline)
      } label: {
        HStack(spacing: 12) {
          Text(nftStore.displayType.dropdownTitle)
            .font(.subheadline.weight(.semibold))
          Text("\(nftStore.totalDisplayedNFTCount)")
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .font(.caption2.weight(.semibold))
            .background(
              Color(braveSystemName: .primary20)
                .cornerRadius(4)
            )
          Image(braveSystemName: "leo.carat.down")
            .font(.subheadline.weight(.semibold))
        }
        .foregroundColor(Color(.braveBlurpleTint))
      }
      if nftStore.isLoadingDiscoverAssets && isNFTDiscoveryEnabled {
        ProgressView()
          .padding(.leading, 5)
      }
      Spacer()
      addCustomAssetButton
        .padding(.trailing, 10)
      filtersButton
    }
    .padding(.horizontal)
    .frame(maxWidth: .infinity, alignment: .leading)
  }
  
  private var addCustomAssetButton: some View {
    AssetButton(braveSystemName: "leo.plus.add") {
      isShowingAddCustomNFT = true
    }
  }
  
  private var nftDiscoveryDescriptionText: NSAttributedString? {
    let attributedString = NSMutableAttributedString(
      string: Strings.Wallet.nftDiscoveryCalloutDescription,
      attributes: [.foregroundColor: UIColor.braveLabel, .font: UIFont.preferredFont(for: .subheadline, weight: .regular)]
    )
    
    attributedString.addAttributes([.underlineStyle: NSUnderlineStyle.single.rawValue], range: (attributedString.string as NSString).range(of: "SimpleHash")) // `SimpleHash` won't get translated
    attributedString.addAttribute(
      .link,
      value: WalletConstants.nftDiscoveryURL.absoluteString,
      range: (attributedString.string as NSString).range(of: Strings.Wallet.nftDiscoveryCalloutDescriptionLearnMore)
    )
    
    return attributedString
  }
  
  /// Builds the grids of NFTs without any grouping or expandable / collapse behaviour.
  @ViewBuilder private func nftGridsPlainView(_ group: NFTGroupViewModel) -> some View {
    LazyVGrid(columns: nftGrids) {
      ForEach(group.assets) { nft in
        Button(action: {
          selectedNFTViewModel = nft
        }) {
          VStack(alignment: .leading, spacing: 4) {
            nftImage(nft)
              .padding(.bottom, 8)
            Text(nft.token.nftTokenTitle)
              .font(.callout.weight(.medium))
              .foregroundColor(Color(.braveLabel))
              .multilineTextAlignment(.leading)
            if !nft.token.symbol.isEmpty {
              Text(nft.token.symbol)
                .font(.caption)
                .foregroundColor(Color(.secondaryBraveLabel))
                .multilineTextAlignment(.leading)
            }
          }
          .overlay(alignment: .topLeading) {
            if nft.token.isSpam {
              HStack(spacing: 4) {
                Text(Strings.Wallet.nftSpam)
                  .padding(.vertical, 4)
                  .padding(.leading, 6)
                  .foregroundColor(Color(.braveErrorLabel))
                Image(braveSystemName: "leo.warning.triangle-outline")
                  .padding(.vertical, 4)
                  .padding(.trailing, 6)
                  .foregroundColor(Color(.braveErrorBorder))
              }
              .font(.system(size: 13).weight(.semibold))
              .background(
                Color(uiColor: WalletV2Design.spamNFTLabelBackground)
                  .cornerRadius(4)
              )
              .padding(12)
            }
          }
        }
        .contextMenu {
          Button(action: {
            if nft.token.visible { // a collected visible NFT, mark as hidden
              nftStore.updateNFTStatus(nft.token, visible: false, isSpam: false, isDeletedByUser: false)
            } else { // either a hidden NFT or a junk NFT, mark as visible
              nftStore.updateNFTStatus(nft.token, visible: true, isSpam: false, isDeletedByUser: false)
            }
          }) {
            if nft.token.visible { // a collected visible NFT
              Label(Strings.recentSearchHide, braveSystemImage: "leo.eye.off")
            } else if nft.token.isSpam { // a spam NFT
              Label(Strings.Wallet.nftUnspam, braveSystemImage: "leo.disable.outline")
            } else { // a hidden but not spam NFT
              Label(Strings.Wallet.nftUnhide, braveSystemImage: "leo.eye.on")
            }
          }
          Button(action: {
            nftToBeRemoved = nft
          }) {
            Label(Strings.Wallet.nftRemoveFromWallet, braveSystemImage: "leo.trash")
          }
        }
      }
    }
  }
  
  /// Builds the expandable /  collapseable section content for a given group.
  @ViewBuilder private func groupedNFTSection(_ group: NFTGroupViewModel) -> some View {
    if group.assets.isEmpty {
      EmptyView()
    } else {
      WalletDisclosureGroup(
        isNFTGroup: true,
        isExpanded: Binding(
          get: { groupToggleState[group.id, default: true] },
          set: { groupToggleState[group.id] = $0 }
        ),
        content: {
          nftGridsPlainView(group)
            .padding(.top)
        },
        label: {
          if case let .account(account) = group.groupType {
            AddressView(address: account.address) {
              PortfolioAssetGroupHeaderView(group: group)
            }
          } else {
            PortfolioAssetGroupHeaderView(group: group)
          }
        }
      )
    }
  }
  
  var body: some View {
    LazyVStack(spacing: 16) {
      nftHeaderView
      if nftStore.isShowingNFTEmptyState {
        emptyView
      } else {
        ForEach(nftStore.displayNFTGroups) { group in
          if group.groupType == .none {
            nftGridsPlainView(group)
              .padding(.horizontal)
          } else {
            groupedNFTSection(group)
          }
        }
      }
    }
    .background(
      NavigationLink(
        isActive: Binding(
          get: { selectedNFTViewModel != nil },
          set: { if !$0 { selectedNFTViewModel = nil } }
        ),
        destination: {
          if let nftViewModel = selectedNFTViewModel {
            NFTDetailView(
              nftDetailStore: cryptoStore.nftDetailStore(for: nftViewModel.token, nftMetadata: nftViewModel.nftMetadata),
              buySendSwapDestination: buySendSwapDestination
            ) { nftMetadata in
              nftStore.updateNFTMetadataCache(for: nftViewModel.token, metadata: nftMetadata)
            }
            .onDisappear {
              cryptoStore.closeNFTDetailStore(for: nftViewModel.token)
            }
          }
        },
        label: {
          EmptyView()
        })
    )
    .background(
      WalletPromptView(
        isPresented: $isShowingNFTDiscoveryAlert,
        primaryButton: .init(
          title: Strings.Wallet.nftDiscoveryCalloutEnable,
          action: { _ in
            isNFTDiscoveryEnabled = true
            nftStore.enableNFTDiscovery()
            Preferences.Wallet.shouldShowNFTDiscoveryPermissionCallout.value = false
            isShowingNFTDiscoveryAlert = false
          }
        ),
        secondaryButton: .init(
          title: Strings.Wallet.nftDiscoveryCalloutDisable,
          action: { _ in
            isNFTDiscoveryEnabled = false
            Preferences.Wallet.shouldShowNFTDiscoveryPermissionCallout.value = false
            // don't need to setDiscovery(false) since the default value is false
            // and when nftDiscoveryEnabled() is true, this WalletPromptView won't
            // get prompt
            isShowingNFTDiscoveryAlert = false
          }
        ),
        showCloseButton: false,
        content: {
          VStack(spacing: 10) {
            Text(Strings.Wallet.nftDiscoveryCalloutTitle)
              .font(.headline.weight(.bold))
              .multilineTextAlignment(.center)
            if let attrString = nftDiscoveryDescriptionText {
              AdjustableHeightAttributedTextView(
                attributedString: attrString,
                openLink: { url in
                  if let url {
                    openWalletURL(url)
                  }
                }
              )
            }
          }
        }
      )
    )
    .background(
      WalletPromptView(
        isPresented: Binding(
          get: { nftToBeRemoved != nil },
          set: { if !$0 { nftToBeRemoved = nil } }
        ),
        primaryButton: .init(
          title: Strings.Wallet.manageSiteConnectionsConfirmAlertRemove,
          action: { _ in
            guard let nft = nftToBeRemoved else { return }
            nftStore.updateNFTStatus(nft.token, visible: false, isSpam: nft.token.isSpam, isDeletedByUser: true)
            nftToBeRemoved = nil
          }
        ),
        secondaryButton: .init(
          title: Strings.CancelString,
          action: { _ in
            nftToBeRemoved = nil
          }
        ),
        showCloseButton: false,
        content: {
          VStack(spacing: 16) {
            Text(Strings.Wallet.nftRemoveFromWalletAlertTitle)
              .font(.headline)
              .foregroundColor(Color(.bravePrimary))
            Text(Strings.Wallet.nftRemoveFromWalletAlertDescription)
              .font(.footnote)
              .foregroundStyle(Color(.secondaryBraveLabel))
          }
        })
    )
    .sheet(isPresented: $isShowingAddCustomNFT) {
      AddCustomAssetView(
        networkStore: networkStore,
        networkSelectionStore: networkStore.openNetworkSelectionStore(mode: .formSelection),
        keyringStore: keyringStore,
        userAssetStore: nftStore.userAssetsStore,
        supportedTokenTypes: [.nft]
      ) {
        cryptoStore.updateAssets()
      }
    }
    .sheet(isPresented: $isPresentingFiltersDisplaySettings) {
      FiltersDisplaySettingsView(
        filters: nftStore.filters,
        isNFTFilters: true,
        networkStore: networkStore,
        save: { filters in
          nftStore.saveFilters(filters)
        }
      )
      .osAvailabilityModifiers({ view in
        if #available(iOS 16, *) {
          view
            .presentationDetents([
              .fraction(0.6),
              .large
            ])
        } else {
          view
        }
      })
    }
    .onAppear {
      Task {
        isNFTDiscoveryEnabled = await nftStore.isNFTDiscoveryEnabled()
        if !isNFTDiscoveryEnabled && Preferences.Wallet.shouldShowNFTDiscoveryPermissionCallout.value {
          self.isShowingNFTDiscoveryAlert = true
        }
      }
    }
  }
}

#if DEBUG
struct NFTView_Previews: PreviewProvider {
  static var previews: some View {
    NFTView(
      cryptoStore: .previewStore,
      keyringStore: .previewStore,
      networkStore: .previewStore,
      nftStore: CryptoStore.previewStore.nftStore
    )
  }
}
#endif
