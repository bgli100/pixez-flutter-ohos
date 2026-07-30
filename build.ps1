# Save original env var values so we can restore them on exit
$_orig_RUSTFLAGS = $env:RUSTFLAGS
$_orig_CC        = $env:CC
$_orig_CXX       = $env:CXX
$_orig_AR        = $env:AR
$_orig_CMAKE     = $env:CMAKE
$_orig_TARGET    = $env:TARGET

try {
    $env:RUSTFLAGS="--cfg reqwest_unstable"

    $WORK_DIR="$PWD"

    # Path to the OHOS fork of flutter_rust_bridge.
    # Change this if your clone is at a different location.
    $FRB_OHOS = "D:\dev\flutter_rust_bridge_ohos"

    # hack to shorten path, otherwise path exceeds CMAKE_OBJECT_PATH_MAX (250)
    cmd /c "mklink /d d:\r\ $PWD\plugins\rhttp\rhttp"

    cd d:\r\
    & "$FRB_OHOS\target\release\flutter_rust_bridge_codegen.exe" generate

    # Auto-upgrade may revert path deps to registry/git versions.
    # Restore OHOS fork path dependencies in both pubspec.yaml and Cargo.toml.
    $pubspec = "$PWD\pubspec.yaml"
    $cargo = "$PWD\rust\Cargo.toml"

    # Compute the relative path from Cargo.toml directory to FRB frb_rust.
    # Resolve-Path follows the symlink to get the real directory.
    $cargoDir = (Resolve-Path "$PWD\rust").Path
    Push-Location $cargoDir
    $cargoRelPath = (Resolve-Path -Relative "$FRB_OHOS\frb_rust").Replace('\', '/')
    Pop-Location

    (Get-Content $pubspec -Raw) -replace '(?s)flutter_rust_bridge:\s*\n\s*git:.*?ref:\s*\S+',
        "flutter_rust_bridge:`n    path: $FRB_OHOS\frb_dart" |
        Set-Content $pubspec -NoNewline
    (Get-Content $cargo -Raw) -replace 'flutter_rust_bridge\s*=\s*\{[^}]*version\s*=\s*"[^"]*"[^}]*\}',
        "flutter_rust_bridge = { path = ""$cargoRelPath"", features = [""chrono""] }" |
        Set-Content $cargo -NoNewline
    flutter pub get

    dart run build_runner build
    cd $WORK_DIR

    dart run build_runner build

    # Set OHOS cross-compilation env vars ONLY for the actual hap build.
    # The codegen steps above build Rust for the HOST (x86_64-pc-windows-msvc)
    # and must use the host MSVC compiler, not the OHOS cross-compiler.
    $env:CC="$PWD\buildtool\aarch64-unknown-linux-ohos-clang.cmd"
    $env:CXX="$PWD\buildtool\aarch64-unknown-linux-ohos-clang++.cmd"
    $env:AR="$PWD\buildtool\llvm-ar.cmd"
    $env:CMAKE="$PWD\buildtool\cmake.cmd"
    $env:TARGET="aarch64-unknown-linux-ohos"
    flutter build hap --target-platform ohos-arm64 --release --dart-define=ENABLE_FLEX_OVERFLOW=false

    cmd /c "rmdir d:\r\"
} finally {
    # Restore original env vars so nothing leaks to the parent shell
    $env:RUSTFLAGS = $_orig_RUSTFLAGS
    $env:CC        = $_orig_CC
    $env:CXX       = $_orig_CXX
    $env:AR        = $_orig_AR
    $env:CMAKE     = $_orig_CMAKE
    $env:TARGET    = $_orig_TARGET
}