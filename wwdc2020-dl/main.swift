//
//  main.swift
//  wwdc2020-dl
//
//  Created by synix on 2020/12/21.
//

import Foundation
import ArgumentParser

struct WWDCDownloadCommander: ParsableCommand {
    @Argument(help: "Session id of wwdc 2020.")
    var sessionId: String

    @Flag(name: .shortAndLong, help: "Download session's video.")
    var video: Bool = false
    
    @Flag(name: .shortAndLong, help: "Download session's subtitle(.srt).")
    var subtitle: Bool = false
    
    @Option(name: .shortAndLong, help: "Video quality you want, 'sd' or 'hd'?")
    var quality: String = "hd"
    
    @Option(name: .shortAndLong, help: "Language of subtitle you want, 'en', 'cn' or 'ja'?")
    var language: String = "en"
    
    func run() throws {
        print("""
        Receive: sessionId = \(sessionId), video = \(video), \
        subtitle = \(subtitle), quality = \(quality), language = \(language)
        """)

        let dl = WWDCDownloader(sessionId: sessionId)

        if video {
            dl.downloadVideo(quality: quality) {
                if subtitle {
                    dl.downloadSrt(language: language, quality: quality)
                }
            }
        }
    }
}

WWDCDownloadCommander.main()
RunLoop.main.run()
