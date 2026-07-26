# Flutter Web 发布性能建议

本项目首屏依赖 `main.dart.js` 与 CanvasKit WASM。生产发布时，除了代码侧避免阻塞首屏，还需要静态资源服务器正确压缩与缓存。

## 不发布的构建调试产物

以下文件不应进入生产静态目录，除非明确用于调试：

- `**/*.map`
- `canvaskit/**/*.symbols`
- `**/*.zip`

这些文件不会提升用户运行体验，可能显著增加上传、同步、CDN 预热和错误配置下的下载成本。

## 推荐缓存策略

- `index.html`：短缓存或 `no-cache`，保证新版本入口及时生效。
- `flutter_bootstrap.js`、`main.dart.js`：随版本发布；如果文件名不带 hash，应使用短缓存或配合版本化目录。
- `canvaskit/*`、`assets/*`、`icons/*`、`*.wasm`：长缓存，并在版本化发布目录或变更时刷新 CDN。
- `manifest.json`、`version.json`：短缓存或重新验证。

## 推荐压缩

服务器/CDN 应对以下类型启用 Brotli 或 gzip：

- `.js`
- `.wasm`
- `.json`
- `.css`
- `.svg`
- `.html`

CanvasKit WASM 和 `main.dart.js` 是首屏下载体积的主要来源，压缩配置对首次进入速度影响很大。

## 构建后检查

发布前建议检查产物体积：

```bash
flutter build web --release --no-source-maps
find build/web \( -name '*.map' -o -name '*.symbols' -o -name '*.zip' \) -print
du -ah build/web | sort -h | tail -40
```

如果仍需发布到纯静态服务器，先复制到临时发布目录，再删除调试产物，避免误删本地构建缓存。
