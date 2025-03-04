/*
 *  Copyright (c) 2021 NetEase, Inc.  All rights reserved.
 *  Use of this source code is governed by a MIT license that can be found in the LICENSE file
 */

package com.netease.yunxin.app.wisdom.record.video.sdk.extension;


import com.netease.yunxin.app.wisdom.record.video.sdk.LivePlayerObserver;
import com.netease.yunxin.app.wisdom.record.video.sdk.model.MediaInfo;

/**
 * 播放器状态回调观察者
 * <p>
 *
 * @author netease
 */

public abstract class SimpleLivePlayerObserver implements LivePlayerObserver {
    @Override
    public void onPreparing() {

    }

    @Override
    public void onPrepared(MediaInfo mediaInfo) {

    }

    @Override
    public void onError(int code, int extra) {

    }

    @Override
    public void onFirstVideoRendered() {

    }

    @Override
    public void onFirstAudioRendered() {

    }

    @Override
    public void onBufferingStart() {

    }

    @Override
    public void onBufferingEnd() {

    }

    @Override
    public void onBuffering(int percent) {

    }

    @Override
    public void onVideoDecoderOpen(int value) {

    }
}
