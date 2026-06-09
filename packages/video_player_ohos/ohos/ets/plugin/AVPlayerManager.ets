/**
 * AVPlayerManager — 管理 AVPlayer 生命周期与 Texture 绑定
 *
 * 每个播放器实例绑定一个 SurfaceTextureEntry（外接纹理），
 * AVPlayer 解码的视频帧直接渲染到该纹理上，Flutter 引擎通过 Texture widget 显示。
 */

import { media } from '@kit.MediaKit';
import { TextureRegistry } from '@ohos/flutter_ohos';

interface PlayerEntry {
  avPlayer: media.AVPlayer;
  textureEntry: TextureRegistry.SurfaceTextureEntry;
}

export class AVPlayerManager {
  private players: Map<number, PlayerEntry> = new Map();
  private textureRegistry: TextureRegistry | null = null;
  private nextId: number = 1;

  setTextureRegistry(registry: TextureRegistry): void {
    this.textureRegistry = registry;
  }

  /** 创建播放器入口，注册 Texture，返回 textureId */
  create(): number {
    if (!this.textureRegistry) {
      throw new Error('TextureRegistry not initialized');
    }

    const textureEntry = this.textureRegistry.createSurfaceTexture();
    const id = this.nextId++;

    // 暂存 entry（AVPlayer 在 init 后才关联）
    this.players.set(id, {
      avPlayer: null!,
      textureEntry: textureEntry,
    });

    return id;
  }

  /** 初始化 AVPlayer，绑定数据源与纹理 */
  async initAVPlayer(
    avPlayer: media.AVPlayer,
    source: string,
    isAsset: boolean,
    isFile: boolean,
  ): Promise<void> {
    // 查找未绑定 AVPlayer 的 entry（最近创建的）
    let targetEntry: PlayerEntry | undefined;
    for (const entry of this.players.values()) {
      if (!entry.avPlayer) {
        targetEntry = entry;
        break;
      }
    }

    if (!targetEntry) {
      throw new Error('No uninitialized player entry found');
    }

    // 绑定 AVPlayer到 entry
    targetEntry.avPlayer = avPlayer;

    // 绑定纹理 surface 到 AVPlayer
    const surfaceId = targetEntry.textureEntry.id();
    avPlayer.surfaceId = surfaceId;

    // 设置数据源
    if (isAsset) {
      // 鸿蒙端 asset 路径：rawfile 下的文件
      avPlayer.url = `rawfile://${source}`;
    } else if (isFile) {
      avPlayer.url = `file://${source}`;
    } else {
      // 网络 URL
      avPlayer.url = source;
    }

    // 预加载
    await avPlayer.prepare();
  }

  /** 获取视频宽高比 */
  getAspectRatio(avPlayer: media.AVPlayer): number {
    // AVPlayer 提供 width/height 或 aspectRatio 属性
    try {
      const width = (avPlayer as any).width ?? 1920;
      const height = (avPlayer as any).height ?? 1080;
      return height > 0 ? width / height : 16 / 9;
    } catch (_) {
      return 16 / 9;
    }
  }

  /** 播放 */
  play(): void {
    for (const entry of this.players.values()) {
      if (entry.avPlayer) {
        entry.avPlayer.play();
      }
    }
  }

  /** 暂停 */
  pause(): void {
    for (const entry of this.players.values()) {
      if (entry.avPlayer) {
        entry.avPlayer.pause();
      }
    }
  }

  /** 跳转（毫秒） */
  seekTo(milliseconds: number): void {
    for (const entry of this.players.values()) {
      if (entry.avPlayer) {
        entry.avPlayer.seek(milliseconds);
      }
    }
  }

  /** 释放当前播放器 */
  dispose(): void {
    for (const [id, entry] of this.players.entries()) {
      if (entry.avPlayer) {
        entry.avPlayer.release();
      }
      entry.textureEntry.release();
      this.players.delete(id);
      break; // 一次只释放一个
    }
  }

  /** 释放全部播放器 */
  disposeAll(): void {
    for (const [id, entry] of this.players.entries()) {
      if (entry.avPlayer) {
        entry.avPlayer.release();
      }
      entry.textureEntry.release();
      this.players.delete(id);
    }
  }
}