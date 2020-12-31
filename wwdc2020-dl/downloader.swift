//
//  downloader.swift
//  wwdc2020-dl
//
//  Created by synix on 2020/12/26.
//

import Foundation
import Combine
import Alamofire
import Progress

struct WWDCDownloader {
    enum WWDC {
        public static let YEAR = 2020
        public static let SESSION_PREFIX = "https://developer.apple.com/videos/play/wwdc\(YEAR)"
    }

    let sessionId: String

    let queue = DispatchQueue(label: "af.networking", qos: .background, attributes: .concurrent)

    private func requestUrl(url: String,  completion: @escaping (String) -> Void) {
        AF.request(url).responseString(queue: queue) {
            switch $0.result {
            case .success(let content):
                completion(content)
            case .failure(let error):
                print(error)
            }
        }
    }

    private func requestUrlPublisher(url: String) -> AnyPublisher<String, AFError> {
        return AF.request(url).publishString(queue: queue).value()
    }

    private func downloadMp4(url: String, with fileName: String, completion: @escaping () -> Void) {
        let destination: DownloadRequest.Destination = { _, _ in
            let documentsURL = FileManager.default.urls(for: .documentDirectory, in:.userDomainMask)[0]
            let fileURL = documentsURL.appendingPathComponent(fileName)

            return (fileURL, [.removePreviousFile, .createIntermediateDirectories])
        }

        var progressbar = ProgressBar(count: 100, configuration: [ProgressString(string: "Video downloading:"), ProgressPercent()])

        AF.download(url, to: destination)
            .downloadProgress(queue: queue) {
                progressbar.setValue(Int($0.fractionCompleted * 100))
            }
            .response(queue: queue) { response in
                if let path = response.fileURL?.path {
                    print("Video downloaded at: \(path)")
                }
                completion()
            }
    }
    
    func downloadVideo(quality: String, completion: @escaping () -> Void) {
        var cancellables = [AnyCancellable]()

        let sessionUrl = String(format: "%@/%@", WWDC.SESSION_PREFIX, sessionId)

        requestUrlPublisher(url: sessionUrl)
            .compactMap { getMp4Url(in: $0, quality: quality) }
            .subscribe(on: queue)
            .sink(receiveCompletion: { _ in
            }, receiveValue: {
                if let fileName = URL(string: $0)?.lastPathComponent {
                    downloadMp4(url: $0, with: fileName, completion: completion)
                }
            })
            .store(in: &cancellables)
    }

    func downloadSrt(language: String, quality: String) {
        var cancellables = [AnyCancellable]()
        let sessionUrl = String(format: "%@/%@", WWDC.SESSION_PREFIX, sessionId)
        
        let m3u8UrlPublisher = requestUrlPublisher(url: sessionUrl)
            .compactMap { getM3U8Url(in: $0) }

        let webvvtsUrlPublisher = m3u8UrlPublisher
            .flatMap { requestUrlPublisher(url: $0) }
            .zip(m3u8UrlPublisher)
            .compactMap { getWebvttsUrl(in: $0, m3u8Url: $1, language: language) }

        let fileNamePublisher = requestUrlPublisher(url: sessionUrl)
            .compactMap { getMp4Url(in: $0, quality: quality) }
            .compactMap {
                URL(string:$0)?
                    .deletingPathExtension()
                    .appendingPathExtension("srt")
                    .lastPathComponent
            }

        var srtCount = 0
        var vvtCount = 0
        var vvtProgress = 0
        var progressbar: ProgressBar? = nil

        webvvtsUrlPublisher
            .flatMap { requestUrlPublisher(url: $0.absoluteString) }
            .zip(webvvtsUrlPublisher)
            .compactMap({ (webvttsContent, webvttsUrl) -> [String]? in
                let webvvtUrlArray = getWebvvtUrlArray(in: webvttsContent, webvttsUrl: webvttsUrl)
                if let cnt = webvvtUrlArray?.count {
                    vvtCount = cnt
                    progressbar = ProgressBar(count: vvtCount,
                                              configuration: [ProgressString(string: "Subtitle downloading:"), ProgressPercent()])
                }
                return webvvtUrlArray
            })
            .flatMap { $0.publisher }
            .flatMap(maxPublishers: .max(1), { webvvtUrl -> AnyPublisher<String, AFError> in
                vvtProgress += 1
                progressbar?.setValue(vvtProgress)
                return requestUrlPublisher(url: webvvtUrl)
            })
            .compactMap { parseWebvvtToSrt(webvvt: $0) }
            .flatMap { $0.publisher }
            .reduce("") { srt, subtitle in
                srtCount += 1
                return srt + "\(srtCount)" + "\n" + subtitle + "\n\n"
            }
            .zip(fileNamePublisher)
            .subscribe(on: queue)
            .sink(receiveCompletion: { _ in }, receiveValue: {
                let documentsURL = FileManager.default.urls(for: .documentDirectory, in:.userDomainMask)[0]
                let fileURL = documentsURL.appendingPathComponent($1)

                do {
                    try $0.write(to: fileURL, atomically: true, encoding: String.Encoding.utf8)
                    print("Subtitle downloaded at: \(fileURL.path)")
                } catch {
                }
            })
            .store(in: &cancellables)
    }
}
