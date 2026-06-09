/**
 * nonto video_player_ohos — 鸿蒙端原生实现
 *
 * 基于 AVPlayer + Texture（外接纹理）实现视频硬件解码播放。
 * 通过 MethodChannel 与 Dart 层通信，接口对齐官方 video_player 插件。
 *
 * 核心流程：
 *   1. Dart 调用 init/create → 创建 AVPlayer 实例 + 注册 Texture
 *   2. Dart 收到 textureId → 用 Texture widget 渲染
 *   3. play/pause/seek → 控制 AVPlayer 播放状态
 *   4. dispose → 释放 AVPlayer + 注销 Texture
 */

import { MethodChannel, FlutterPlugin, FlutterPluginBinding, TextureRegistry,
  MethodCallHandler, MethodCall, MethodResult } from '@ohos/flutter_ohos';
import { media } from '@kit.MediaKit';
import { AVPlayerManager } from './AVPlayerManager';

const CHANNEL_NAME = 'nonto_video_player';

export class VideoPlayerOhosPlugin implements FlutterPlugin, MethodCallHandler {
  private channel: MethodChannel | null = null;
  private playerManager: AVPlayerManager = new AVPlayerManager();
  private textureRegistry: TextureRegistry | null = null;

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.channel = new MethodChannel(binding.getBinaryMessenger(), CHANNEL_NAME);
    this.channel.setMethodCallHandler(this);
    this.textureRegistry = binding.getTextureRegistry();
    this.playerManager.setTextureRegistry(this.textureRegistry);
  }

  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    this.playerManager.disposeAll();
    this.channel?.setMethodCallHandler(null);
    this.channel = null;
    this.textureRegistry = null;
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    switch (call.method) {
      case 'create':
        this.handleCreate(call, result);
        break;
      case 'init':
        this.handleInit(call, result);
        break;
      case 'play':
        this.playerManager.play();
        result.success(null);
        break;
      case 'pause':
        this.playerManager.pause();
        result.success(null);
        break;
      case 'seekTo':
        this.playerManager.seekTo(call.argument('position') as number);
        result.success(null);
        break;
      case 'dispose':
        this.playerManager.dispose();
        result.success(null);
        break;
      default:
        result.notImplemented();
    }
  }

  private async handleCreate(call: MethodCall, result: MethodResult): Promise<void> {
    try {
      const textureId = this.playerManager.create();
      result.success(textureId.toString());
    } catch (e) {
      result.error('CREATE_ERROR', e.message, null);
    }
  }

  private async handleInit(call: MethodCall, result: MethodResult): Promise<void> {
    const source = call.argument('source') as string;
    const isAsset = call.argument('isAsset') as boolean;
    const isFile = call.argument('isFile') as boolean;

    try {
      const avPlayer = await media.createAVPlayer();
      await this.playerManager.initAVPlayer(avPlayer, source, isAsset, isFile);

      // 设置播放状态回调
      avPlayer.on('stateChange', (state: string) => {
        if (state === 'prepared') {
          this.channel?.invokeMethod('onPrepared', {
            duration: avPlayer.duration,
            aspectRatio: this.playerManager.getAspectRatio(avPlayer),
          });
        } else if (state === 'completed') {
          this.channel?.invokeMethod('onCompletion', null);
        }
      });

      // 设置播放进度回调（每500ms回调一次）
      avPlayer.on('timeUpdate', (time: number) => {
        this.channel?.invokeMethod('onPositionUpdate', time);
      });

      result.success(null);
    } catch (e) {
      result.error('INIT_ERROR', e.message, null);
    }
  }
}