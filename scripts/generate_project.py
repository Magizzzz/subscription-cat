from pathlib import Path
import hashlib
root=Path(__file__).resolve().parent.parent
objects={}
def uid(s): return hashlib.sha1(s.encode()).hexdigest()[:24].upper()
def obj(name,body):
 i=uid(name);objects[i]=body;return i
def arr(ids):return '('+','.join(ids)+',)' if ids else '()'
def q(s):return '"'+s.replace('\\','\\\\').replace('"','\\"')+'"'
app='SubscriptionWallet'; proj=uid('project'); appid=uid('appTarget'); testid=uid('testTarget'); uiid=uid('uiTarget')
product=obj('appProduct','isa = PBXFileReference; explicitFileType = wrapper.application; path = SubscriptionWallet.app; sourceTree = BUILT_PRODUCTS_DIR;')
testProduct=obj('testProduct','isa = PBXFileReference; explicitFileType = wrapper.cfbundle; path = SubscriptionWalletTests.xctest; sourceTree = BUILT_PRODUCTS_DIR;')
uiProduct=obj('uiProduct','isa = PBXFileReference; explicitFileType = wrapper.cfbundle; path = SubscriptionWalletUITests.xctest; sourceTree = BUILT_PRODUCTS_DIR;')
groups=[];phases={}
for folder,target in [('SubscriptionWallet','app'),('Tests','test'),('UITests','ui')]:
 refs=[];sources=[];resources=[]
 for f in sorted((root/folder).rglob('*')):
  if not f.is_file() or f.suffix not in ('.swift','.json') or '.xcassets' in f.as_posix():continue
  rel=f.relative_to(root).as_posix(); typ='sourcecode.swift' if f.suffix=='.swift' else 'text.json'
  ref=obj('ref'+rel,f'isa = PBXFileReference; lastKnownFileType = {typ}; path = {q(rel)}; sourceTree = SOURCE_ROOT;');refs.append(ref)
  b=obj('build'+rel,f'isa = PBXBuildFile; fileRef = {ref};')
  (sources if f.suffix=='.swift' else resources).append(b)
 for cat in sorted((root/folder).rglob('*.xcassets')):
  rel=cat.relative_to(root).as_posix()
  ref=obj('ref'+rel,f'isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = {q(rel)}; sourceTree = SOURCE_ROOT;');refs.append(ref)
  resources.append(obj('build'+rel,f'isa = PBXBuildFile; fileRef = {ref};'))
 group=obj('group'+target,f'isa = PBXGroup; children = {arr(refs)}; name = {folder}; sourceTree = "<group>";');groups.append(group)
 src=obj('src'+target,f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = {arr(sources)}; runOnlyForDeploymentPostprocessing = 0;')
 res=obj('res'+target,f'isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = {arr(resources)}; runOnlyForDeploymentPostprocessing = 0;')
 fw=obj('fw'+target,'isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;')
 phases[target]=[src,fw,res]
products=obj('products',f'isa = PBXGroup; children = {arr([product,testProduct,uiProduct])}; name = Products; sourceTree = "<group>";')
main=obj('mainGroup',f'isa = PBXGroup; children = {arr(groups+[products])}; sourceTree = "<group>";')
def configlist(name,extra):
 ids=[]
 for debug in [True,False]:
  typ='Debug' if debug else 'Release'
  base={'SWIFT_VERSION':'5.0','IPHONEOS_DEPLOYMENT_TARGET':'17.0','SDKROOT':'iphoneos','TARGETED_DEVICE_FAMILY':'1','CODE_SIGN_STYLE':'Automatic','GENERATE_INFOPLIST_FILE':'YES','SWIFT_STRICT_CONCURRENCY':'minimal','ENABLE_TESTABILITY':'YES' if debug else 'NO','SWIFT_OPTIMIZATION_LEVEL':'-Onone' if debug else '-O','DEBUG_INFORMATION_FORMAT':'dwarf','CLANG_ENABLE_MODULES':'YES','SWIFT_ACTIVE_COMPILATION_CONDITIONS':'DEBUG' if debug else ''}
  base.update(extra)
  ids.append(obj(name+typ,'isa = XCBuildConfiguration; buildSettings = {'+' '.join(k+' = '+q(v)+';' for k,v in base.items())+'}; name = '+typ+';'))
 return obj(name+'configs',f'isa = XCConfigurationList; buildConfigurations = {arr(ids)}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
pc=configlist('project',{})
ac=configlist('app',{'PRODUCT_BUNDLE_IDENTIFIER':'local.magi.SubscriptionWallet$(WALLET_BUNDLE_SUFFIX)','PRODUCT_NAME':'$(TARGET_NAME)','INFOPLIST_KEY_CFBundleDisplayName':'订阅猫','INFOPLIST_KEY_LSApplicationCategoryType':'public.app-category.finance','INFOPLIST_KEY_UILaunchScreen_Generation':'YES','INFOPLIST_KEY_UISupportedInterfaceOrientations':'UIInterfaceOrientationPortrait','MARKETING_VERSION':'0.5.1','CURRENT_PROJECT_VERSION':'12'}|({'ASSETCATALOG_COMPILER_APPICON_NAME':'AppIcon'} if (root/'SubscriptionWallet/Assets.xcassets/AppIcon.appiconset').exists() else {}))
tc=configlist('test',{'PRODUCT_BUNDLE_IDENTIFIER':'local.magi.SubscriptionWalletTests','PRODUCT_NAME':'$(TARGET_NAME)','TEST_HOST':'$(BUILT_PRODUCTS_DIR)/SubscriptionWallet.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/SubscriptionWallet','BUNDLE_LOADER':'$(TEST_HOST)'})
uc=configlist('ui',{'PRODUCT_BUNDLE_IDENTIFIER':'local.magi.SubscriptionWalletUITests','PRODUCT_NAME':'$(TARGET_NAME)','TEST_TARGET_NAME':'SubscriptionWallet'})
proxy=obj('testproxy',f'isa = PBXContainerItemProxy; containerPortal = {proj}; proxyType = 1; remoteGlobalIDString = {appid}; remoteInfo = SubscriptionWallet;')
dep=obj('testdep',f'isa = PBXTargetDependency; target = {appid}; targetProxy = {proxy};')
for name,tid,c,product,kind in [('app',appid,ac,product,'application'),('test',testid,tc,testProduct,'bundle.unit-test'),('ui',uiid,uc,uiProduct,'bundle.ui-testing')]:
 title={'app':'SubscriptionWallet','test':'SubscriptionWalletTests','ui':'SubscriptionWalletUITests'}[name]
 objects[tid]=f'isa = PBXNativeTarget; buildConfigurationList = {c}; buildPhases = {arr(phases[name])}; buildRules = (); dependencies = {arr([] if name=="app" else [dep])}; name = {title}; productName = {title}; productReference = {product}; productType = "com.apple.product-type.{kind}";'
objects[proj]=f'isa = PBXProject; attributes = {{ LastUpgradeCheck = 1600; BuildIndependentTargetsInParallel = YES; }}; buildConfigurationList = {pc}; compatibilityVersion = "Xcode 14.0"; developmentRegion = zh_CN; hasScannedForEncodings = 0; knownRegions = (zh_CN,en,Base); mainGroup = {main}; productRefGroup = {products}; projectDirPath = ""; projectRoot = ""; targets = {arr([appid,testid,uiid])};'
text='// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n'+'\n'.join(i+' = {'+body+'};' for i,body in objects.items())+'\n}; rootObject = '+proj+'; }\n'
(root/'SubscriptionWallet.xcodeproj/project.pbxproj').write_text(text)
scheme=f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.7"><BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{appid}" BuildableName="SubscriptionWallet.app" BlueprintName="SubscriptionWallet" ReferencedContainer="container:SubscriptionWallet.xcodeproj"/></BuildActionEntry></BuildActionEntries></BuildAction><TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables>'''
for i,name in [(testid,'SubscriptionWalletTests'),(uiid,'SubscriptionWalletUITests')]:scheme+=f'<TestableReference skipped="NO"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{i}" BuildableName="{name}.xctest" BlueprintName="{name}" ReferencedContainer="container:SubscriptionWallet.xcodeproj"/></TestableReference>'
scheme+=f'''</Testables></TestAction><LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{appid}" BuildableName="SubscriptionWallet.app" BlueprintName="SubscriptionWallet" ReferencedContainer="container:SubscriptionWallet.xcodeproj"/></BuildableProductRunnable></LaunchAction><ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"/><AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/></Scheme>'''
(root/'SubscriptionWallet.xcodeproj/xcshareddata/xcschemes/SubscriptionWallet.xcscheme').write_text(scheme)
