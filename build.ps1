$env:CC="$PWD\buildtool\aarch64-unknown-linux-ohos-clang.cmd"
$env:AR="$PWD\buildtool\llvm-ar.cmd"
$env:RUSTFLAGS="--cfg reqwest_unstable"
dart run build_runner build --delete-conflicting-outputs
flutter build hap --target-platform ohos-arm64 --release