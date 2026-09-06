/// Shared layout measurements for the responsive application shell.
class AppBreakpoints {
  AppBreakpoints._();

  /// Width reserved for the landscape navigation column.
  static const double navigationWidth = 224;

  /// Maximum readable width for the main content column.
  static const double contentMaxWidth = 960;

  /// Whether the available area should use the horizontal layout.
  ///
  /// A square viewport remains in the portrait layout to avoid switching while
  /// the device is between orientation states.
  static bool isLandscape(double width, double height) => width > height;
}
