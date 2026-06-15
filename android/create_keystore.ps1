# 创建 Android 签名密钥库脚本

Write-Host "正在创建密钥库文件..." -ForegroundColor Green

$keytoolPath = "keytool"
$keystoreFile = "nonto-release-key.jks"
$alias = "nonto"
$storePass = "nonto_password"
$keyPass = "nonto_password"
$dname = "CN=FacebookClone, OU=Development, O=FacebookClone, L=Beijing, S=Beijing, C=CN"

try {
    & $keytoolPath -genkey -v `
        -keystore $keystoreFile `
        -keyalg RSA `
        -keysize 2048 `
        -validity 10000 `
        -alias $alias `
        -storepass $storePass `
        -keypass $keyPass `
        -dname $dname
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "`n密钥库创建成功！" -ForegroundColor Green
        Write-Host "文件位置: $PWD\$keystoreFile" -ForegroundColor Cyan
        Write-Host "`n现在可以运行以下命令构建 APK:" -ForegroundColor Yellow
        Write-Host "cd .." -ForegroundColor Gray
        Write-Host "flutter build apk --release" -ForegroundColor Gray
    } else {
        Write-Host "`n密钥库创建失败！" -ForegroundColor Red
    }
} catch {
    Write-Host "`n发生错误: $_" -ForegroundColor Red
    Write-Host "请确保已安装 Java JDK 并且 keytool 在系统路径中" -ForegroundColor Yellow
}
