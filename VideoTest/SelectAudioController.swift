//
//  SelectAudioController.swift
//  VideoTest
//
//  Created by Fluper on 28/03/19.
//  Copyright © 2019 Fluper. All rights reserved.
//

import UIKit
import AVKit
import Photos
import SDWebImage

class MusicDataSource {
    var name: String = ""
    var author: String = ""
    var music: String = ""
    var image: String = ""
    
    init() {}
    
    init(with dict: [String: Any]) {
        self.name = dict["name"] as? String ?? ""
        self.author = dict["singer"] as? String ?? ""
        self.music = dict["music"] as? String ?? ""
        self.image = dict["image"] as? String ?? ""
    }
}

class SelectAudioController: UIViewController {

    @IBOutlet weak var tableView: UITableView!
    var videoUrl: URL?
    var dataSource = [MusicDataSource]()
    var showLoaderAt = -1
    
    override func viewDidLoad() {
        super.viewDidLoad()
        initialSetup()
    }
    
    private func initialSetup() {
        self.title = "Select Audio"
        tableView.dataSource = self
        tableView.delegate = self
        tableView.tableFooterView = UIView()
        pullMusicData()
    }
    
    func pullMusicData() {
        guard let url = URL(string: "http:3.19.41.190/api/music_list.php?type=tiktok") else { return }
        URLSession.shared.dataTask(with: url) { (data, response, error) in
            
            guard let dataResponse = data, error == nil else {
                    print(error?.localizedDescription ?? "Response Error")
                    return }
            do{
                
                let jsonResponse = try JSONSerialization.jsonObject(with:
                    dataResponse, options: [])
                guard let jsonArray = jsonResponse as? [String: Any] else {
                    return
                }
                guard let musicData = jsonArray["data"] as? [[String: Any]] else { return }
                musicData.forEach({ (data) in
                    self.dataSource.append(MusicDataSource(with: data))
                })
                DispatchQueue.main.async {
                    self.tableView.reloadData()
                }
            } catch let parsingError {
                print("Error", parsingError)
            }
        }.resume()
    }
    
    func downloadFileFromURL(url: URL){
        
        var downloadTask: URLSessionDownloadTask
        downloadTask = URLSession.shared.downloadTask(with: url, completionHandler: { [weak self] (URL, response, error) -> Void in
            self?.mergeVideoAndAudio(audioUrl: url)
        })
        downloadTask.resume()
    }
    
    func mergeVideoAndAudio(audioUrl: URL) {
        
        showLoaderAt = -1
        
        guard let videoUrl = videoUrl else { return }
        let videoAsset = AVAsset(url: videoUrl)
        let loadedAudioAsset = AVAsset(url: audioUrl)
        
        print("playing \(audioUrl)")
        print("Time to merge \(videoAsset) ::::::::: \(loadedAudioAsset)")
        
        let mixComposition = AVMutableComposition()
        
        guard let firstTrack = mixComposition.addMutableTrack(withMediaType: .video, preferredTrackID: Int32(kCMPersistentTrackID_Invalid)) else { return }
        do {
            try firstTrack.insertTimeRange(CMTimeRangeMake(start: CMTime.zero, duration: videoAsset.duration), of: videoAsset.tracks(withMediaType : .video)[0], at: CMTime.zero)
        } catch {
            print("Failed To Load First Track")
            return
        }
        
        let mainInstruction = AVMutableVideoCompositionInstruction()
        mainInstruction.timeRange = CMTimeRangeMake(start: CMTime.zero, duration: videoAsset.duration)
        
        let firstInstruction = VideoHelper.videoCompositionInstruction(firstTrack, asset: videoAsset)
        firstInstruction.setOpacity(0.0, at: videoAsset.duration)
    
        mainInstruction.layerInstructions = [firstInstruction]
        let mainComposition = AVMutableVideoComposition()
        mainComposition.instructions = [mainInstruction]
        mainComposition.frameDuration = CMTimeMake(value: 1, timescale: 30)
        mainComposition.renderSize = CGSize(width: UIScreen.main.bounds.width, height: UIScreen.main.bounds.height)
    
        let audioTrack = mixComposition.addMutableTrack(withMediaType: .audio, preferredTrackID: 0)
        do {
            try audioTrack?.insertTimeRange(CMTimeRangeMake(start: CMTime.zero, duration: videoAsset.duration), of: loadedAudioAsset.tracks(withMediaType: .audio)[0], at: CMTime.zero)
        } catch {
            print("Failed To Load Audio Track")
            return
        }
        
        guard let documentDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .long
        dateFormatter.timeStyle = .short
        let date = dateFormatter.string(from: Date())
        let url = documentDirectory.appendingPathComponent("mergeVideo-\(date).mov")
        
        guard let exporter = AVAssetExportSession(asset: mixComposition, presetName: AVAssetExportPresetHighestQuality) else { return }
        exporter.outputURL = url
        exporter.outputFileType = AVFileType.mov
        exporter.shouldOptimizeForNetworkUse = true
        exporter.videoComposition = mainComposition  
        
        exporter.exportAsynchronously() {
            DispatchQueue.main.async {
                self.exportDidFinish(exporter)
                self.tableView.reloadData()
            }
        }
    }
    
    func exportDidFinish(_ session: AVAssetExportSession) {
        
        guard session.status == AVAssetExportSession.Status.completed,
        let outputURL = session.outputURL else { return }
        
        let saveVideoToPhotos = {
            PHPhotoLibrary.shared().performChanges({ PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: outputURL) }) { saved, error in

                let player = AVPlayer(url: outputURL)
                let vcPlayer = AVPlayerViewController()
                vcPlayer.player = player
                self.present(vcPlayer, animated: true, completion: {
                    self.navigationController?.popViewController(animated: true)
                })
            }
        }
        
        if PHPhotoLibrary.authorizationStatus() != .authorized {
            PHPhotoLibrary.requestAuthorization({ status in
                if status == .authorized {
                    saveVideoToPhotos()
                }
            })
        } else {
            saveVideoToPhotos()
        }
    }
}

extension SelectAudioController: UITableViewDataSource, UITableViewDelegate {
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return dataSource.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        
        let cell = tableView.dequeueReusableCell(withIdentifier: "SongCell", for: indexPath)
        
        if let cell = cell as? SongCell {
            
            cell.setup(dataSource[indexPath.row], showLoader: showLoaderAt == indexPath.row ? true : false)
        }
        
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        showLoaderAt = indexPath.row
        tableView.reloadData()
        guard let url = URL(string: dataSource[indexPath.row].music) else { return }
        downloadFileFromURL(url: url)
    }
}

class SongCell: UITableViewCell {
    @IBOutlet weak var imgView: UIImageView!
    @IBOutlet weak var nameLabel: UILabel!
    @IBOutlet weak var descLabel: UILabel!
    @IBOutlet weak var loader: UIActivityIndicatorView!
    
    func setup(_ data: MusicDataSource, showLoader: Bool) {
        imgView.sd_setImage(with: URL(string: data.image), completed: nil)
        nameLabel.text = data.name
        descLabel.text = "By - \(data.author)"
        loader.isHidden = showLoader ? false : true
        showLoader ? loader.startAnimating() : loader.stopAnimating()
    }
    
}
