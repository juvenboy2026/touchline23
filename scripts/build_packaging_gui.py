#!/usr/bin/env python3
"""Build only the small packaging GUI with the installed Apple Swift compiler.

Uses a new output root, external module caches and no SwiftPM build service.
No game input, game compiler, signer or packaging recipe is executed.
"""
import argparse
from pathlib import Path
import plistlib
import subprocess
import sys


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True, help='new GUI build directory')
    parser.add_argument('--test', action='store_true', help='also compile/run the Swift model tests')
    parser.add_argument('--python', type=Path, default=Path(sys.executable),
                        help='redistributor only: relocatable CPython with build dependencies')
    parser.add_argument('--python-site', action='append', type=Path, default=[],
                        help='redistributor only: additional dependency site-packages')
    args = parser.parse_args()
    root = args.output.expanduser().resolve()
    if root.exists():
        parser.error('output already exists; choose a new GUI build directory')
    repo = Path(__file__).resolve().parents[1]
    root.mkdir(parents=True)
    modules = root / 'modules'; modules.mkdir()
    app = root / 'Touchline23Packaging.app'
    sys.path.insert(0, str(repo))
    from tools.packaging_gui.distribution import bundle
    bundle(repo, app / 'Contents/Resources', args.python, root, args.python_site)
    frameworks = app / 'Contents/Frameworks'; frameworks.mkdir(parents=True)
    binaries = app / 'Contents/MacOS'; binaries.mkdir()
    library = frameworks / 'libPackagingModel.dylib'
    common = ['xcrun', 'swiftc', '-swift-version', '5', '-module-cache-path', str(root / 'module-cache')]

    def run(argv):
        subprocess.run([str(a) for a in argv], check=True, cwd=repo)

    run(common + ['-parse-as-library', '-enable-testing', '-emit-module', '-emit-library',
                  '-module-name', 'PackagingModel', *sorted((repo / 'gui/Sources/PackagingModel').glob('*.swift')),
                  '-o', library, '-emit-module-path', modules / 'PackagingModel.swiftmodule',
                  '-Xlinker', '-install_name', '-Xlinker', '@rpath/libPackagingModel.dylib'])
    run(common + ['-parse-as-library', '-I', modules, '-L', frameworks, '-lPackagingModel',
                  '-Xlinker', '-rpath', '-Xlinker', '@executable_path/../Frameworks',
                  *sorted((repo / 'gui/Sources/NXPackagingGUI').glob('*.swift')),
                  '-o', binaries / 'Touchline23Packaging'])
    with (app / 'Contents/Info.plist').open('wb') as stream:
        plistlib.dump(dict(CFBundleExecutable='Touchline23Packaging', CFBundleName='Touchline 23 Packaging',
                          CFBundleIdentifier='com.ohxiaoguang.touchline23.packaging', CFBundlePackageType='APPL',
                          CFBundleVersion='7', CFBundleShortVersionString='0.7.0',
                          CFBundleDevelopmentRegion='en', CFBundleLocalizations=['en', 'zh-Hans'],
                          LSMinimumSystemVersion='26.0', NSHighResolutionCapable=True,
                          NSRemovableVolumesUsageDescription='Inspect selected game files and build paths.'), stream)
    if args.test:
        test = root / 'PackagingModelTests'
        developer = Path(subprocess.run(['xcode-select', '-p'], check=True,
                                        capture_output=True, text=True).stdout.strip())
        test_frameworks = developer / 'Platforms/MacOSX.platform/Developer/Library/Frameworks'
        test_libraries = developer / 'Platforms/MacOSX.platform/Developer/usr/lib'
        run(common + ['-I', modules, '-L', frameworks, '-lPackagingModel', '-F', test_frameworks,
                      '-I', test_libraries, '-L', test_libraries,
                      '-Xlinker', '-rpath', '-Xlinker', test_libraries,
                      '-Xlinker', '-rpath', '-Xlinker', test_frameworks,
                      '-Xlinker', '-rpath', '-Xlinker', str(frameworks),
                      *sorted((repo / 'gui/Tests/PackagingModelTests').glob('*.swift')),
                      repo / 'gui/TestSupport/main.swift', '-o', test])
        run([test])
    run(['codesign', '--force', '--deep', '--sign', '-', app])
    print('Standalone GUI App: ' + str(app))
    print('Follows the system language by default; choose System / English / 简体中文. '
          'Builds require fresh preflight and confirmation.')


if __name__ == '__main__':
    main()
