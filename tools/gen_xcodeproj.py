#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""生成 InkReader.xcodeproj（经典 pbxproj，Xcode 14+ 可直接打开）"""
import itertools
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PROJ_DIR = os.path.join(ROOT, "InkReader.xcodeproj")
os.makedirs(PROJ_DIR, exist_ok=True)

_counter = itertools.count(1)


def uid():
    return "AA%022X" % next(_counter)


def q(value):
    """pbxproj 字符串安全引用"""
    return '"%s"' % value.replace("\\", "\\\\").replace('"', '\\"')


# ---------------------------------------------------------------- 文件清单
GROUPS = [
    ("Models", [
        "Book.swift",
        "Bookmark.swift",
        "Collection.swift",
        "ReadingSettings.swift",
    ]),
    ("Services", [
        "AnnotationStore.swift",
        "BackupService.swift",
        "BookImporter.swift",
        "ChapterParser.swift",
        "CollectionStore.swift",
        "ComicExtractor.swift",
        "ComicPageStore.swift",
        "EPUBParser.swift",
        "ExportService.swift",
        "LanShare.swift",
        "LibraryStore.swift",
        "ShareCrypto.swift",
        "SpeechService.swift",
        "Storage.swift",
        "TextEncodingDetector.swift",
        "TextRevision.swift",
        "TxtPaginator.swift",
    ]),
    ("Utils", [
        "Color+Hex.swift",
        "VolumeKeyObserver.swift",
    ]),
]

NESTED_GROUPS = [
    ("Views", [
        ("Library", [
            "BackupView.swift",
            "CollectionsView.swift",
            "ComicPagesView.swift",
            "LanShareView.swift",
            "LibrarySidebarView.swift",
            "LibraryView.swift",
        ]),
        ("Reader", [
            "ComicReaderView.swift",
            "PageTextView.swift",
            "PdfReaderView.swift",
            "PdfSearchView.swift",
            "ReaderContainerView.swift",
            "ReaderViewModel.swift",
            "TxtPagedReader.swift",
            "TxtScrollReader.swift",
        ]),
        ("Overlays", [
            "AnnotationCanvasView.swift",
            "ChapterListView.swift",
            "LookupView.swift",
            "NoteComposer.swift",
            "SettingsPanel.swift",
            "TextRevisionView.swift",
        ]),
    ]),
]

ROOT_FILES = ["InkReaderApp.swift"]
RESOURCES = ["Assets.xcassets"]

# ---------------------------------------------------------------- 固定对象
PROJECT = uid()
TARGET = uid()
MAIN_GROUP = uid()
PRODUCTS_GROUP = uid()
SRC_GROUP = uid()
CL_PROJ = uid()
CL_TARGET = uid()
BC_PROJ_DEBUG = uid()
BC_PROJ_RELEASE = uid()
BC_TGT_DEBUG = uid()
BC_TGT_RELEASE = uid()
PHASE_SOURCES = uid()
PHASE_FRAMEWORKS = uid()
PHASE_RESOURCES = uid()
PRODUCT_REF = uid()
SP_REF = uid()
SP_PRODUCT = uid()
SP_BUILDFILE = uid()

build_files = []      # (id, file_ref_id, name, phase)
file_refs = []        # (id, name, path, filetype, group_id)
resources_files = []  # (id, file_ref_id, name)
group_children = {}   # group_id -> [(id, comment)]
group_defs = {}       # group_id -> (name, path_or_None)


def add_file(filename, group_id):
    ref = uid()
    if filename.endswith(".swift"):
        ftype = "sourcecode.swift"
    elif filename.endswith(".xcassets"):
        ftype = "folder.assetcatalog"
    elif filename.endswith(".plist"):
        ftype = "text.plist.xml"
    else:
        ftype = "text"
    file_refs.append((ref, filename, filename, ftype, group_id))
    group_children.setdefault(group_id, []).append((ref, filename))
    return ref


# 根级文件
for name in ROOT_FILES:
    ref = add_file(name, SRC_GROUP)
    build_files.append((uid(), ref, name, "Sources"))

# 一级分组
for group_name, files in GROUPS:
    gid = uid()
    group_defs[gid] = (group_name, group_name)
    group_children.setdefault(SRC_GROUP, []).append((gid, group_name))
    for name in files:
        ref = add_file(name, gid)
        build_files.append((uid(), ref, name, "Sources"))

# 嵌套分组（Views）
for parent_name, children in NESTED_GROUPS:
    parent_id = uid()
    group_defs[parent_id] = (parent_name, parent_name)
    group_children.setdefault(SRC_GROUP, []).append((parent_id, parent_name))
    for child_name, files in children:
        child_id = uid()
        group_defs[child_id] = (child_name, child_name)
        group_children.setdefault(parent_id, []).append((child_id, child_name))
        for name in files:
            ref = add_file(name, child_id)
            build_files.append((uid(), ref, name, "Sources"))

# 资源
for name in RESOURCES:
    ref = add_file(name, SRC_GROUP)
    resources_files.append((uid(), ref, name))

group_children.setdefault(MAIN_GROUP, []).append((SRC_GROUP, "InkReader"))
group_defs[SRC_GROUP] = ("InkReader", "InkReader")
group_children.setdefault(MAIN_GROUP, []).append((PRODUCTS_GROUP, "Products"))
group_children.setdefault(PRODUCTS_GROUP, []).append((PRODUCT_REF, "InkReader.app"))

# ---------------------------------------------------------------- 输出
out = []
w = out.append

w("// !$*UTF8*$!")
w("{")
w("\tarchiveVersion = 1;")
w("\tclasses = {")
w("\t};")
w("\tobjectVersion = 56;")
w("\tobjects = {")
w("")

# PBXBuildFile
w("/* Begin PBXBuildFile section */")
for bf_id, ref_id, name, phase in build_files:
    w("\t\t%s /* %s in %s */ = {isa = PBXBuildFile; fileRef = %s /* %s */; };"
      % (bf_id, name, phase, ref_id, name))
for bf_id, ref_id, name in resources_files:
    w("\t\t%s /* %s in Resources */ = {isa = PBXBuildFile; fileRef = %s /* %s */; };"
      % (bf_id, name, ref_id, name))
w("\t\t%s /* ZIPFoundation in Frameworks */ = {isa = PBXBuildFile; productRef = %s /* ZIPFoundation */; };"
  % (SP_BUILDFILE, SP_PRODUCT))
w("/* End PBXBuildFile section */")
w("")

# PBXFileReference
w("/* Begin PBXFileReference section */")
w("\t\t%s /* InkReader.app */ = {isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = InkReader.app; sourceTree = BUILT_PRODUCTS_DIR; };"
  % PRODUCT_REF)
for ref_id, name, path, ftype, group_id in file_refs:
    w("\t\t%s /* %s */ = {isa = PBXFileReference; lastKnownFileType = %s; path = %s; sourceTree = \"<group>\"; };"
      % (ref_id, name, ftype, q(path)))
w("/* End PBXFileReference section */")
w("")

# PBXFrameworksBuildPhase
w("/* Begin PBXFrameworksBuildPhase section */")
w("\t\t%s /* Frameworks */ = {" % PHASE_FRAMEWORKS)
w("\t\t\tisa = PBXFrameworksBuildPhase;")
w("\t\t\tbuildActionMask = 2147483647;")
w("\t\t\tfiles = (")
w("\t\t\t\t%s /* ZIPFoundation in Frameworks */," % SP_BUILDFILE)
w("\t\t\t);")
w("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
w("\t\t};")
w("/* End PBXFrameworksBuildPhase section */")
w("")


def write_group(gid, indent="\t\t"):
    if gid == MAIN_GROUP:
        name = None
        path = None
    elif gid == PRODUCTS_GROUP:
        name = "Products"
        path = None
    else:
        name, path = group_defs[gid]
    w("%s%s /* %s */ = {" % (indent, gid, name or gid))
    w("%s\tisa = PBXGroup;" % indent)
    w("%s\tchildren = (" % indent)
    for child_id, child_name in group_children.get(gid, []):
        w("%s\t\t%s /* %s */," % (indent, child_id, child_name))
    w("%s\t);" % indent)
    if path:
        w("%s\tpath = %s;" % (indent, q(path)))
    if name and gid != PRODUCTS_GROUP:
        pass
    w("%s\tsourceTree = \"<group>\";" % indent)
    w("%s};" % indent)


w("/* Begin PBXGroup section */")
w("\t\t%s = {" % MAIN_GROUP)
w("\t\t\tisa = PBXGroup;")
w("\t\t\tchildren = (")
for child_id, child_name in group_children[MAIN_GROUP]:
    w("\t\t\t\t%s /* %s */," % (child_id, child_name))
w("\t\t\t);")
w("\t\t\tsourceTree = \"<group>\";")
w("\t\t};")
w("\t\t%s /* Products */ = {" % PRODUCTS_GROUP)
w("\t\t\tisa = PBXGroup;")
w("\t\t\tchildren = (")
for child_id, child_name in group_children[PRODUCTS_GROUP]:
    w("\t\t\t\t%s /* %s */," % (child_id, child_name))
w("\t\t\t);")
w("\t\t\tname = Products;")
w("\t\t\tsourceTree = \"<group>\";")
w("\t\t};")
for gid in list(group_defs.keys()):
    write_group(gid)
w("/* End PBXGroup section */")
w("")

# PBXNativeTarget
w("/* Begin PBXNativeTarget section */")
w("\t\t%s /* InkReader */ = {" % TARGET)
w("\t\t\tisa = PBXNativeTarget;")
w("\t\t\tbuildConfigurationList = %s /* Build configuration list for PBXNativeTarget \"InkReader\" */;" % CL_TARGET)
w("\t\t\tbuildPhases = (")
w("\t\t\t\t%s /* Sources */," % PHASE_SOURCES)
w("\t\t\t\t%s /* Frameworks */," % PHASE_FRAMEWORKS)
w("\t\t\t\t%s /* Resources */," % PHASE_RESOURCES)
w("\t\t\t);")
w("\t\t\tbuildRules = (")
w("\t\t\t);")
w("\t\t\tdependencies = (")
w("\t\t\t);")
w("\t\t\tname = InkReader;")
w("\t\t\tpackageProductDependencies = (")
w("\t\t\t\t%s /* ZIPFoundation */," % SP_PRODUCT)
w("\t\t\t);")
w("\t\t\tproductName = InkReader;")
w("\t\t\tproductReference = %s /* InkReader.app */;" % PRODUCT_REF)
w("\t\t\tproductType = \"com.apple.product-type.application\";")
w("\t\t};")
w("/* End PBXNativeTarget section */")
w("")

# PBXProject
w("/* Begin PBXProject section */")
w("\t\t%s /* Project object */ = {" % PROJECT)
w("\t\t\tisa = PBXProject;")
w("\t\t\tattributes = {")
w("\t\t\t\tBuildIndependentTargetsInParallel = 1;")
w("\t\t\t\tLastSwiftUpdateCheck = 1600;")
w("\t\t\t\tLastUpgradeCheck = 1600;")
w("\t\t\t\tTargetAttributes = {")
w("\t\t\t\t\t%s = {" % TARGET)
w("\t\t\t\t\t\tCreatedOnToolsVersion = 16.0;")
w("\t\t\t\t\t};")
w("\t\t\t\t};")
w("\t\t\t};")
w("\t\t\tbuildConfigurationList = %s /* Build configuration list for PBXProject \"InkReader\" */;" % CL_PROJ)
w("\t\t\tcompatibilityVersion = \"Xcode 14.0\";")
w("\t\t\tdevelopmentRegion = en;")
w("\t\t\thasScannedForEncodings = 0;")
w("\t\t\tknownRegions = (")
w("\t\t\t\ten,")
w("\t\t\t\tBase,")
w("\t\t\t\t\"zh-Hans\",")
w("\t\t\t);")
w("\t\t\tmainGroup = %s;" % MAIN_GROUP)
w("\t\t\tpackageReferences = (")
w("\t\t\t\t%s /* XCRemoteSwiftPackageReference \"ZIPFoundation\" */," % SP_REF)
w("\t\t\t);")
w("\t\t\tproductRefGroup = %s /* Products */;" % PRODUCTS_GROUP)
w("\t\t\tprojectDirPath = \"\";")
w("\t\t\tprojectRoot = \"\";")
w("\t\t\ttargets = (")
w("\t\t\t\t%s /* InkReader */," % TARGET)
w("\t\t\t);")
w("\t\t};")
w("/* End PBXProject section */")
w("")

# PBXResourcesBuildPhase
w("/* Begin PBXResourcesBuildPhase section */")
w("\t\t%s /* Resources */ = {" % PHASE_RESOURCES)
w("\t\t\tisa = PBXResourcesBuildPhase;")
w("\t\t\tbuildActionMask = 2147483647;")
w("\t\t\tfiles = (")
for bf_id, ref_id, name in resources_files:
    w("\t\t\t\t%s /* %s in Resources */," % (bf_id, name))
w("\t\t\t);")
w("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
w("\t\t};")
w("/* End PBXResourcesBuildPhase section */")
w("")

# PBXSourcesBuildPhase
w("/* Begin PBXSourcesBuildPhase section */")
w("\t\t%s /* Sources */ = {" % PHASE_SOURCES)
w("\t\t\tisa = PBXSourcesBuildPhase;")
w("\t\t\tbuildActionMask = 2147483647;")
w("\t\t\tfiles = (")
for bf_id, ref_id, name, phase in build_files:
    w("\t\t\t\t%s /* %s in Sources */," % (bf_id, name))
w("\t\t\t);")
w("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
w("\t\t};")
w("/* End PBXSourcesBuildPhase section */")
w("")

PROJECT_COMMON = [
    ("ALWAYS_SEARCH_USER_PATHS", "NO"),
    ("CLANG_ANALYZER_NONNULL", "YES"),
    ("CLANG_ENABLE_MODULES", "YES"),
    ("CLANG_ENABLE_OBJC_ARC", "YES"),
    ("COPY_PHASE_STRIP", "NO"),
    ("ENABLE_STRICT_OBJC_MSGSEND", "YES"),
    ("GCC_C_LANGUAGE_STANDARD", "gnu17"),
    ("GCC_NO_COMMON_BLOCKS", "YES"),
    ("GCC_WARN_UNDECLARED_SELECTOR", "YES"),
    ("IPHONEOS_DEPLOYMENT_TARGET", "17.0"),
    ("SDKROOT", "iphoneos"),
    ("SWIFT_EMIT_LOC_STRINGS", "YES"),
]
PROJECT_DEBUG = [
    ("DEBUG_INFORMATION_FORMAT", "dwarf"),
    ("ENABLE_TESTABILITY", "YES"),
    ("GCC_PREPROCESSOR_DEFINITIONS", "(\n\t\t\t\t\t\"DEBUG=1\",\n\t\t\t\t\t\"$(inherited)\",\n\t\t\t\t)"),
    ("SWIFT_ACTIVE_COMPILATION_CONDITIONS", "\"DEBUG $(inherited)\""),
    ("SWIFT_OPTIMIZATION_LEVEL", "\"-Onone\""),
]
PROJECT_RELEASE = [
    ("DEBUG_INFORMATION_FORMAT", "\"dwarf-with-dsym\""),
    ("SWIFT_COMPILATION_MODE", "wholemodule"),
    ("VALIDATE_PRODUCT", "YES"),
]

TARGET_COMMON = [
    ("ASSETCATALOG_COMPILER_APPICON_NAME", "AppIcon"),
    ("ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME", "AccentColor"),
    ("CODE_SIGN_STYLE", "Automatic"),
    ("CURRENT_PROJECT_VERSION", "1"),
    ("GENERATE_INFOPLIST_FILE", "YES"),
    ("INFOPLIST_FILE", "InkReader/Info.plist"),
    ("IPHONEOS_DEPLOYMENT_TARGET", "17.0"),
    ("LD_RUNPATH_SEARCH_PATHS", "(\n\t\t\t\t\t\"$(inherited)\",\n\t\t\t\t\t\"@executable_path/Frameworks\",\n\t\t\t\t)"),
    ("MARKETING_VERSION", "1.0"),
    ("PRODUCT_BUNDLE_IDENTIFIER", "com.inkreader.app"),
    ("PRODUCT_NAME", "\"$(TARGET_NAME)\""),
    ("SUPPORTED_PLATFORMS", "iphoneos iphonesimulator"),
    ("SWIFT_VERSION", "5.0"),
    ("TARGETED_DEVICE_FAMILY", "\"1,2\""),
]


def write_bc(bc_id, name, settings):
    w("\t\t%s /* %s */ = {" % (bc_id, name))
    w("\t\t\tisa = XCBuildConfiguration;")
    w("\t\t\tbuildSettings = {")
    for key, value in settings:
        w("\t\t\t\t%s = %s;" % (key, value))
    w("\t\t\t};")
    w("\t\t\tname = %s;" % name)
    w("\t\t};")


w("/* Begin XCBuildConfiguration section */")
write_bc(BC_PROJ_DEBUG, "Debug", PROJECT_COMMON + PROJECT_DEBUG)
write_bc(BC_PROJ_RELEASE, "Release", PROJECT_COMMON + PROJECT_RELEASE)
write_bc(BC_TGT_DEBUG, "Debug", TARGET_COMMON)
write_bc(BC_TGT_RELEASE, "Release", TARGET_COMMON)
w("/* End XCBuildConfiguration section */")
w("")

w("/* Begin XCConfigurationList section */")
w("\t\t%s /* Build configuration list for PBXProject \"InkReader\" */ = {" % CL_PROJ)
w("\t\t\tisa = XCConfigurationList;")
w("\t\t\tbuildConfigurations = (")
w("\t\t\t\t%s /* Debug */," % BC_PROJ_DEBUG)
w("\t\t\t\t%s /* Release */," % BC_PROJ_RELEASE)
w("\t\t\t);")
w("\t\t\tdefaultConfigurationIsVisible = 0;")
w("\t\t\tdefaultConfigurationName = Release;")
w("\t\t};")
w("\t\t%s /* Build configuration list for PBXNativeTarget \"InkReader\" */ = {" % CL_TARGET)
w("\t\t\tisa = XCConfigurationList;")
w("\t\t\tbuildConfigurations = (")
w("\t\t\t\t%s /* Debug */," % BC_TGT_DEBUG)
w("\t\t\t\t%s /* Release */," % BC_TGT_RELEASE)
w("\t\t\t);")
w("\t\t\tdefaultConfigurationIsVisible = 0;")
w("\t\t\tdefaultConfigurationName = Release;")
w("\t\t};")
w("/* End XCConfigurationList section */")
w("")

w("/* Begin XCRemoteSwiftPackageReference section */")
w("\t\t%s /* XCRemoteSwiftPackageReference \"ZIPFoundation\" */ = {" % SP_REF)
w("\t\t\tisa = XCRemoteSwiftPackageReference;")
w("\t\t\trepositoryURL = \"https://github.com/weichsel/ZIPFoundation.git\";")
w("\t\t\trequirement = {")
w("\t\t\t\tkind = upToNextMajorVersion;")
w("\t\t\t\tminimumVersion = 0.9.19;")
w("\t\t\t};")
w("\t\t};")
w("/* End XCRemoteSwiftPackageReference section */")
w("")

w("/* Begin XCSwiftPackageProductDependency section */")
w("\t\t%s /* ZIPFoundation */ = {" % SP_PRODUCT)
w("\t\t\tisa = XCSwiftPackageProductDependency;")
w("\t\t\tpackage = %s /* XCRemoteSwiftPackageReference \"ZIPFoundation\" */;" % SP_REF)
w("\t\t\tproductName = ZIPFoundation;")
w("\t\t};")
w("/* End XCSwiftPackageProductDependency section */")

w("\t};")
w("\trootObject = %s /* Project object */;" % PROJECT)
w("}")

content = "\n".join(out) + "\n"

# 基本格式自检
assert content.count("{") == content.count("}"), "brace mismatch %d/%d" % (
    content.count("{"), content.count("}"))
assert content.count("(") == content.count(")"), "paren mismatch %d/%d" % (
    content.count("("), content.count(")"))

with open(os.path.join(PROJ_DIR, "project.pbxproj"), "w", encoding="utf-8", newline="\n") as f:
    f.write(content)

print("generated:", os.path.join(PROJ_DIR, "project.pbxproj"))
print("files:", len(file_refs), "build files:", len(build_files))

# ---------------------------------------------------------------- shared scheme
# 关键：没有 scheme 时 xcodebuild 无法解析 SPM 包依赖，CI 上会直接失败（exit 74）。
# 放在 xcshareddata 下才会进 git（xcuserdata 被 .gitignore 忽略）。
SCHEME_DIR = os.path.join(PROJ_DIR, "xcshareddata", "xcschemes")
os.makedirs(SCHEME_DIR, exist_ok=True)

BUILDABLE = """            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "__TARGET__"
               BuildableName = "InkReader.app"
               BlueprintName = "InkReader"
               ReferencedContainer = "container:InkReader.xcodeproj">
            </BuildableReference>""".replace("__TARGET__", TARGET)

SCHEME = """<?xml version="1.0" encoding="UTF-8"?>
<Scheme
   LastUpgradeVersion = "1500"
   version = "1.3">
   <BuildAction
      parallelizeBuildables = "YES"
      buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry
            buildForTesting = "YES"
            buildForRunning = "YES"
            buildForProfiling = "YES"
            buildForArchiving = "YES"
            buildForAnalyzing = "YES">
__REF__
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      shouldUseLaunchSchemeArgsEnv = "YES">
      <Testables>
      </Testables>
   </TestAction>
   <LaunchAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      launchStyle = "0"
      useCustomWorkingDirectory = "NO"
      ignoresPersistentStateOnLaunch = "NO"
      debugDocumentVersioning = "YES"
      debugServiceExtension = "internal"
      allowLocationSimulation = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
__REF__
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction
      buildConfiguration = "Release"
      shouldUseLaunchSchemeArgsEnv = "YES"
      savedToolIdentifier = ""
      useCustomWorkingDirectory = "NO"
      debugDocumentVersioning = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
__REF__
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction
      buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction
      buildConfiguration = "Release"
      revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
""".replace("__REF__", BUILDABLE)

with open(os.path.join(SCHEME_DIR, "InkReader.xcscheme"), "w", encoding="utf-8", newline="\n") as f:
    f.write(SCHEME)

print("generated:", os.path.join(SCHEME_DIR, "InkReader.xcscheme"))
