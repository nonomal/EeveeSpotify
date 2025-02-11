import Orion
import UIKit

func exitApplication() {
    UIControl().sendAction(#selector(URLSessionTask.suspend), to: UIApplication.shared, for: nil)
    Timer.scheduledTimer(withTimeInterval: 0.2, repeats: false) { _ in
        exit(EXIT_SUCCESS)
    }
}

struct PremiumPatchingGroup: HookGroup { }

struct EeveeSpotify: Tweak {
    static let version = "5.8.7"
    static let isOldSpotifyVersion = NSClassFromString("Lyrics_NPVCommunicatorImpl.LyricsOnlyViewController") == nil
    
    init() {
        if UserDefaults.darkPopUps {
            DarkPopUps().activate()
        }
        
        if UserDefaults.patchType.isPatching {
            PremiumPatchingGroup().activate()
        }
        
        if UserDefaults.lyricsSource.isReplacing {
            LyricsGroup().activate()
        }
    }
}
