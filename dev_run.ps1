# dev_run.ps1 - 解决中文路径乱码与 CMake 缓存冲突的调试运行脚本
$tempPath = "c:\liceal\code\unclutter_temp_build"
$currentPath = "c:\liceal\code\unClutter复刻"

# 1. 首先清理主工作区的冲突构建缓存
Write-Host "正在清理本地缓存..." -ForegroundColor Cyan
$env:PUB_HOSTED_URL='https://pub.flutter-io.cn'
$env:FLUTTER_STORAGE_BASE_URL='https://storage.flutter-io.cn'
flutter clean

# 2. 准备纯英文编译目录
Write-Host "正在创建临时调试目录..." -ForegroundColor Cyan
Remove-Item -Recurse -Force $tempPath -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force $tempPath | Out-Null

# 3. 复制代码文件
Write-Host "正在同步代码..." -ForegroundColor Cyan
Copy-Item -Path "$currentPath\lib", "$currentPath\windows", "$currentPath\pubspec.yaml", "$currentPath\analysis_options.yaml" -Destination $tempPath -Recurse -Force

# 4. 进入临时目录并以调试模式运行
Write-Host "开始在英文路径运行调试..." -ForegroundColor Cyan
cd $tempPath

# 启动运行 (支持 r 热重载 / R 热重启 / q 退出)
flutter run -d windows

# 5. 用户退出运行后，把最新的构建缓存同步回来，方便后续打包或查看
Write-Host "同步构建数据并清理临时目录..." -ForegroundColor Cyan
cd $currentPath
if (Test-Path "$tempPath\build") {
    Copy-Item -Path "$tempPath\build" -Destination . -Recurse -Force
}
Remove-Item -Recurse -Force $tempPath -ErrorAction SilentlyContinue

Write-Host "调试结束，临时目录已安全清理！" -ForegroundColor Green
