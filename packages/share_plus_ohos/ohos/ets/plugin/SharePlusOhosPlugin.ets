/**
 * share_plus_ohos — 鸿蒙端原生实现
 *
 * 通过 systemShare.startAbility 启动系统分享面板，
 * 支持分享文本、图片、视频等类型。
 */

import { MethodChannel, FlutterPlugin, FlutterPluginBinding,
  MethodCallHandler, MethodCall, MethodResult } from '@ohos/flutter_ohos';
import { Want } from '@kit.AbilityKit';
import { common } from '@kit.AbilityKit';

const CHANNEL_NAME = 'nonto_share';

export class SharePlusOhosPlugin implements FlutterPlugin, MethodCallHandler {
  private channel: MethodChannel | null = null;
  private context: common.UIAbilityContext | null = null;

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.channel = new MethodChannel(binding.getBinaryMessenger(), CHANNEL_NAME);
    this.channel.setMethodCallHandler(this);
    this.context = binding.getAbilityContext();
  }

  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    this.channel?.setMethodCallHandler(null);
    this.channel = null;
    this.context = null;
  }

  async onMethodCall(call: MethodCall, result: MethodResult): Promise<void> {
    if (call.method === 'share') {
      await this.handleShare(call, result);
    } else {
      result.notImplemented();
    }
  }

  private async handleShare(call: MethodCall, result: MethodResult): Promise<void> {
    const text = call.argument('text') as string;
    const subject = call.argument('subject') as string;
    const filePath = call.argument('filePath') as string;

    try {
      const want: Want = {
        action: 'ohos.want.action.sendData',
        flags: 1,  // FLAG_ABILITY_NEW_MISSION
        parameters: {
          'shareText': text,
          'shareTitle': subject,
          'shareFile': filePath,
        },
      };

      // 启动系统分享面板
      await this.context?.startAbility(want);
      result.success(null);
    } catch (e) {
      result.error('SHARE_ERROR', e.message, null);
    }
  }
}