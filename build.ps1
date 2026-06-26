$env:CC="$PWD\buildtool\aarch64-unknown-linux-ohos-clang.cmd"
$env:CXX="$PWD\buildtool\aarch64-unknown-linux-ohos-clang++.cmd"
$env:AR="$PWD\buildtool\llvm-ar.cmd"
$env:CMAKE="$PWD\buildtool\cmake.cmd"
$env:RUSTFLAGS="--cfg reqwest_unstable"

$WORK_DIR="$PWD"

# hack to shorten path, otherwise path exceeds CMAKE_OBJECT_PATH_MAX (250)
cmd /c "mklink /d d:\r\ $PWD\plugins\rhttp\rhttp"

cd d:\r\
flutter_rust_bridge_codegen generate
dart run build_runner build
cd $WORK_DIR

dart run build_runner build
flutter build hap --target-platform ohos-arm64 --release --dart-define=ENABLE_FLEX_OVERFLOW=false

cmd /c "rmdir d:\r\"