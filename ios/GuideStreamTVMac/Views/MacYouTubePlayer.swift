//
//  MacYouTubePlayer.swift
//  GuideStreamTVMac
//
//  YouTube's official IFrame player in a WKWebView — the same player the
//  iPhone app embeds through youtube-ios-player-helper. Views count for the
//  creator, YouTube's own controls and ads stay on it, and videos whose
//  owners disabled embedding report an error so the caller can skip them.
//

import SwiftUI
import WebKit

struct MacYouTubePlayer: NSViewRepresentable {
    let videoId: String
    var muted: Bool = false
    var onEnded: () -> Void = {}
    /// Embedding disabled (101/150), removed video (100) or bad id (2).
    var onUnplayable: () -> Void = {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.mediaTypesRequiringUserActionForPlayback = []
        config.userContentController.add(context.coordinator, name: "gs")
        let web = WKWebView(frame: .zero, configuration: config)
        web.setValue(false, forKey: "drawsBackground")
        context.coordinator.loadedId = videoId
        web.loadHTMLString(Self.html(videoId: videoId, muted: muted), baseURL: URL(string: "https://guidestream.tv"))
        return web
    }

    func updateNSView(_ web: WKWebView, context: Context) {
        context.coordinator.parent = self
        guard context.coordinator.loadedId != videoId else { return }
        context.coordinator.loadedId = videoId
        web.evaluateJavaScript("player && player.loadVideoById('\(videoId)')")
    }

    static func dismantleNSView(_ web: WKWebView, coordinator: Coordinator) {
        web.configuration.userContentController.removeScriptMessageHandler(forName: "gs")
        web.loadHTMLString("", baseURL: nil)
    }

    final class Coordinator: NSObject, WKScriptMessageHandler {
        var parent: MacYouTubePlayer
        var loadedId: String?
        init(_ parent: MacYouTubePlayer) { self.parent = parent }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? String else { return }
            if body == "ended" { parent.onEnded() }
            if body.hasPrefix("error") { parent.onUnplayable() }
        }
    }

    private static func html(videoId: String, muted: Bool) -> String {
        """
        <!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1">
        <style>html,body{margin:0;height:100%;background:#000;overflow:hidden}#p{position:absolute;inset:0;width:100%;height:100%}</style>
        </head><body><div id="p"></div>
        <script src="https://www.youtube.com/iframe_api"></script>
        <script>
        var player;
        function post(m){try{window.webkit.messageHandlers.gs.postMessage(m)}catch(e){}}
        function onYouTubeIframeAPIReady(){
          player=new YT.Player('p',{videoId:'\(videoId)',
            playerVars:{autoplay:1,mute:\(muted ? 1 : 0),playsinline:1,rel:0,modestbranding:1,origin:'https://guidestream.tv'},
            events:{
              onStateChange:function(e){if(e.data===0)post('ended')},
              onError:function(e){post('error:'+e.data)}
            }});
        }
        </script></body></html>
        """
    }
}
