import Orion
import SwiftUI

//

struct LyricsGroup: HookGroup { }

//

class LyricsFullscreenViewControllerHook: ClassHook<UIViewController> {
    typealias Group = LyricsGroup
    
    static var targetName: String {
        return EeveeSpotify.isOldSpotifyVersion
            ? "Lyrics_CoreImpl.FullscreenViewController"
            : "Lyrics_FullscreenPageImpl.FullscreenViewController"
    }

    func viewDidLoad() {
        orig.viewDidLoad()
        
        if UserDefaults.lyricsSource == .musixmatch 
            && lastLyricsState.fallbackError == nil
            && !lastLyricsState.wasRomanized
            && !lastLyricsState.areEmpty {
            return
        }
        
        let headerView = Ivars<UIView>(target.view).headerView
        
        if let reportButton = headerView.subviews(matching: "EncoreButton")[1] as? UIButton {
            reportButton.isEnabled = false
        }
    }
}

//

private var preloadedLyrics: Lyrics? = nil
private var lastLyricsState = LyricsLoadingState()

private var hasShownRestrictedPopUp = false
private var hasShownUnauthorizedPopUp = false

//

class LyricsOnlyViewControllerHook: ClassHook<UIViewController> {
    typealias Group = LyricsGroup
    
    static var targetName: String {
        return EeveeSpotify.isOldSpotifyVersion
            ? "Lyrics_CoreImpl.LyricsOnlyViewController"
            : "Lyrics_NPVCommunicatorImpl.LyricsOnlyViewController"
    }

    func viewDidLoad() {
        orig.viewDidLoad()
        
        guard
            let lyricsHeaderViewController = target.parent?.children.first
        else {
            return
        }
        
        //
        
        let lyricsLabel = EeveeSpotify.isOldSpotifyVersion 
            ? lyricsHeaderViewController.view.subviews.first?.subviews.first
            : lyricsHeaderViewController.view.subviews.first

        guard let lyricsLabel = lyricsLabel else {
            return
        }
        
        //

        let encoreLabel = Dynamic.convert(lyricsLabel, to: SPTEncoreLabel.self)
        
        var text = [
            encoreLabel.text().firstObject
        ]
        
        let attributes = Dynamic.SPTEncoreAttributes
            .alloc(interface: SPTEncoreAttributes.self)
            .`init`({ attributes in
                attributes.setForegroundColor(.white.withAlphaComponent(0.5))
            })
        
        let typeStyle = type(
            of: Dynamic[
                dynamicMember: EeveeSpotify.isOldSpotifyVersion
                    ? "SPTEncoreTypeStyle"
                    : "SPTEncoreTextStyle"
            ].alloc(interface: SPTEncoreTypeStyle.self)
        ).bodyMediumBold()
        
        //
        
        if UserDefaults.fallbackReasons, let description = lastLyricsState.fallbackError?.description {
            var attributedString = Dynamic.SPTEncoreAttributedString.alloc(
                interface: SPTEncoreAttributedString.self
            )
            
            text.append(
                EeveeSpotify.isOldSpotifyVersion
                    ? attributedString.initWithString(
                        "\n\("fallback_attribute".localized): \(description)",
                        typeStyle: typeStyle,
                        attributes: attributes
                    )
                    : attributedString.initWithString(
                        "\n\("fallback_attribute".localized): \(description)",
                        textStyle: typeStyle,
                        attributes: attributes
                    )
            )
        }
        
        if lastLyricsState.wasRomanized {
            var attributedString = Dynamic.SPTEncoreAttributedString.alloc(
                interface: SPTEncoreAttributedString.self
            )
            
            text.append(
                EeveeSpotify.isOldSpotifyVersion
                    ? attributedString.initWithString(
                        "\n\("romanized_attribute".localized)",
                        typeStyle: typeStyle,
                        attributes: attributes
                    )
                    : attributedString.initWithString(
                        "\n\("romanized_attribute".localized)",
                        textStyle: typeStyle,
                        attributes: attributes
                    )
            )
        }
        
        if EeveeSpotify.isOldSpotifyVersion {
            encoreLabel.setNumberOfLines(text.count)
        }

        encoreLabel.setText(text as NSArray)
    }
}

//

private func loadLyricsForCurrentTrack() throws {
    guard let track = HookedInstances.currentTrack else {
        throw LyricsError.noCurrentTrack
    }
    
    //
    
    let searchQuery = LyricsSearchQuery(
        title: track.trackTitle(),
        primaryArtist: track.artistTitle(),
        spotifyTrackId: track.URI().spt_trackIdentifier()
    )
    
    let options = UserDefaults.lyricsOptions
    var source = UserDefaults.lyricsSource
    
    var repository: LyricsRepository = switch source {
        case .genius: GeniusLyricsRepository()
        case .lrclib: LrcLibLyricsRepository()
        case .musixmatch: MusixmatchLyricsRepository.shared
        case .petit: PetitLyricsRepository()
        case .notReplaced: throw LyricsError.invalidSource
    }
    
    let lyricsDto: LyricsDto
    
    //
    
    lastLyricsState = LyricsLoadingState()
    
    do {
        lyricsDto = try repository.getLyrics(searchQuery, options: options)
    }
    catch let error {
        if let error = error as? LyricsError {
            lastLyricsState.fallbackError = error
            
            switch error {
                
            case .invalidMusixmatchToken:
                if !hasShownUnauthorizedPopUp {
                    PopUpHelper.showPopUp(
                        delayed: false,
                        message: "musixmatch_unauthorized_popup".localized,
                        buttonText: "OK".uiKitLocalized
                    )
                    
                    hasShownUnauthorizedPopUp.toggle()
                }
            
            case .musixmatchRestricted:
                if !hasShownRestrictedPopUp {
                    PopUpHelper.showPopUp(
                        delayed: false,
                        message: "musixmatch_restricted_popup".localized,
                        buttonText: "OK".uiKitLocalized
                    )
                    
                    hasShownRestrictedPopUp.toggle()
                }
                
            default:
                break
            }
        }
        else {
            lastLyricsState.fallbackError = .unknownError
        }
        
        if source == .genius || !UserDefaults.geniusFallback {
            throw error
        }
        
        NSLog("[EeveeSpotify] Unable to load lyrics from \(source): \(error), trying Genius as fallback")
        
        source = .genius
        repository = GeniusLyricsRepository()
        
        lyricsDto = try repository.getLyrics(searchQuery, options: options)
    }
    
    lastLyricsState.areEmpty = lyricsDto.lines.isEmpty
    
    lastLyricsState.wasRomanized = lyricsDto.romanization == .romanized
        || (lyricsDto.romanization == .canBeRomanized && UserDefaults.lyricsOptions.romanization)
    
    lastLyricsState.loadedSuccessfully = true

    let lyrics = Lyrics.with {
        $0.data = lyricsDto.toLyricsData(source: source.description)
    }
    
    preloadedLyrics = lyrics
}

func getLyricsForCurrentTrack(originalLyrics: Lyrics? = nil) throws -> Data {
    guard let track = HookedInstances.currentTrack else {
        throw LyricsError.noCurrentTrack
    }
    
    var lyrics = preloadedLyrics
    
    if lyrics == nil {
        try loadLyricsForCurrentTrack()
        lyrics = preloadedLyrics
    }
    
    guard var lyrics = lyrics else {
        throw LyricsError.unknownError
    }
    
    let lyricsColorsSettings = UserDefaults.lyricsColors
    
    if lyricsColorsSettings.displayOriginalColors, let originalLyrics = originalLyrics {
        lyrics.colors = originalLyrics.colors
    }
    else {
        var color: Color?
        
        if let extractedColorHex = track.extractedColorHex() {
            color = Color(hex: extractedColorHex)
        }
        else if let uiColor = HookedInstances.nowPlayingMetaBackgroundModel?.color() {
            color = Color(uiColor)
        }
        
        color = color?.normalized(lyricsColorsSettings.normalizationFactor)
        
        lyrics.colors = LyricsColors.with {
            $0.backgroundColor = lyricsColorsSettings.useStaticColor
                ? Color(hex: lyricsColorsSettings.staticColor).uInt32
            : color?.uInt32 ?? Color.gray.uInt32
            $0.lineColor = Color.black.uInt32
            $0.activeLineColor = Color.white.uInt32
        }
    }
    
    preloadedLyrics = nil
    return try lyrics.serializedBytes()
}
