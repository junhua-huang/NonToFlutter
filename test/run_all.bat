@echo off
chcp 65001 >nul
cd /d D:\FlutterProject\facebook_clone

echo ========================================
echo Running all tests...
echo ========================================

REM 运行所有单元测试
echo.
echo [1/3] Running unit tests...
flutter test test/unit/ --reporter expanded > test_report_unit.txt 2>&1

REM 运行所有 Widget 测试
echo.
echo [2/3] Running widget tests...
flutter test test/widget/ --reporter expanded > test_report_widget.txt 2>&1

REM 运行集成测试
echo.
echo [3/3] Running integration tests...
flutter test test/integration/ --reporter expanded > test_report_integration.txt 2>&1

REM 合并报告
echo.
echo ========================================
echo Merging reports...
echo ========================================
echo # Test Report - %date% %time% > test_report.txt
echo. >> test_report.txt
echo ## Unit Tests >> test_report.txt
type test_report_unit.txt >> test_report.txt
echo. >> test_report.txt
echo ## Widget Tests >> test_report.txt
type test_report_widget.txt >> test_report.txt
echo. >> test_report.txt
echo ## Integration Tests >> test_report.txt
type test_report_integration.txt >> test_report.txt

echo.
echo ========================================
echo All tests completed!
echo Report saved to test_report.txt
echo ========================================
pause
