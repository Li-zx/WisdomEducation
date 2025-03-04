//
//  NEEduRecorderPlayer.swift
//  NERecordPlay
//
//  Created by 郭园园 on 2021/8/9.
//

import Foundation
import NELivePlayerFramework

enum ScrollDirection {
    case right
    case left
}

public class NEEduRecorderPlayerManager: NSObject, NEEduRecordPlayerProtocol, NEEduRecordPlayerDelegate {
    
    public var state: PlayState {
        get {
            return firstPlayerItem?.state ?? .idle
        }
    }
    
    public weak var delegate: NEEduRecordPlayerDelegate?
    public var duration: Double {
        get {
            return firstPlayerItem?.duration ?? 0
        }
    }
    var data: RecordData
    var wbContentView: UIView
    var firstPlayerItem: NEEduRecordPlayer?
    
    /// 用户视频数据视频数据列表，不包含辅流
    public var recordList: Array<RecordItem> = []
    
    /// 白板地址列表
    var wbUrlList: Array<String> = []
    
    /// 辅流列表
    var subStreamList: Array<RecordItem> = []
    
    /// 初始化的总的播放器列表，包含主流和辅流播放器。
    public var playerList = [NEEduRecordPlayer]()
    
    /// 当前正在播放的播放器列表
    var playingPlayers = [NEEduRecordPlayer]()
    
    /// 当前正在播放的播放器列表
    var preparePlayPlayers = [NEEduRecordPlayer]()
    
    /// 当前正在播放的RecordItem
    public var playingRecordItems = [RecordItem]()
    
    public var playerDic: [String:NEEduRecordPlayer] = [:]
    var wbPlayer:NEEduWBPlayItem?
    var preparedNumber = 0
    var fininshedNum = 0
    
    /// 时间：事件，时间单位秒
    var timeEvent: [Int:Event] = [:]
    var subPlayer: NEEduRecordPlayer?
    let eventPair = [2:1,8:7]
    var currentTime: Double = 0
    
    public init(data: RecordData, view:UIView) {
        self.data = data
        self.wbContentView = view;
        super.init()
        self.handleData(data: data)
        // 创建视频播放器列表
        self.playerList = createVideoPlayer(recordList: recordList)
        // 创建白板播放器
        self.wbPlayer = createWBPlayer(wbUrlList: wbUrlList)
        // 创建辅流播放器
        self.subPlayer = createSubStreamPlayer()
    }
    
    /// 对元数据分类处理
    /// - Parameter data: 元数据
    func handleData(data:RecordData) {
        for item in data.recordItemList {
            if item.type == .mp4 {
                if item.subStream {
                    subStreamList.append(item)
                }else {
                    item.isTeacher() ? recordList.insert(item, at: 0) : recordList.append(item)
                }
            }else {
                wbUrlList.append(item.url)
            }
        }
        print("recordList:\(recordList)\n subStreamList:\(subStreamList)\n wbUrlList:\(wbUrlList)")
        for event in data.eventList {
            if event.type == 4 || event.type == 5 || event.type == 6 || event.type == 3 {
                continue
            }
            let timeKey = (event.timestamp - data.record.startTime)/1000
            timeEvent[timeKey] = event
        }
        print("timeEvent:\(timeEvent)");
    }
    
    /// 创建播放器
    /// - Parameter recordList: 视频地址列表
    /// - Returns: 播放器列表
    func createVideoPlayer(recordList:[RecordItem]) -> [NEEduRecordPlayer] {
        var itemList = [NEEduRecordPlayer]()
        for recordItem in recordList {
            do {
                let item = try NEEduRecordPlayer(url: recordItem.url)
                item.startOffSet = Double(recordItem.timestamp - data.record.startTime) / 1000
                item.delegate = self
                itemList.append(item)
                playerDic[recordItem.url] = item
                //统计刚进入回放就需要播放的播放器
                let offset = (recordItem.timestamp - data.record.startTime)/1000
                if Int(offset) == 0 {
                    if recordItem.isTeacher() {
                        self.firstPlayerItem = item
                        item.asTimeline = true
                        playingPlayers.insert(item, at: 0)
                        playingRecordItems.insert(recordItem, at: 0)
                    }else {
                        playingPlayers.append(item)
                        playingRecordItems.append(recordItem)
                    }
                }else {
                    preparePlayPlayers.append(item)
                }
            } catch  {
                print("error: initPlayer:\(error)")
            }
        }
        return itemList
    }
    
    func resetPlayers(recordList:[RecordItem]) {
        var players = [NEEduRecordPlayer]()
        var items = [RecordItem]()
        for item in recordList {
            guard let player = playerDic[item.url] else {
                print("error:playerDic中获取player为空url:\(item.url)")
                continue
            }
//            player.pause()
            player.startOffSet = Double(item.timestamp - data.record.startTime) / 1000
//            player.seekTo(time: 0)
            if Int((item.timestamp - data.record.startTime)/1000) == 0 {
                if item.isTeacher() {
                    self.firstPlayerItem = player
                    player.asTimeline = true
                    players.insert(player, at: 0)
                    items.insert(item, at: 0)
                }else {
                    players.append(player)
                    items.append(item)
                }
            }else {
                print("时间:\(Int((item.timestamp - data.record.startTime)/1000))")
            }
        }
        playingPlayers = players
        playingRecordItems = items
        // 初始化辅流播放器
        subPlayer = createSubStreamPlayer()
        print("resetPlayers\(playingPlayers.count) playingRecordItems:\(playingRecordItems.count)")
        self.delegate?.onResetPlayer(player: self)
    }
  
    /// 创建白板播放器
    /// - Returns: 播放器
    func createWBPlayer(wbUrlList: Array<String>) -> NEEduWBPlayItem {
        let wbPlayerItem = NEEduWBPlayItem.init(urls: wbUrlList,contentView: self.wbContentView)
        wbPlayerItem.delegate = self
        return wbPlayerItem
    }
    
    func createSubVideoPlayer(recordItem: RecordItem, event: Event) -> NEEduRecordPlayer? {
        if recordItem.url.count <= 0 {
            return nil
        }
        if subPlayer != nil {
            subPlayer?.pause()
            subPlayer?.startOffSet = Double(recordItem.timestamp - data.record.startTime) / 1000
            subPlayer?.subStreamOffSet = Double(event.timestamp - recordItem.timestamp) / 1000
            subPlayer?.seekTo(time: 0)
        }else {
            do {
                try subPlayer = NEEduRecordPlayer(url: recordItem.url)
                subPlayer?.delegate = self
                subPlayer?.startOffSet = Double(recordItem.timestamp - data.record.startTime) / 1000
                subPlayer?.subStreamOffSet = Double(event.timestamp - recordItem.timestamp) / 1000
                subPlayer?.prepareToPlay()
            } catch  {
                print("error: initPlayer:\(error)")
            }
        }
        return subPlayer
    }
    
    func createSubStreamPlayer() -> NEEduRecordPlayer? {
        //1.找到第一个event.type == 7的事件
        var firstEvent: Event?
        for tmp in data.eventList {
            if tmp.type == 7 {
                firstEvent = tmp
                break
            }
        }
        guard let event = firstEvent else {
            return nil
        }
        //2.通过event找到record
        var recordItem: RecordItem?
        for item in subStreamList {
            if Int(event.roomUid) == item.roomUid {
                recordItem = item
                break
            }
        }
        guard let record = recordItem else {
            return nil
        }
        return createSubVideoPlayer(recordItem: record, event: event)
    }
// MARK: - NEEduRecordPlayProtocol
    public func prepareToPlay() {
        for item in playingPlayers {
            item.prepareToPlay()
        }
        
        for prepareItem in preparePlayPlayers {
            prepareItem.prepareToPlay()
        }
    }
    public func play() {
        for item in playingPlayers {
            item.play()
        }
        wbPlayer?.play()
    }
    
    public func pause() {
        for item in playingPlayers {
            item.pause()
        }
        wbPlayer?.pause()
    }

    public func seekTo(time: Double) {
        currentTime = firstPlayerItem?.currentTime ?? 0
        print("seekCurrentTime:\(currentTime) toTime:\(time)")
        //  事件处理
        if currentTime < time {
            //right
            for item in playingPlayers {
                item.seekTo(time: time)
            }
            wbPlayer?.seekTo(time: time)
            
            handleSeekToRightEvent(fromTime: currentTime, toTime: time)
        }else {
            //left
            resetPlayers(recordList: data.recordItemList)
            
            for item in playingPlayers {
                item.seekTo(time: time)
            }
            wbPlayer?.seekTo(time: time)
            handleSeekToLeftEvent(fromTime: currentTime, toTime: time)
        }
    }
    
    public func stop() {
        for item in playingPlayers {
            item.stop()
        }
        subPlayer?.stop()
        wbPlayer?.stop()
    }
    
    public func muteAudio(mute: Bool) {
        for item in playingPlayers {
            item.muteAudio(mute: mute)
        }
    }

// MARK:
    
    // 向右拖拽事件处理
    private func handleSeekToRightEvent(fromTime: Double, toTime: Double) {
        filterEvent(fromTime: fromTime, toTime: toTime, direction: .right)
    }
    // 向左拖拽事件处理
    private func handleSeekToLeftEvent(fromTime: Double, toTime: Double) {
        filterEvent(fromTime: fromTime, toTime: toTime, direction: .left)
    }
    // 成对事件消除处理
    private func filterEvent(fromTime: Double, toTime: Double, direction: ScrollDirection) {
//         折叠时间点之前事件，执行剩下的事件
        var dic = [String:Event]()
        var array = [Event]()
        print("eventList:\(data.eventList) count:\(data.eventList.count)")
        for event in data.eventList {
            print("eventType:\(event.type)\n 事件时间：\(event.timestamp) 时长：\((event.timestamp - data.record.startTime)/1000)")
            let point = (event.timestamp - data.record.startTime)/1000
            if direction == .right {
                if point > Int(toTime) || point < Int(fromTime) {
                    continue
                }
            }else {
                if point > Int(toTime) {
                    continue
                }
            }
            let key = String("\(event.type)\(event.roomUid)")
            let pairType = self.eventPair[event.type]
            let pairKey = String("\(pairType)\(event.roomUid)")
            //先看下配对事件是否已存在，不存在则加入数组，存在则消消乐
            let pairEvent = dic[pairKey]
            if pairEvent == nil {
                dic[key] = event
                array.append(event)
            }else {
                dic.removeValue(forKey: pairKey)
                for (index, event) in array.enumerated() {
                    if event.roomUid == pairEvent?.roomUid,event.type == pairEvent?.type {
                        print("will remove at\(index)")
                        array.remove(at: index)
                        break
                    }
                }
            }
        }
        print("最终的事件：\(array)个数：\(array.count)")
        for event in array {
            handleEvent(event: event, to: toTime)
        }
    }

//    MARK:NEEduRecordPlayEvent
    public func onPrepared(playerItem: Any) {
        if let wbPlayer = playerItem as? NEEduWBPlayItem {
            wbPlayer.setDuration(startTime: data.record.startTime, endTime: data.record.stopTime)
        }
        if let player = playerItem as? NEEduRecordPlayer,Int(player.startOffSet) == 0 {
            preparedNumber += 1
        }
        if (preparedNumber == playingPlayers.count) {
            delegate?.onPrepared(playerItem: firstPlayerItem)
        }
    }
    
    public func onPlay(player: Any) {
        delegate?.onPlay(player: self)
    }
    
    public func onPause(player: Any) {
        delegate?.onPause(player: self)
    }
    
    //FIXME:单位按照秒算
    public func onSeeked(player: Any, time: Double, errorCode: Int) {
        if let playerItem = player as? NEEduRecordPlayer, playerItem.url == self.firstPlayerItem?.url {
            delegate?.onSeeked(player: self, time: time, errorCode: errorCode)
        }
    }
    
    public func onFinished(player: Any) {
        if let playerItem = player as? NEEduRecordPlayer, playerItem.url == self.firstPlayerItem?.url {
            resetPlayers(recordList: data.recordItemList)
            delegate?.onFinished(player: self)
            print("11播放完成：\(playerItem.url) \(playerItem.asTimeline)")
        }
    }
    
    public func onError(player: Any, errorCode: Int) {
        delegate?.onError(player: self, errorCode: errorCode)
    }
    
    public func onPlayTime(player: NEEduRecordPlayerProtocol, time: Double) {
        if let player = player as? NEEduRecordPlayer, player.asTimeline, player.state != .finished {
            delegate?.onPlayTime(player: self, time: time)
            // 查找是否有需要执行的事件
            
            let timeKey = Int(time)
            print("播放时间：\(timeKey) in timeEvent:\(timeEvent)");
            guard let event = timeEvent[timeKey] else {
                return
            }
            print("播放器:\(player) 播放时间：\(timeKey)");
            print("播放器:event:\(event.type)")
            let to  =  Double((event.timestamp - data.record.startTime) / 1000)
            handleEvent(event: event, to: to)
        }
    }
    public func onSubStreamStart(player: NEEduRecordPlayerProtocol, videoView: UIView?) {
        
    }
    
    public func onSubStreamStop(player: NEEduRecordPlayerProtocol, videoView: UIView?) {
        
    }
    
    public func userEnter(item: RecordItem) {
    }
    
    public func userLeave(item: RecordItem) {
        
    }
    public func onResetPlayer(player: NEEduRecordPlayerProtocol) {
        
    }
    
//    MARK: 回放事件
    /*
     事件类型
     1：成员进入房间
     2：成员离开房间
     3：成员打开音频
     4：成员关闭音频
     5：成员打开视频
     6：成员关闭视频
     7：成员打开辅流
     8：成员关闭辅流
     9:成员上台（大班课）
     10:成员下台（大班课）
     */
    func handleEvent(event: Event, to:Double) {
        switch event.type {
        case 1:
            if data.sceneType == "EDU.BIG" {
                return
            }
            userEnter(event: event,to: to)
        case 2:
            if data.sceneType == "EDU.BIG" {
                return
            }
            userLeave(event: event)
        case 7:
            startShareSceen(event: event, to:to)
        case 8:
            stopShareSceen(event: event)
        case 9:
            userEnter(event: event,to: to)
        case 10:
            userLeave(event: event)
        default:
            break
        }
    }
    
    func userEnter(event: Event, to: Double) {
        let record = findUrlOfUser(roomUid: Int(event.roomUid) ?? 0)
        guard let recordItem = record else {
            return
        }
        guard let player = playerDic[recordItem.url]  else {
            return
        }
        player.play()
        let offset = to - player.startOffSet
        print("用户进入时间偏移：\(offset)")
        if offset > 0 {
            player.seekTo(time: offset)
        }
        if playingRecordItems.contains(where: { item in
            return item.url == recordItem.url
        }) { return }
        
        if recordItem.isTeacher() {
            playingRecordItems.insert(recordItem, at: 0)
            playingPlayers.insert(player, at: 0)
        }else {
            playingRecordItems.append(recordItem)
            playingPlayers.append(player)
        }
        delegate?.userEnter(item: recordItem)
    }
    
    func userLeave(event: Event) {
        let record = findUrlOfUser(roomUid: Int(event.roomUid) ?? 0)
        guard let recordItem = record else {
            return
        }
        guard let player = playerDic[recordItem.url]  else {
            return
        }
        player.pause()
        for (index,item) in playingRecordItems.enumerated() {
            if item.url == recordItem.url {
                playingRecordItems.remove(at: index)
                playingPlayers.remove(at: index)
            }
        }
        delegate?.userLeave(item: recordItem)
    }
    
    func startShareSceen(event: Event, to:Double) {
        guard let player = self.subPlayer else {
            return
        }
        if player.state == .playing {
            stopShareSceen(event: nil)
        }
        var recordItem: RecordItem?
        for item in subStreamList {
            if Int(event.roomUid) == item.roomUid {
                recordItem = item
                break
            }
        }
        guard let record = recordItem else {
            return
        }
        player.startOffSet = Double(record.timestamp - data.record.startTime) / 1000
        let offset1 = to - player.startOffSet
        let offset2 = Double(event.timestamp - record.timestamp) / 1000
        player.subStreamOffSet = max(offset1, offset2)
        
        if player.url == record.url {
            player.play()
        }else {
            player.updateUrl(url: record.url)
            player.play()
        }
        delegate?.onSubStreamStart(player: player, videoView: player.view)
    }
    
    func stopShareSceen(event: Event?) {
        print("屏幕共享结束\(event?.roomUid)")
        guard let player = subPlayer else {
            return
        }
        subPlayer?.pause()
        delegate?.onSubStreamStop(player: player, videoView: player.view)
    }

    private func findUrlOfUser(roomUid: Int) -> (RecordItem?) {
        for item in recordList {
            if roomUid == item.roomUid {
                return item
            }
        }
        return nil
    }
    
    deinit {
        print("deinit NEEduRecorderPlayer")
    }
}


