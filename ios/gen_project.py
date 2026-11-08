#!/usr/bin/env python3
"""ios/Meridian.xcodeproj 생성 (앱 + 위젯 확장, 폴더 동기화). 대상·설정을 바꾸면 다시 실행한다."""
import os

ROOT = os.path.dirname(os.path.abspath(__file__))
I = lambda n: f"AB00000000000000000000{n:02X}"

APP_ID = "kr.b-612.meridian"
DEPLOY = "26.0"

common_target = lambda extra: "\n".join(f"\t\t\t\t{k} = {v};" for k, v in extra.items())


def target_settings(kind: str) -> dict:
    if kind == "app":
        return {
            "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
            "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
            "CODE_SIGN_ENTITLEMENTS": "Config/Meridian.entitlements",
            "CODE_SIGN_STYLE": "Automatic",
            "CURRENT_PROJECT_VERSION": "1",
            "DEVELOPMENT_TEAM": '""',
            "ENABLE_PREVIEWS": "YES",
            "GENERATE_INFOPLIST_FILE": "YES",
            "INFOPLIST_FILE": "Config/Info.plist",
            "INFOPLIST_KEY_CFBundleDisplayName": '"자오선"',
            "INFOPLIST_KEY_UIApplicationSceneManifest_Generation": "YES",
            "INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents": "YES",
            "INFOPLIST_KEY_UILaunchScreen_Generation": "YES",
            "INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone": '"UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight"',
            "INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad": '"UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight"',
            "LD_RUNPATH_SEARCH_PATHS": '(\n\t\t\t\t\t"$(inherited)",\n\t\t\t\t\t"@executable_path/Frameworks",\n\t\t\t\t)',
            "MARKETING_VERSION": "1.0",
            "PRODUCT_BUNDLE_IDENTIFIER": f'"{APP_ID}"',
            "PRODUCT_NAME": '"$(TARGET_NAME)"',
            "SUPPORTED_PLATFORMS": '"iphoneos iphonesimulator"',
            "SUPPORTS_MACCATALYST": "NO",
            "SWIFT_EMIT_LOC_STRINGS": "YES",
            "SWIFT_VERSION": "5.0",
            "TARGETED_DEVICE_FAMILY": '"1,2"',
        }
    return {
        "CODE_SIGN_ENTITLEMENTS": "Config/Widget.entitlements",
        "CODE_SIGN_STYLE": "Automatic",
        "CURRENT_PROJECT_VERSION": "1",
        "DEVELOPMENT_TEAM": '""',
        "GENERATE_INFOPLIST_FILE": "YES",
        "INFOPLIST_FILE": '"Config/Widget-Info.plist"',
        "INFOPLIST_KEY_CFBundleDisplayName": '"자오선"',
        "LD_RUNPATH_SEARCH_PATHS": '(\n\t\t\t\t\t"$(inherited)",\n\t\t\t\t\t"@executable_path/Frameworks",\n\t\t\t\t\t"@executable_path/../../Frameworks",\n\t\t\t\t)',
        "MARKETING_VERSION": "1.0",
        "PRODUCT_BUNDLE_IDENTIFIER": f'"{APP_ID}.widget"',
        "PRODUCT_NAME": '"$(TARGET_NAME)"',
        "SKIP_INSTALL": "YES",
        "SUPPORTED_PLATFORMS": '"iphoneos iphonesimulator"',
        "SWIFT_EMIT_LOC_STRINGS": "YES",
        "SWIFT_VERSION": "5.0",
        "TARGETED_DEVICE_FAMILY": '"1,2"',
    }


def project_settings(debug: bool) -> dict:
    s = {
        "ALWAYS_SEARCH_USER_PATHS": "NO",
        "ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS": "YES",
        "CLANG_ANALYZER_NONNULL": "YES",
        "CLANG_CXX_LANGUAGE_STANDARD": '"gnu++20"',
        "CLANG_ENABLE_MODULES": "YES",
        "CLANG_ENABLE_OBJC_ARC": "YES",
        "CLANG_ENABLE_OBJC_WEAK": "YES",
        "COPY_PHASE_STRIP": "NO",
        "ENABLE_STRICT_OBJC_MSGSEND": "YES",
        "ENABLE_USER_SCRIPT_SANDBOXING": "YES",
        "GCC_C_LANGUAGE_STANDARD": "gnu17",
        "GCC_NO_COMMON_BLOCKS": "YES",
        "IPHONEOS_DEPLOYMENT_TARGET": DEPLOY,
        "LOCALIZATION_PREFERS_STRING_CATALOGS": "YES",
        "MTL_FAST_MATH": "YES",
        "SDKROOT": "iphoneos",
    }
    if debug:
        s.update({
            "DEBUG_INFORMATION_FORMAT": "dwarf",
            "ENABLE_TESTABILITY": "YES",
            "GCC_DYNAMIC_NO_PIC": "NO",
            "GCC_OPTIMIZATION_LEVEL": "0",
            "GCC_PREPROCESSOR_DEFINITIONS": '(\n\t\t\t\t\t"DEBUG=1",\n\t\t\t\t\t"$(inherited)",\n\t\t\t\t)',
            "MTL_ENABLE_DEBUG_INFO": "INCLUDE_SOURCE",
            "ONLY_ACTIVE_ARCH": "YES",
            "SWIFT_ACTIVE_COMPILATION_CONDITIONS": '"DEBUG $(inherited)"',
            "SWIFT_OPTIMIZATION_LEVEL": '"-Onone"',
        })
    else:
        s.update({
            "DEBUG_INFORMATION_FORMAT": '"dwarf-with-dsym"',
            "ENABLE_NS_ASSERTIONS": "NO",
            "MTL_ENABLE_DEBUG_INFO": "NO",
            "SWIFT_COMPILATION_MODE": "wholemodule",
            "VALIDATE_PRODUCT": "YES",
        })
    return s


def config(id_, name, settings):
    body = common_target(settings)
    return f"""\t\t{id_} /* {name} */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
{body}
\t\t\t}};
\t\t\tname = {name};
\t\t}};"""


def phase(id_, isa, name, files=""):
    return f"""\t\t{id_} /* {name} */ = {{
\t\t\tisa = {isa};
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
{files}\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};"""


pbx = f"""// !$*UTF8*$!
{{
\tarchiveVersion = 1;
\tclasses = {{
\t}};
\tobjectVersion = 77;
\tobjects = {{

/* Begin PBXBuildFile section */
\t\t{I(0x30)} /* MeridianWidget.appex in Embed Foundation Extensions */ = {{isa = PBXBuildFile; fileRef = {I(0x20)} /* MeridianWidget.appex */; settings = {{ATTRIBUTES = (RemoveHeadersOnCopy, ); }}; }};
/* End PBXBuildFile section */

/* Begin PBXFileReference section */
\t\t{I(0x01)} /* Meridian.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = Meridian.app; sourceTree = BUILT_PRODUCTS_DIR; }};
\t\t{I(0x20)} /* MeridianWidget.appex */ = {{isa = PBXFileReference; explicitFileType = "wrapper.app-extension"; includeInIndex = 0; path = MeridianWidget.appex; sourceTree = BUILT_PRODUCTS_DIR; }};
\t\t{I(0x0B)} /* Info.plist */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = "<group>"; }};
\t\t{I(0x0C)} /* Widget-Info.plist */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = "Widget-Info.plist"; sourceTree = "<group>"; }};
\t\t{I(0x0D)} /* Meridian.entitlements */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.entitlements; path = Meridian.entitlements; sourceTree = "<group>"; }};
\t\t{I(0x0E)} /* Widget.entitlements */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.entitlements; path = Widget.entitlements; sourceTree = "<group>"; }};
/* End PBXFileReference section */

/* Begin PBXFileSystemSynchronizedRootGroup section */
\t\t{I(0x02)} /* Meridian */ = {{isa = PBXFileSystemSynchronizedRootGroup; path = Meridian; sourceTree = "<group>"; }};
\t\t{I(0x21)} /* MeridianWidget */ = {{isa = PBXFileSystemSynchronizedRootGroup; path = MeridianWidget; sourceTree = "<group>"; }};
\t\t{I(0x40)} /* Shared */ = {{isa = PBXFileSystemSynchronizedRootGroup; path = Shared; sourceTree = "<group>"; }};
/* End PBXFileSystemSynchronizedRootGroup section */

/* Begin PBXCopyFilesBuildPhase section */
\t\t{I(0x31)} /* Embed Foundation Extensions */ = {{
\t\t\tisa = PBXCopyFilesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tdstPath = "";
\t\t\tdstSubfolderSpec = 13;
\t\t\tfiles = (
\t\t\t\t{I(0x30)} /* MeridianWidget.appex in Embed Foundation Extensions */,
\t\t\t);
\t\t\tname = "Embed Foundation Extensions";
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
/* End PBXCopyFilesBuildPhase section */

/* Begin PBXContainerItemProxy section */
\t\t{I(0x32)} /* PBXContainerItemProxy */ = {{
\t\t\tisa = PBXContainerItemProxy;
\t\t\tcontainerPortal = {I(0x09)} /* Project object */;
\t\t\tproxyType = 1;
\t\t\tremoteGlobalIDString = {I(0x25)};
\t\t\tremoteInfo = MeridianWidget;
\t\t}};
/* End PBXContainerItemProxy section */

/* Begin PBXTargetDependency section */
\t\t{I(0x33)} /* PBXTargetDependency */ = {{
\t\t\tisa = PBXTargetDependency;
\t\t\ttarget = {I(0x25)} /* MeridianWidget */;
\t\t\ttargetProxy = {I(0x32)} /* PBXContainerItemProxy */;
\t\t}};
/* End PBXTargetDependency section */

/* Begin PBXFrameworksBuildPhase section */
{phase(I(0x03), "PBXFrameworksBuildPhase", "Frameworks")}
{phase(I(0x23), "PBXFrameworksBuildPhase", "Frameworks")}
/* End PBXFrameworksBuildPhase section */

/* Begin PBXGroup section */
\t\t{I(0x04)} = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\t{I(0x02)} /* Meridian */,
\t\t\t\t{I(0x21)} /* MeridianWidget */,
\t\t\t\t{I(0x40)} /* Shared */,
\t\t\t\t{I(0x0A)} /* Config */,
\t\t\t\t{I(0x05)} /* Products */,
\t\t\t);
\t\t\tsourceTree = "<group>";
\t\t}};
\t\t{I(0x0A)} /* Config */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\t{I(0x0B)} /* Info.plist */,
\t\t\t\t{I(0x0C)} /* Widget-Info.plist */,
\t\t\t\t{I(0x0D)} /* Meridian.entitlements */,
\t\t\t\t{I(0x0E)} /* Widget.entitlements */,
\t\t\t);
\t\t\tpath = Config;
\t\t\tsourceTree = "<group>";
\t\t}};
\t\t{I(0x05)} /* Products */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\t{I(0x01)} /* Meridian.app */,
\t\t\t\t{I(0x20)} /* MeridianWidget.appex */,
\t\t\t);
\t\t\tname = Products;
\t\t\tsourceTree = "<group>";
\t\t}};
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
\t\t{I(0x06)} /* Meridian */ = {{
\t\t\tisa = PBXNativeTarget;
\t\t\tbuildConfigurationList = {I(0x10)} /* Build configuration list for PBXNativeTarget "Meridian" */;
\t\t\tbuildPhases = (
\t\t\t\t{I(0x07)} /* Sources */,
\t\t\t\t{I(0x03)} /* Frameworks */,
\t\t\t\t{I(0x08)} /* Resources */,
\t\t\t\t{I(0x31)} /* Embed Foundation Extensions */,
\t\t\t);
\t\t\tbuildRules = (
\t\t\t);
\t\t\tdependencies = (
\t\t\t\t{I(0x33)} /* PBXTargetDependency */,
\t\t\t);
\t\t\tfileSystemSynchronizedGroups = (
\t\t\t\t{I(0x02)} /* Meridian */,
\t\t\t\t{I(0x40)} /* Shared */,
\t\t\t);
\t\t\tname = Meridian;
\t\t\tpackageProductDependencies = (
\t\t\t);
\t\t\tproductName = Meridian;
\t\t\tproductReference = {I(0x01)} /* Meridian.app */;
\t\t\tproductType = "com.apple.product-type.application";
\t\t}};
\t\t{I(0x25)} /* MeridianWidget */ = {{
\t\t\tisa = PBXNativeTarget;
\t\t\tbuildConfigurationList = {I(0x28)} /* Build configuration list for PBXNativeTarget "MeridianWidget" */;
\t\t\tbuildPhases = (
\t\t\t\t{I(0x22)} /* Sources */,
\t\t\t\t{I(0x23)} /* Frameworks */,
\t\t\t\t{I(0x24)} /* Resources */,
\t\t\t);
\t\t\tbuildRules = (
\t\t\t);
\t\t\tdependencies = (
\t\t\t);
\t\t\tfileSystemSynchronizedGroups = (
\t\t\t\t{I(0x21)} /* MeridianWidget */,
\t\t\t\t{I(0x40)} /* Shared */,
\t\t\t);
\t\t\tname = MeridianWidget;
\t\t\tpackageProductDependencies = (
\t\t\t);
\t\t\tproductName = MeridianWidget;
\t\t\tproductReference = {I(0x20)} /* MeridianWidget.appex */;
\t\t\tproductType = "com.apple.product-type.app-extension";
\t\t}};
/* End PBXNativeTarget section */

/* Begin PBXProject section */
\t\t{I(0x09)} /* Project object */ = {{
\t\t\tisa = PBXProject;
\t\t\tattributes = {{
\t\t\t\tBuildIndependentTargetsInParallel = 1;
\t\t\t\tLastSwiftUpdateCheck = 1600;
\t\t\t\tLastUpgradeCheck = 1600;
\t\t\t\tTargetAttributes = {{
\t\t\t\t\t{I(0x06)} = {{
\t\t\t\t\t\tCreatedOnToolsVersion = 16.0;
\t\t\t\t\t}};
\t\t\t\t\t{I(0x25)} = {{
\t\t\t\t\t\tCreatedOnToolsVersion = 16.0;
\t\t\t\t\t}};
\t\t\t\t}};
\t\t\t}};
\t\t\tbuildConfigurationList = {I(0x11)} /* Build configuration list for PBXProject "Meridian" */;
\t\t\tdevelopmentRegion = ko;
\t\t\thasScannedForEncodings = 0;
\t\t\tknownRegions = (
\t\t\t\tko,
\t\t\t\tBase,
\t\t\t);
\t\t\tmainGroup = {I(0x04)};
\t\t\tminimizedProjectReferenceProxies = 1;
\t\t\tpreferredProjectObjectVersion = 77;
\t\t\tproductRefGroup = {I(0x05)} /* Products */;
\t\t\tprojectDirPath = "";
\t\t\tprojectRoot = "";
\t\t\ttargets = (
\t\t\t\t{I(0x06)} /* Meridian */,
\t\t\t\t{I(0x25)} /* MeridianWidget */,
\t\t\t);
\t\t}};
/* End PBXProject section */

/* Begin PBXResourcesBuildPhase section */
{phase(I(0x08), "PBXResourcesBuildPhase", "Resources")}
{phase(I(0x24), "PBXResourcesBuildPhase", "Resources")}
/* End PBXResourcesBuildPhase section */

/* Begin PBXSourcesBuildPhase section */
{phase(I(0x07), "PBXSourcesBuildPhase", "Sources")}
{phase(I(0x22), "PBXSourcesBuildPhase", "Sources")}
/* End PBXSourcesBuildPhase section */

/* Begin XCBuildConfiguration section */
{config(I(0x12), "Debug", project_settings(True))}
{config(I(0x13), "Release", project_settings(False))}
{config(I(0x14), "Debug", target_settings("app"))}
{config(I(0x15), "Release", target_settings("app"))}
{config(I(0x26), "Debug", target_settings("share"))}
{config(I(0x27), "Release", target_settings("share"))}
/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
\t\t{I(0x11)} /* Build configuration list for PBXProject "Meridian" */ = {{
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = (
\t\t\t\t{I(0x12)} /* Debug */,
\t\t\t\t{I(0x13)} /* Release */,
\t\t\t);
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t}};
\t\t{I(0x10)} /* Build configuration list for PBXNativeTarget "Meridian" */ = {{
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = (
\t\t\t\t{I(0x14)} /* Debug */,
\t\t\t\t{I(0x15)} /* Release */,
\t\t\t);
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t}};
\t\t{I(0x28)} /* Build configuration list for PBXNativeTarget "MeridianWidget" */ = {{
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = (
\t\t\t\t{I(0x26)} /* Debug */,
\t\t\t\t{I(0x27)} /* Release */,
\t\t\t);
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t}};
/* End XCConfigurationList section */
\t}};
\trootObject = {I(0x09)} /* Project object */;
}}
"""

scheme = f"""<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion = "1600" version = "1.7">
   <BuildAction parallelizeBuildables = "YES" buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry buildForTesting = "YES" buildForRunning = "YES" buildForProfiling = "YES" buildForArchiving = "YES" buildForAnalyzing = "YES">
            <BuildableReference BuildableIdentifier = "primary" BlueprintIdentifier = "{I(0x06)}" BuildableName = "Meridian.app" BlueprintName = "Meridian" ReferencedContainer = "container:Meridian.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv = "YES">
   </TestAction>
   <LaunchAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" launchStyle = "0" useCustomWorkingDirectory = "NO" ignoresPersistentStateOnLaunch = "NO" debugDocumentVersioning = "YES" debugServiceExtension = "internal" allowLocationSimulation = "YES">
      <BuildableProductRunnable runnableDebuggingMode = "0">
         <BuildableReference BuildableIdentifier = "primary" BlueprintIdentifier = "{I(0x06)}" BuildableName = "Meridian.app" BlueprintName = "Meridian" ReferencedContainer = "container:Meridian.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction buildConfiguration = "Release" shouldUseLaunchSchemeArgsEnv = "YES" savedToolIdentifier = "" useCustomWorkingDirectory = "NO" debugDocumentVersioning = "YES">
   </ProfileAction>
   <AnalyzeAction buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction buildConfiguration = "Release" revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
"""

proj = os.path.join(ROOT, "Meridian.xcodeproj")
os.makedirs(os.path.join(proj, "xcshareddata", "xcschemes"), exist_ok=True)
open(os.path.join(proj, "project.pbxproj"), "w").write(pbx)
open(os.path.join(proj, "xcshareddata", "xcschemes", "Meridian.xcscheme"), "w").write(scheme)
print("ok")
