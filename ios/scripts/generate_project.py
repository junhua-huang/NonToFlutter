#!/usr/bin/env python3
"""Generate the Xcode project deterministically (Python 3)."""
from pathlib import Path
import hashlib
import json
import io
import zipfile

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / 'Nonto.xcodeproj'
objects = {}

def ident(name):
    return hashlib.sha1(name.encode()).hexdigest()[:24].upper()

def quote(value):
    return json.dumps(str(value), ensure_ascii=False)

def add(name, value):
    key = ident(name)
    objects[key] = value
    return key

def ref(path, filetype):
    return add('ref:' + path, f'{{isa = PBXFileReference; lastKnownFileType = {filetype}; path = {quote(path)}; sourceTree = "<group>"; }}')

def build(path, reference):
    return add('build:' + path, f'{{isa = PBXBuildFile; fileRef = {reference}; }}')

def array(values):
    return '(' + ', '.join(values) + (',' if values else '') + ')'

def group(name, children):
    return add('group:' + name, f'{{isa = PBXGroup; name = {quote(name)}; children = {array(children)}; sourceTree = "<group>"; }}')

def phase(name, kind, files):
    return add('phase:' + name, f'{{isa = {kind}; buildActionMask = 2147483647; files = {array(files)}; runOnlyForDeploymentPostprocessing = 0; }}')

def configs(name, settings):
    ids = []
    for mode in ['Debug', 'Release']:
        values = dict(settings)
        if name == 'app':
            values['APNS_ENVIRONMENT'] = 'development' if mode == 'Debug' else 'production'
        values.update({'SWIFT_OPTIMIZATION_LEVEL': '-Onone' if mode == 'Debug' else '-O',
                       'DEBUG_INFORMATION_FORMAT': 'dwarf' if mode == 'Debug' else 'dwarf-with-dsym'})
        if mode == 'Debug':
            values.update({'SWIFT_ACTIVE_COMPILATION_CONDITIONS': 'DEBUG', 'ENABLE_TESTABILITY': 'YES', 'GCC_PREPROCESSOR_DEFINITIONS': 'DEBUG=1 $(inherited)'})
        fields = ' '.join(f'{key} = {quote(value)};' for key, value in sorted(values.items()))
        ids.append(add(f'config:{name}:{mode}', f'{{isa = XCBuildConfiguration; buildSettings = {{{fields}}}; name = {mode}; }}'))
    return add('configlist:' + name, f'{{isa = XCConfigurationList; buildConfigurations = {array(ids)}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release; }}')

sources = sorted(p.relative_to(ROOT).as_posix() for p in (ROOT / 'Nonto').rglob('*.swift'))
tests = sorted(p.relative_to(ROOT).as_posix() for p in (ROOT / 'Tests').rglob('*.swift'))
resources = ['Nonto/Resources/Assets.xcassets', 'Nonto/Resources/PrivacyInfo.xcprivacy', 'Nonto/Resources/privacy.txt', 'Nonto/Resources/terms.txt', 'Nonto/Resources/community.txt', 'Nonto/Resources/Compliance.json']
resources.append('Nonto/Resources/NotoEmoji')
source_refs = [ref(p, 'sourcecode.swift') for p in sources]
test_refs = [ref(p, 'sourcecode.swift') for p in tests]
resource_refs = [add('ref:noto-bundle', '{isa = PBXFileReference; lastKnownFileType = folder; path = NotoEmoji; sourceTree = DERIVED_FILE_DIR; }') if p.endswith('/NotoEmoji') else ref(p, 'folder.assetcatalog' if p.endswith('.xcassets') else ('text.plist.xml' if p.endswith('.xcprivacy') else 'text')) for p in resources]
lottie_package = add('package:lottie', '{isa = XCRemoteSwiftPackageReference; repositoryURL = "https://github.com/airbnb/lottie-spm.git"; requirement = {kind = exactVersion; version = 4.6.1; }; }')
lottie_product = add('package-product:lottie', f'{{isa = XCSwiftPackageProductDependency; package = {lottie_package}; productName = Lottie; }}')
lottie_framework = add('build:lottie', f'{{isa = PBXBuildFile; productRef = {lottie_product}; }}')
lottie_test_framework = add('build:tests:lottie', f'{{isa = PBXBuildFile; productRef = {lottie_product}; }}')
app_product = add('product:app', '{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = Nonto.app; sourceTree = BUILT_PRODUCTS_DIR; }')
test_product = add('product:tests', '{isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = NontoTests.xctest; sourceTree = BUILT_PRODUCTS_DIR; }')
main_group = group('Nonto', [group('Application', source_refs), group('Resources', resource_refs + [ref('Nonto/Resources/Info.plist', 'text.plist.xml'), ref('Nonto/Resources/Nonto.entitlements', 'text.plist.xml')]), group('Tests', test_refs), group('Products', [app_product, test_product])])
archive_script = 'if [ "$ACTION" = "install" ]; then\n  if [ "$NONTO_DISTRIBUTION_CHANNEL" = "testflight-internal" ] || [ "$NONTO_DISTRIBUTION_CHANNEL" = "app-store-upload" ]; then\n    echo "Draft/test upload only: outstanding release disclosures remain unresolved; not approved for submission."\n    /usr/bin/env python3 "$SRCROOT/scripts/check_compliance.py"\n  else\n    /usr/bin/env python3 "$SRCROOT/scripts/check_compliance.py" --release\n  fi\nfi'
archive_inputs = ['$(SRCROOT)/scripts/check_compliance.py'] + ['$(SRCROOT)/Nonto/Resources/' + name for name in ['Compliance.json', 'PrivacyInfo.xcprivacy', 'privacy.txt', 'terms.txt', 'community.txt']]
archive_check = add('phase:app:compliance', '{isa = PBXShellScriptBuildPhase; buildActionMask = 2147483647; files = (); inputPaths = ' + array([quote(p) for p in archive_inputs]) + '; outputPaths = (); name = "Check release disclosures"; runOnlyForDeploymentPostprocessing = 0; shellPath = /bin/sh; shellScript = ' + quote(archive_script) + '; alwaysOutOfDate = 1; }')
emoji_parts = sorted((ROOT / 'Nonto/Resources').glob('NotoEmoji.zip.[0-9][0-9][0-9]'))
if not emoji_parts:
    raise SystemExit('Missing offline Noto emoji archive parts')
emoji_inputs = [p.relative_to(ROOT).as_posix() for p in emoji_parts]
# Declare every extracted file so the build sandbox need not permit arbitrary
# writes below a directory that does not exist yet when the sandbox starts.
with zipfile.ZipFile(io.BytesIO(b''.join(p.read_bytes() for p in emoji_parts))) as emoji_archive:
    emoji_names = sorted(emoji_archive.namelist())
if any('/' in name or name in {'.', '..'} for name in emoji_names):
    raise SystemExit('Unexpected path in emoji archive')
PROJECT.mkdir(exist_ok=True)
(PROJECT / 'NotoEmojiOutputs.xcfilelist').write_text(''.join('$(DERIVED_FILE_DIR)/NotoEmoji/' + name + '\n' for name in emoji_names))
emoji_unpack_script = 'set -e\n/bin/cat ' + ' '.join('"$SRCROOT/' + p + '"' for p in emoji_inputs) + ' > "$DERIVED_FILE_DIR/NotoEmoji.zip"\n/bin/mkdir -p "$DERIVED_FILE_DIR/NotoEmoji"\n/usr/bin/unzip -q -o "$DERIVED_FILE_DIR/NotoEmoji.zip" -d "$DERIVED_FILE_DIR/NotoEmoji"'
emoji_unpack = add('phase:app:noto-resources', '{isa = PBXShellScriptBuildPhase; buildActionMask = 2147483647; files = (); inputPaths = ' + array([quote('$(SRCROOT)/' + p) for p in emoji_inputs]) + '; outputFileListPaths = ("$(SRCROOT)/Nonto.xcodeproj/NotoEmojiOutputs.xcfilelist",); outputPaths = ("$(DERIVED_FILE_DIR)/NotoEmoji.zip", "$(DERIVED_FILE_DIR)/NotoEmoji",); name = "Prepare offline Noto emoji"; runOnlyForDeploymentPostprocessing = 0; shellPath = /bin/sh; shellScript = ' + quote(emoji_unpack_script) + '; }')
app_phases = [archive_check, emoji_unpack, phase('app:sources', 'PBXSourcesBuildPhase', [build(p, r) for p, r in zip(sources, source_refs)]), phase('app:frameworks', 'PBXFrameworksBuildPhase', [lottie_framework]), phase('app:resources', 'PBXResourcesBuildPhase', [build(p, r) for p, r in zip(resources, resource_refs)])]
test_phases = [phase('tests:sources', 'PBXSourcesBuildPhase', [build(p, r) for p, r in zip(tests, test_refs)]), phase('tests:frameworks', 'PBXFrameworksBuildPhase', [lottie_test_framework]), phase('tests:resources', 'PBXResourcesBuildPhase', [])]
common = {'IPHONEOS_DEPLOYMENT_TARGET': '26.0', 'SDKROOT': 'iphoneos', 'SWIFT_VERSION': '5.0', 'CLANG_ENABLE_MODULES': 'YES', 'TARGETED_DEVICE_FAMILY': '1,2', 'CODE_SIGN_STYLE': 'Automatic', 'SUPPORTED_PLATFORMS': 'iphoneos iphonesimulator', 'SUPPORTS_MACCATALYST': 'NO'}
app_config = configs('app', common | {'NONTO_DISTRIBUTION_CHANNEL': 'app-store', 'CODE_SIGN_ENTITLEMENTS': 'Nonto/Resources/Nonto.entitlements', 'PRODUCT_NAME': 'Nonto', 'PRODUCT_BUNDLE_IDENTIFIER': 'online.nonto.native', 'INFOPLIST_FILE': 'Nonto/Resources/Info.plist', 'ASSETCATALOG_COMPILER_APPICON_NAME': 'AppIcon', 'MARKETING_VERSION': '1.0.0', 'CURRENT_PROJECT_VERSION': '1', 'LD_RUNPATH_SEARCH_PATHS': '$(inherited) @executable_path/Frameworks', 'ENABLE_USER_SCRIPT_SANDBOXING': 'YES'})
test_config = configs('tests', common | {'PRODUCT_NAME': 'NontoTests', 'PRODUCT_BUNDLE_IDENTIFIER': 'online.nonto.native.tests', 'GENERATE_INFOPLIST_FILE': 'YES', 'TEST_HOST': '$(BUILT_PRODUCTS_DIR)/Nonto.app/Nonto', 'BUNDLE_LOADER': '$(TEST_HOST)', 'TEST_TARGET_NAME': 'Nonto', 'LD_RUNPATH_SEARCH_PATHS': '$(inherited) @executable_path/Frameworks @loader_path/Frameworks'})
app_id = ident('target:app')
project_id = ident('project')
proxy = add('proxy:app', f'{{isa = PBXContainerItemProxy; containerPortal = {project_id}; proxyType = 1; remoteGlobalIDString = {app_id}; remoteInfo = Nonto; }}')
dependency = add('dependency:app', f'{{isa = PBXTargetDependency; target = {app_id}; targetProxy = {proxy}; }}')
add('target:app', f'{{isa = PBXNativeTarget; buildConfigurationList = {app_config}; buildPhases = {array(app_phases)}; buildRules = (); dependencies = (); packageProductDependencies = ({lottie_product},); name = Nonto; productName = Nonto; productReference = {app_product}; productType = "com.apple.product-type.application"; }}')
test_id = add('target:tests', f'{{isa = PBXNativeTarget; buildConfigurationList = {test_config}; buildPhases = {array(test_phases)}; buildRules = (); dependencies = ({dependency},); packageProductDependencies = ({lottie_product},); name = NontoTests; productName = NontoTests; productReference = {test_product}; productType = "com.apple.product-type.bundle.unit-test"; }}')
project_config = configs('project', {'CLANG_ENABLE_OBJC_ARC': 'YES', 'CLANG_WARN_DOCUMENTATION_COMMENTS': 'YES', 'GCC_C_LANGUAGE_STANDARD': 'gnu17', 'SWIFT_STRICT_CONCURRENCY': 'targeted'})
add('project', f'{{isa = PBXProject; attributes = {{BuildIndependentTargetsInParallel = YES; LastUpgradeCheck = 1600; TargetAttributes = {{{app_id} = {{CreatedOnToolsVersion = 16.0; SystemCapabilities = {{com.apple.Push = {{enabled = 1; }}; }}; }}; {test_id} = {{CreatedOnToolsVersion = 16.0; TestTargetID = {app_id}; }}; }}; }}; buildConfigurationList = {project_config}; compatibilityVersion = "Xcode 14.0"; developmentRegion = zh-Hans; hasScannedForEncodings = 0; knownRegions = ("zh-Hans", en, Base); mainGroup = {main_group}; packageReferences = ({lottie_package},); productRefGroup = {ident("group:Products")}; projectDirPath = ""; projectRoot = ""; targets = ({app_id}, {test_id},); }}')
PROJECT.mkdir(exist_ok=True)
(PROJECT / 'project.pbxproj').write_text('// !$*UTF8*$!\n{\narchiveVersion = 1;\nclasses = {};\nobjectVersion = 56;\nobjects = {\n' + '\n'.join(f'{key} = {value};' for key, value in sorted(objects.items())) + f'\n}};\nrootObject = {project_id};\n}}\n')
scheme_dir = PROJECT / 'xcshareddata/xcschemes'
scheme_dir.mkdir(parents=True, exist_ok=True)
def buildable(target, product, name):
    return f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="{product}" BlueprintName="{name}" ReferencedContainer="container:Nonto.xcodeproj"/>'
app_buildable = buildable(app_id, 'Nonto.app', 'Nonto')
test_buildable = buildable(test_id, 'NontoTests.xctest', 'NontoTests')
(scheme_dir / 'Nonto.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries>
<BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{app_buildable}</BuildActionEntry>
</BuildActionEntries></BuildAction>
<TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES" codeCoverageEnabled="YES"><Testables><TestableReference skipped="NO">{test_buildable}</TestableReference></Testables></TestAction>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{app_buildable}</BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{app_buildable}</BuildableProductRunnable></ProfileAction>
<AnalyzeAction buildConfiguration="Debug"/>
<ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
''')
print(f'Generated {PROJECT.name}: {len(sources)} application files, {len(tests)} test files')
