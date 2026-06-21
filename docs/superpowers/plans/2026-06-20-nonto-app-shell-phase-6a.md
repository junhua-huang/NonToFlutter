# Nonto App Shell Phase 6A Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Modernize `HomeScreen` app shell structure and clean targeted analyzer noise while preserving current tab behavior, unread badges, drawer routes, and performance.

**Architecture:** Keep the existing four-tab `IndexedStack` and Riverpod-backed `currentTabIndexProvider`. Refactor only the shell chrome into private helpers so the main `build` method is easier to read, source-regression-testable, and analyzer-clean. Avoid new data loading, route index changes, or drawer destination changes.

**Tech Stack:** Flutter, Dart, Riverpod, `BottomNavigationBar`, `IndexedStack`, SVG nav icons, source-level Flutter regression tests.

---

## File Structure

- Create: `test/nonto_app_shell_phase6a_regression_test.dart`
  - Source regression tests for shell structure, helper extraction, labels, compose route, badge behavior, and analyzer cleanup.
- Modify: `lib/screens/home/home_screen.dart`
  - Add Nonto-owned shell doc comment.
  - Remove unused imports/local/helpers.
  - Extract compose FAB and bottom navigation helpers.
  - Preserve `IndexedStack`, four tabs, drawer routes, and provider-derived unread badge.
- Do not commit in this task unless the user explicitly asks.

---

### Task 1: Add RED source regression coverage

**Files:**
- Create: `test/nonto_app_shell_phase6a_regression_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/nonto_app_shell_phase6a_regression_test.dart` with this content:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final projectRoot = Directory.current.path;
  String read(String relativePath) =>
      File('$projectRoot/$relativePath').readAsStringSync();

  group('Phase 6A app shell source regressions', () {
    test('home shell uses Nonto-owned wording and keeps tab retention', () {
      final source = read('lib/screens/home/home_screen.dart');

      expect(source, contains('Nonto 主框架页'));
      expect(source, contains('首页、发现、消息与我的'));
      expect(source, contains('IndexedStack'));
      expect(source, contains('FeedTab()'));
      expect(source, contains('SearchTab()'));
      expect(source, contains('MessagesTab()'));
      expect(source, contains('ProfileTab()'));
    });

    test('bottom navigation chrome is extracted and keeps stable labels', () {
      final source = read('lib/screens/home/home_screen.dart');

      expect(source, contains('Widget _buildBottomNavigationBar'));
      expect(source, contains('List<BottomNavigationBarItem> _buildNavigationItems'));
      expect(source, contains('BottomNavigationBarItem _buildNavItem'));
      expect(source, contains('Widget _buildNavIcon'));
      expect(source, contains("label: '首页'"));
      expect(source, contains("label: '发现'"));
      expect(source, contains("label: '消息'"));
      expect(source, contains("label: '我的'"));
    });

    test('compose action remains feed-only and opens create post screen', () {
      final source = read('lib/screens/home/home_screen.dart');

      expect(source, contains('Widget? _buildComposeButton(bool barVisible, int currentIndex)'));
      expect(source, contains('if (currentIndex != 0) return null;'));
      expect(source, contains('const CreatePostScreen()'));
      expect(source, contains('FloatingActionButton'));
    });

    test('unread badge remains provider derived and capped', () {
      final source = read('lib/screens/home/home_screen.dart');

      expect(source, contains('unreadNotificationsCountProvider'));
      expect(source, contains('unreadMessagesCountProvider'));
      expect(source, contains('String _formatBadgeCount(int count)'));
      expect(source, contains("count > 99 ? '99+' : '$count'"));
      expect(source, contains('Badge('));
    });

    test('known HomeScreen analyzer noise is removed', () {
      final source = read('lib/screens/home/home_screen.dart');

      expect(source, isNot(contains("import 'package:nonto/config/app_config.dart';")));
      expect(source, isNot(contains("import 'package:nonto/providers/chat_notifiers.dart';")));
      expect(source, isNot(contains('final authState = ref.watch(authProvider);')));
      expect(source, isNot(contains('Widget _buildBadgeIcon')));
      expect(source, isNot(contains('Widget _buildAvatar')));
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
cd /d/FlutterProject/nonto && flutter test test/nonto_app_shell_phase6a_regression_test.dart
```

Expected: FAIL because `HomeScreen` does not yet have the Nonto shell wording, extracted helper methods, labels, compose helper, or analyzer cleanup.

---

### Task 2: Refactor HomeScreen shell chrome

**Files:**
- Modify: `lib/screens/home/home_screen.dart`
- Test: `test/nonto_app_shell_phase6a_regression_test.dart`

- [ ] **Step 1: Remove unused imports**

Delete these imports from `lib/screens/home/home_screen.dart`:

```dart
import 'package:nonto/config/app_config.dart';
import 'package:nonto/providers/chat_notifiers.dart';
```

- [ ] **Step 2: Add Nonto-owned screen documentation**

Add this comment immediately above `class HomeScreen extends ConsumerStatefulWidget`:

```dart
/// Nonto 主框架页：承载首页、发现、消息与我的四个核心入口。
///
/// 保留 IndexedStack 以维持各 Tab 状态，底部导航和发布入口只做轻量重组。
```

- [ ] **Step 3: Simplify `build` method shell**

In `build`, remove the unused local:

```dart
final authState = ref.watch(authProvider);
```

Then keep the provider-derived values and replace the current inline FAB and bottom navigation sections with helper calls:

```dart
  @override
  Widget build(BuildContext context) {
    final barVisible = ref.watch(barVisibleProvider);
    final totalBadge = (ref.watch(unreadNotificationsCountProvider) +
            ref.watch(unreadMessagesCountProvider))
        .toInt();
    final currentIndex = ref.watch(currentTabIndexProvider);

    return Scaffold(
      extendBody: true,
      body: IndexedStack(
        index: currentIndex,
        children: _tabs,
      ),
      drawer: _buildDrawer(context),
      floatingActionButton: _buildComposeButton(barVisible, currentIndex),
      bottomNavigationBar: _buildBottomNavigationBar(
        barVisible: barVisible,
        currentIndex: currentIndex,
        totalBadge: totalBadge,
      ),
    );
  }
```

- [ ] **Step 4: Add compose helper**

Add this method after `build` and before `_buildDrawer`:

```dart
  Widget? _buildComposeButton(bool barVisible, int currentIndex) {
    if (currentIndex != 0) return null;

    return AnimatedSlide(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      offset: barVisible ? Offset.zero : const Offset(0, 2),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 250),
        opacity: barVisible ? 1.0 : 0.0,
        child: FloatingActionButton(
          onPressed: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const CreatePostScreen()),
            );
          },
          backgroundColor: AppColors.primary,
          elevation: 4,
          shape: const CircleBorder(),
          child: const Icon(Icons.edit, color: Colors.white, size: 26),
        ),
      ),
    );
  }
```

- [ ] **Step 5: Add bottom navigation helper**

Add this method after `_buildComposeButton`:

```dart
  Widget _buildBottomNavigationBar({
    required bool barVisible,
    required int currentIndex,
    required int totalBadge,
  }) {
    return AnimatedSlide(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      offset: barVisible ? Offset.zero : const Offset(0, 1),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 250),
        opacity: barVisible ? 1.0 : 0.0,
        child: Theme(
          data: Theme.of(context).copyWith(
            splashColor: Colors.transparent,
            highlightColor: Colors.transparent,
          ),
          child: BottomNavigationBar(
            currentIndex: currentIndex,
            onTap: (index) {
              ref.read(currentTabIndexProvider.notifier).state = index;
            },
            type: BottomNavigationBarType.fixed,
            showSelectedLabels: true,
            showUnselectedLabels: true,
            selectedFontSize: 0,
            unselectedFontSize: 0,
            items: _buildNavigationItems(
              currentIndex: currentIndex,
              totalBadge: totalBadge,
            ),
          ),
        ),
      ),
    );
  }
```

- [ ] **Step 6: Add navigation item helpers**

Add these methods after `_buildBottomNavigationBar`:

```dart
  List<BottomNavigationBarItem> _buildNavigationItems({
    required int currentIndex,
    required int totalBadge,
  }) {
    return [
      _buildNavItem(
        label: '首页',
        asset: 'assets/icons/未选中首页.svg',
        activeAsset: 'assets/icons/选中首页.svg',
        selected: currentIndex == 0,
      ),
      _buildNavItem(
        label: '发现',
        asset: 'assets/icons/未选中搜索.svg',
        activeAsset: 'assets/icons/选中搜索.svg',
        selected: currentIndex == 1,
      ),
      _buildNavItem(
        label: '消息',
        asset: 'assets/icons/未选中消息.svg',
        activeAsset: 'assets/icons/选中消息.svg',
        selected: currentIndex == 2,
        badgeCount: totalBadge,
      ),
      _buildNavItem(
        label: '我的',
        asset: 'assets/icons/未选中个人.svg',
        activeAsset: 'assets/icons/选中个人.svg',
        selected: currentIndex == 3,
      ),
    ];
  }

  BottomNavigationBarItem _buildNavItem({
    required String label,
    required String asset,
    required String activeAsset,
    required bool selected,
    int badgeCount = 0,
  }) {
    return BottomNavigationBarItem(
      icon: _buildNavIcon(
        asset: asset,
        selected: selected,
        badgeCount: badgeCount,
      ),
      activeIcon: _buildNavIcon(
        asset: activeAsset,
        selected: selected,
        badgeCount: badgeCount,
      ),
      label: label,
    );
  }

  Widget _buildNavIcon({
    required String asset,
    required bool selected,
    int badgeCount = 0,
  }) {
    final icon = _NavIcon(
      asset: asset,
      isSelected: selected,
      size: 26,
    );

    if (badgeCount <= 0) return icon;

    return Badge(
      label: Text(_formatBadgeCount(badgeCount)),
      child: icon,
    );
  }

  String _formatBadgeCount(int count) => count > 99 ? '99+' : '$count';
```

- [ ] **Step 7: Remove obsolete unused helpers**

Delete these methods from `_HomeScreenState`:

```dart
  Widget _buildBadgeIcon({
    required IconData icon,
    required IconData activeIcon,
    required int count,
    bool isActive = false,
  }) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(icon, size: 26),
        if (count > 0)
          Positioned(
            right: -6,
            top: -2,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: const BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
              ),
              constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
              child: Center(
                child: Text(
                  count > 99 ? '99+' : '$count',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildAvatar() {
    final authState = ref.watch(authProvider);
    // 复用 ImageUtils.buildAvatar：走 CachedNetworkImage + memCacheWidth，
    // 之前用裸 Image.network 每次重建都重新下载，是「卡」的一个来源。
    return ImageUtils.buildAvatar(authState.user, radius: 16);
  }
```

- [ ] **Step 8: Format changed files**

Run:

```bash
cd /d/FlutterProject/nonto && dart format lib/screens/home/home_screen.dart test/nonto_app_shell_phase6a_regression_test.dart
```

Expected: formatter completes and reports the two formatted files or no changes.

- [ ] **Step 9: Run Phase 6A regression test**

Run:

```bash
cd /d/FlutterProject/nonto && flutter test test/nonto_app_shell_phase6a_regression_test.dart
```

Expected: PASS.

- [ ] **Step 10: Run targeted analyzer**

Run:

```bash
cd /d/FlutterProject/nonto && dart analyze lib/screens/home/home_screen.dart test/nonto_app_shell_phase6a_regression_test.dart
```

Expected: `No issues found!`.

---

### Task 3: Run adjacent and full verification

**Files:**
- Verify: `lib/screens/home/home_screen.dart`
- Verify: `test/nonto_app_shell_phase6a_regression_test.dart`

- [ ] **Step 1: Run adjacent shell/performance tests**

Run:

```bash
cd /d/FlutterProject/nonto && flutter test test/page_performance_regression_test.dart test/nonto_ui_phase1_regression_test.dart test/nonto_app_shell_phase6a_regression_test.dart
```

Expected: all selected tests pass.

- [ ] **Step 2: Run full Flutter test suite**

Run:

```bash
cd /d/FlutterProject/nonto && flutter test --dart-define=API_BASE_URL=https://www.nonto.online/api --dart-define=WS_URL=wss://www.nonto.online/ws
```

Expected: full suite passes. Previous baseline after Phase 5B was `+86`, `All tests passed!`; the total should increase by the new Phase 6A tests.

- [ ] **Step 3: Run full analyzer and record baseline honestly**

Run:

```bash
cd /d/FlutterProject/nonto && flutter analyze
```

Expected: full analyzer may still fail from historical project-wide issues. Current baseline before Phase 6A is `72 issues found`; this slice should remove the six `home_screen.dart` issues and should not add new touched-file issues.

---

## Self-Review

- Spec coverage:
  - Nonto-owned shell wording: Task 2 Step 2 and Task 1 first test.
  - Preserve `IndexedStack` and four tabs: Task 1 first test and Task 2 Step 3.
  - Extract bottom navigation helpers: Task 1 second test and Task 2 Steps 5-6.
  - Stable tab labels: Task 1 second test and Task 2 Step 6.
  - Feed-only compose: Task 1 third test and Task 2 Step 4.
  - Provider-derived badge and `99+` cap: Task 1 fourth test and Task 2 Step 6.
  - Analyzer cleanup: Task 1 fifth test and Task 2 Steps 1, 3, and 7.
- Placeholder scan: no TBD/fill-in-later steps; commands and code snippets are explicit.
- Type consistency: helper signatures match the tests and implementation snippets: `_buildBottomNavigationBar`, `_buildNavigationItems`, `_buildNavItem`, `_buildNavIcon`, `_formatBadgeCount`, `_buildComposeButton`.
- User constraints: no commits, no migrations, no route index changes, no extra data loading, and performance-preserving `IndexedStack` remains intact.
