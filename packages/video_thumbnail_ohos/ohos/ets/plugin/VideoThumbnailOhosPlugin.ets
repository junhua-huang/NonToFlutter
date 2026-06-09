/**
 * video_thumbnail_ohos — 鸿蒙端原生实现
 *
 * 使用 AVImageGenerator 从视频中提取指定位置的帧，
 * 编码为 JPEG 后通过 MethodChannel 返回给 Dart 层。
 */

import { MethodChannel, FlutterPlugin, FlutterPluginBinding,
  MethodCallHandler, MethodCall, MethodResult } from '@ohos/flutter_ohos';
import { media } from '@kit.MediaKit';
import { image } from '@kit.ImageKit';

const CHANNEL_NAME = 'nonto_video_thumbnail';

export class VideoThumbnailOhosPlugin implements FlutterPlugin, MethodCallHandler {
  private channel: MethodChannel | null = null;

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.channel = new MethodChannel(binding.getBinaryMessenger(), CHANNEL_NAME);
    this.channel.setMethodCallHandler(this);
  }

  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    this.channel?.setMethodCallHandler(null);
    this.channel = null;
  }

  async onMethodCall(call: MethodCall, result: MethodResult): Promise<void> {
    if (call.method === 'extractThumbnail') {
      await this.handleExtract(call, result);
    } else {
      result.notImplemented();
    }
  }

  private async handleExtract(call: MethodCall, result: MethodResult): Promise<void> {
    const videoPath = call.argument('videoPath') as string;
    const positionMs = call.argument('positionMs') as number;
    const maxWidth = call.argument('maxWidth') as number;
    const maxHeight = call.argument('maxHeight') as number;
    const quality = call.argument('quality') as number;

    try {
      // 1. 创建 AVImageGenerator
      const avImageGen = await media.createAVImageGenerator();
      avImageGen.fdSrc = { fd: videoPath };

      // 2. 按时间点抓取一帧
      const pixelMap = await avImageGen.fetchFrameByTime(positionMs * 1000, {
        width: maxWidth,
        height: maxHeight,
      });

      // 3. 编码为 JPEG
      const packer = image.createImagePacker();
      const jpegBuffer = await packer.packing(pixelMap, {
        format: 'image/jpeg',
        quality: quality,
      });

      // 4. 返回字节数组
      result.success({ data: jpegBuffer });

      // 5. 释放资源
      avImageGen.release();
      pixelMap.release();
      packer.release();
    } catch (e) {
      result.error('THUMBNAIL_ERROR', e.message, null);
    }
  }
}