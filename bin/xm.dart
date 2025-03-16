import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:archive/archive_io.dart';
import 'package:ini/ini.dart';
import 'dart:math' as math;
import 'package:stack_trace/stack_trace.dart';

void main(List<String> args) async {

  // 获取当前执行文件所在目录
  final exeDir = File(Platform.resolvedExecutable).parent;
  // 修改配置文件路径为 exe 所在目录下的 xm_config.ini
  final configFile = File('${exeDir.path}/xm_config.ini');

  if (!configFile.existsSync()) {
    print('找不到配置文件 xm_config.ini');
    return;
  }

  final config = Config.fromString(configFile.readAsStringSync());

  if (args.isEmpty) {
    print('可用模块: ${config.sections().join(', ')}');
    return;
  }

  if (args.contains('-h') || args.contains('--help')) {
    _printHelp();
    return;
  }

  else if (args[0] == '-x') {
    final userPath = _getUserPath().split(';');
    print('-----------------');
    for (var p in userPath) {
      print(p);
    }
    return ;
  }
  else if (args[0] == '-p') {
    printAllModulesStatus(config);
    return;
  }
  else if (args[0] == '--unset-all') {

    print('正在清理所有模块环境变量...');
    for (final section in config.sections()) {
      await unsetCommand(section, config);
    }
    print('清理完成');
    return;
  }

  // 动态处理所有模块命令
  final section = args[0];
  if (config.sections().contains(section)) {
    await handleSectionCommand(section, args.sublist(1), config);
  } else {
    print('无效模块: $section');
    print('可用模块: ${config.sections().join(', ')}');
  }
}

void _printHelp() {
  final helpText = '''
XM 多版本管理器 v1.0

使用方式:
  xm [选项] [模块名称] [命令]
  -h, --help                   显示帮助信息
  -p                           显示所有模块状态
  -x                           显示当前 PATH 环境变量
  --unset-all                  清理所有模块环境变量
  [module]                     显示可用版本列表
  [module] install [version]   安装指定版本
  [module] use [version]       使用指定版本
  [module] unset               取消使用当前版本
  [module] remove [version]    移除已安装版本
''';

  print(helpText);
}


// 通用模块命令处理
Future<void> handleSectionCommand(
    String section, List<String> args, Config config) async {

  if (args.isEmpty) {
    printSectionList(section, config);
  } 

  else if (args[0] == 'install') {
    if (args.length >= 2) {
      await installPackage(section, args[1], config);
    } else {
      print("\nselect a version\n");
      printSectionList(section, config);
    }
  } else if (args[0] == 'use' && args.length >= 2) {
    final targetPath = await useCommand(section, args[1], config);

    if (targetPath.isEmpty) {
      return;
    }

    final addEntries = config
            .items(section)
            ?.where((item) =>
                item.length >= 2 &&
                item[0]?.toLowerCase() == 'add' &&
                item[1] != null) // Add null check for value
            .expand((item) => item[1]!.split(';'))
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList() ??
        [];

    for (final entry in addEntries) {
      final parts = entry.split('=').map((e) => e.trim()).toList();
      if (parts.length != 2) continue;

      final varName = parts[0].replaceAll(RegExp(r'^"|"$'), '');
      var varValue = parts[1]
          .replaceAll(r'${CURRENT_USE_DIR}', targetPath)
          .replaceAllMapped(RegExp(r'(?<!\\)%'), (m) => '^%')
          // 引号过滤逻辑
          .replaceAll(RegExp(r'^"|"$'), '');
      print("$varName = $varValue");
      await setUserEnvironmentVariable(varName, varValue);
    }
  } else if (args[0] == 'unset') {
    // 新增 unset 命令
    await unsetCommand(section, config);
    await removeEnvironmentVariables(section, config);
  } else if (args[0] == 'remove' && args.length >= 2) {
    await removePackage(section, args[1], config);
  }
}

// 新增移除方法
Future<void> removePackage(String section, String version, Config config) async {
  final installDir = Directory('install/$section/$version');
  if (!installDir.existsSync()) {
    print('未安装 $section $version');
    return;
  }

  try {
    print('正在移除 $section/$version...');
    unsetCommand(section, config);
    installDir.deleteSync(recursive: true);
    print('移除成功');
  } catch (e) {
    print('移除失败: $e');
  }
}

// 注册表读取方法
String _getUserPath() {
  final result = Process.runSync(
      'reg', ['query', 'HKCU\\Environment', '/v', 'PATH'],
      runInShell: true);
  if (result.exitCode!= 0) {
    print("获取用户变量出错 ${result.stderr}");
    return '';
  }
  final lines = result.stdout.toString().split('\n');
  return lines
      .firstWhere((line) => line.trim().startsWith('PATH'),
          orElse: () => 'PATH    REG_EXPAND_SZ    ')
      .split('REG_EXPAND_SZ')
      .last
      .trim();
}

// 新增删除软链接方法
Future<void> unsetCommand(String section, Config config) async {

  // 获取所有需要清理的路径
  final pathsToRemove = <String>[];

  // 1. 添加 install 目录路径
  final installDir = Directory('install/$section');
  if (installDir.existsSync()) {
    pathsToRemove.add(installDir.absolute.path.replaceAll('/', '\\'));
  }

  // 2. 添加配置中的本地路径
  final localPaths = config.items(section)
      ?.where((item) => item.length >= 2 && 
          !item[0]!.toLowerCase().startsWith('add') &&
          !(item[1]?.startsWith('http') ?? true) &&
          !(item[1]?.startsWith('https') ?? true))
      .map((item) => item[1]!.replaceAll('"', '')) // 去除引号
      .expand((path) => path.split(';'))           // 展开多路径
      .map((p) => p.trim())                        // 去除空格
      .where((p) => p.isNotEmpty)                  // 过滤空路径
      .map((p) => p.replaceAll('/', Platform.pathSeparator)) // 统一路径格式
      .toList() ?? [];

  pathsToRemove.addAll(localPaths);

  // PATH 清理逻辑
  final userPath = _getUserPath().replaceAllMapped(RegExp(r'(?<!\\)%'), (m) => '^%');
  var pathList = userPath.split(';');

  List<String> newPathList = [];
  for (var p in pathList) {
    if (p.isEmpty) continue;
    // 检查路径是否需要保留
    final shouldKeep = pathsToRemove.every((removePath) => 
        !p.toLowerCase().contains(removePath.toLowerCase().replaceAllMapped(RegExp(r'(?<!\\)%'), (m) => '^%')));
    if (shouldKeep) {
      newPathList.add(p);
    }
  }

  final newPath = newPathList.join(';');
  await setUserEnvironmentVariable('PATH', newPath);
}

// 新增环境变量移除方法
Future<void> removeEnvironmentVariables(String section, Config config) async {
  final addEntries = config
          .items(section)
          ?.where((item) =>
              item.length >= 2 &&
              item[0]?.toLowerCase() == 'add' &&
              item[1] != null)
          .expand((item) => item[1]!.split(';'))
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList() ??
      [];

  for (final entry in addEntries) {
    final parts = entry.split('=').map((e) => e.trim()).toList();
    if (parts.length != 2) continue;

    final varName = parts[0].replaceAll(RegExp(r'^"|"$'), '');
    // 使用注册表删除命令
    final result = Process.runSync(
        'reg', ['delete', 'HKCU\\Environment', '/v', varName, '/f'],
        runInShell: true);

    if (result.exitCode == 0) {
      print('移除环境变量 $varName');
    } else if (result.exitCode != 1) {
      print('移除失败: ${result.stderr}');
    }
  }
}

// 新增用户环境变量设置方法
Future<void> setUserEnvironmentVariable(String varName, String value) async {
  try {
    final result = Process.runSync(
        'reg',
        [
          'add',
          'HKCU\\Environment',
          '/v',
          varName,
          '/t',
          'REG_EXPAND_SZ',
          '/d',
          value,
          '/f'
        ],
        runInShell: true);

    if (result.exitCode != 0) {
      print('环境变量设置失败: ${result.stderr}');
    } else {
      // print('设置环境变量 $varName=$value');
    }
  } catch (e) {
    print('环境变量操作异常: $e');
  }
}

// 新增模块状态生成辅助方法
String _getModuleStatus(String section, Config config, List<String> userPath) {

  // 获取本地路径版本
  final localVersions = config.items(section)
      ?.where((item) => item.length >= 2 && 
          !item[0]!.toLowerCase().startsWith('add') &&
          !(item[1]?.startsWith('http') ?? true) && 
          !(item[1]?.startsWith('https') ?? true))
      .map((item) => item[0]!)
      .toList() ?? [];

  // 获取已安装版本
  final installDir = Directory('install/$section');
  final installedVersions = installDir.existsSync()
      ? installDir
          .listSync()
          .whereType<Directory>()
          .map((d) => d.path.split('\\').last)
          .toSet()
      : <String>{};

  // 获取使用中的版本
  final inUseVersion = userPath
      .firstWhere(
        (p) => p.contains('install\\$section\\'),
        orElse: () => '',
      )
      .split('\\')
      .where((e) => e.isNotEmpty)
      .toList();

  final pathInUseVerion = userPath.where((p) => _isLocalPathInUse(config, section, p)).toSet();
  Set<String> localInUseVersion = <String>{};
  
  // 新增：建立路径与版本的映射关系
  final pathVersionMap = <String, String>{};
  config.items(section)?.forEach((entry) {
    if (entry.length >= 2) {
      final version = entry[0]!;
      // 新增引号移除逻辑
      final rawValue = entry[1]!.replaceAll(RegExp(r'^"|"$'), '');
      final paths = rawValue.split(';');
      for (var p in paths) {
        p = p.trim().toLowerCase().replaceAll('/', Platform.pathSeparator);
        if (p.isNotEmpty) {
          pathVersionMap[p] = version;
        }
      }
    }
  });
  
  // 检查当前使用的路径对应的版本
  pathInUseVerion.forEach((usedPath) {
    final normalizedPath = usedPath.toLowerCase().replaceAll('/', Platform.pathSeparator);
    pathVersionMap.forEach((path, version) {
      if (normalizedPath == path) {
        localInUseVersion.add(version);
      }
    });
  });

  String version = '';
  for (var i = 0; i < inUseVersion.length - 1; i++) {
    if (inUseVersion[i] == 'install' && 
        inUseVersion[i + 1] == section.toLowerCase()) {
      if (i + 2 < inUseVersion.length) {
        version = inUseVersion[i + 2];
      }
      break;
    }
  }

  final status = StringBuffer();
  if (version.isNotEmpty) {
    status.write('* $version');
  } 
  else if (localInUseVersion.isNotEmpty) {
    status.write('* ${localInUseVersion.first} (local)');
  }
  else if (installedVersions.isNotEmpty) {
    status.write('@ ${installedVersions.first}');
  } else if (localVersions.isNotEmpty) {
    status.write('# ${localVersions.first}'); 
  } else {
    status.write('none');
  }
  return status.toString();
}

// 新增模块状态打印方法
void printAllModulesStatus(Config config) {
  // 动态计算列宽
  int maxNameLength = 8; // 初始值为列标题"模块名称"的长度
  int maxStatusLength = 4; // 初始值为列标题"状态"的长度

  final userPath = _getUserPath().toLowerCase().split(';');

  // 首次遍历收集最大长度
  for (final section in config.sections()) {
    // ... 状态生成逻辑与之前相同 ...
    final status = _getModuleStatus(section, config, userPath); // 假设抽取出状态生成逻辑
    
    maxNameLength = math.max(maxNameLength, section.length);
    maxStatusLength = math.max(maxStatusLength, status.length);
  }

  // 设置列宽（最大内容长度 + 2个空格缓冲）
  final nameWidth = maxNameLength + 2;
  final statusWidth = math.max(maxStatusLength + 2, 16); // 保持最小宽度

  // 生成动态边框线
  final borderLine = '+${'-' * nameWidth}+${'-' * statusWidth}+';
  
  // 打印表格头
  print(borderLine);
  print('| ${'name'.padRight(nameWidth-2)} | ${'status'.padRight(statusWidth-2)} |');
  print(borderLine);

  // 打印数据行
  for (final section in config.sections()) {
    final status = _getModuleStatus(section, config, userPath);
    print('| ${section.padRight(nameWidth-2)} | ${status.padRight(statusWidth-2)} |');
    print(borderLine);
  }
}

// 新增本地路径使用状态检查方法
bool _isLocalPathInUse(Config config, String section, String path) {
  final localEntries = config.items(section)
      ?.where((item) => item.length >= 2 && 
          !item[0]!.toLowerCase().startsWith('add') &&
          !item[1]!.startsWith('http') && 
          !item[1]!.startsWith('https'))
      .toList() ?? [];

  return localEntries.any((entry) {
    final cleanedPath = entry[1]!.replaceAll('"', '').split(';');

    for (var p in cleanedPath) {
      if(p.isEmpty) continue;
      p = p.toLowerCase().replaceAll('/', Platform.pathSeparator);
      if (path.contains(p)) {
        return true;
      }
    }
    return false; 
  });
}


// 通用列表打印
void printSectionList(String section, Config config) {

  final items = config
      .items(section)
      ?.where((item) => item.length >= 2 && !item[0]!.toLowerCase().startsWith('add')) 
      .map((item) => MapEntry(item[0]!, item[1]!))
      .toList() ?? [];

  // 获取已安装版本
  final installDir = Directory('install/$section');
  final installedVersions = installDir.existsSync()
      ? installDir
          .listSync()
          .whereType<Directory>()
          .map((d) => d.path.split('\\').last)
          .toSet()
      : <String>{};

  // 本地路径检测
  final localPaths = items
      .where((entry) => !entry.value.startsWith('http') && !entry.value.startsWith('https'))
      .map((entry) => entry.key)
      .toSet();

  // 获取当前使用的路径
  final userPath = _getUserPath().toLowerCase().split(';');
  final inUseVersions = userPath
      .where((p) => p.contains('install\\$section\\'))
      .map((p) {
        final parts = p.split('\\').where((e) => e.isNotEmpty).toList();
        for (var i = 0; i < parts.length - 1; i++) {
          if (parts[i].toLowerCase() == 'install' && 
              parts[i + 1].toLowerCase() == section.toLowerCase()) {
            return i + 2 < parts.length ? parts[i + 2] : null;
          }
        }
        return null;
      })
      .where((v) => v != null)
      .toSet();

  final pathInUseVerion = userPath.where((p) => _isLocalPathInUse(config, section, p)).toSet();
  Set<String> localInUseVersion = <String>{};
  
  // 新增：建立路径与版本的映射关系
  final pathVersionMap = <String, String>{};
  config.items(section)?.forEach((entry) {
    if (entry.length >= 2) {
      final version = entry[0]!;
      // 新增引号移除逻辑
      final rawValue = entry[1]!.replaceAll(RegExp(r'^"|"$'), '');
      final paths = rawValue.split(';');
      for (var p in paths) {
        p = p.trim().toLowerCase().replaceAll('/', Platform.pathSeparator);
        if (p.isNotEmpty) {
          pathVersionMap[p] = version;
        }
      }
    }
  });
  
  // 检查当前使用的路径对应的版本
  pathInUseVerion.forEach((usedPath) {
    final normalizedPath = usedPath.toLowerCase().replaceAll('/', Platform.pathSeparator);
    pathVersionMap.forEach((path, version) {
      if (normalizedPath == path) {
        localInUseVersion.add(version);
      }
    });
  });

  // 生成带状态的列表项
  final entries = items.map((entry) {

    final version = entry.key;
    final isInstalled = installedVersions.contains(version);
    final isLocal = localPaths.contains(version);
    final isInUse = inUseVersions.contains(version) || localInUseVersion.contains(version);
    
    final status = StringBuffer();
    if (isInUse) {
      status.write(' * ');
    } else if (isInstalled) {
      status.write(' @ ');
    }
    else if (isLocal) {
      status.write(' # ');
    }
    else {
      status.write('  ');
    }

    return '${status.toString().padRight(3)}$version';
  }).toList();

  // 美化表格输出

  // 动态计算列宽（最大条目长度 + 10）
  final maxEntryLength = entries.fold<int>(0, 
    (max, e) => e.length > max ? e.length : max);
  var colWidth = maxEntryLength + 3;

  // 精确计算说明行对齐
  final legend = '* : used,  @ : installed,  # : local';
  if ((colWidth * 3 + 2) < legend.length) {
    colWidth = legend.length ~/ 3 + 1;
  }

  final totalSpace = colWidth * 3 + 2; // 3列总字符数（62）
  final padding = totalSpace - legend.length;
  final leftPad = (padding / 2).floor();

  final borderLine = '+${'-' * colWidth}+${'-' * colWidth}+${'-' * colWidth}+';
  print(borderLine);
  print('|${' ' * leftPad}$legend${' ' * (padding - leftPad)}|');
  print(borderLine);

  // 分三列输出（修复多余空格）
  for (var i = 0; i < entries.length; i += 3) {
    final row = entries.sublist(i, i + 3 > entries.length ? entries.length : i + 3);
    final paddedRow = row.map((e) => e.padRight(colWidth)).toList();
    while (paddedRow.length < 3) {
      paddedRow.add(' ' * colWidth);
    }
    print('|${paddedRow[0]}|${paddedRow[1]}|${paddedRow[2]}|'); // 移除多余空格
    print(borderLine);
  }
}

// 通用安装逻辑
Future<void> installPackage(
    String section, String version, Config config) async {
  final url = config.get(section, version);
  if (url == null) {
    print('\nno version $version');
    return;
  }

  if (!url.startsWith('http') && !url.startsWith('https')) {
      print('$version 是本地安装，无需下载');
      return;
  }

  try {
    final cacheDir = Directory('cache/$section/$version');
    cacheDir.createSync(recursive: true);  // 目录创建
    final installDir = Directory('install/$section/$version');

    // 获取压缩包文件名
    final fileName = url.split('/').last;
    final cachedFile = File('${cacheDir.path}/$fileName');
    final client = http.Client();

    // 断点续传逻辑
    int downloadedBytes = 0;
    int totalBytes = 0;
    bool resumeSupported = false;
    bool needDownload = true;
    
    print('下载地址: $url');

    if (cachedFile.existsSync()) {
      downloadedBytes = cachedFile.lengthSync();
      print("发现缓存: ${cachedFile.absolute.path.replaceAll('/', '\\')}");

      // 完整文件检测, 并检查服务器是否支持断点续传
      try {
        final headResponse = await client.head(Uri.parse(url));
        totalBytes = int.parse(headResponse.headers['content-length'] ?? '0');
        resumeSupported = headResponse.headers['accept-ranges'] == 'bytes';
        
        if (resumeSupported && downloadedBytes < totalBytes) {
          print('尝试断点续传...');
        } else if (downloadedBytes == totalBytes) {
          print('文件已完整下载');
          needDownload = false;
        }
      } catch (e) {
        print('无法获取服务器信息: $e');
      }
    } else {
      print('保存路径: ${cachedFile.absolute.path.replaceAll('/', '\\')}');
    }

    final request = http.Request('GET', Uri.parse(url));
    if (resumeSupported && downloadedBytes > 0) {
      request.headers['Range'] = 'bytes=$downloadedBytes-';
    }

    if (needDownload) {
      try {
        final response = await client.send(request);
        totalBytes = (totalBytes == 0 || !resumeSupported) 
            ? response.contentLength ?? 0 
            : totalBytes;
        
        // 进度显示逻辑
        final startTime = DateTime.now().millisecondsSinceEpoch;
        int lastUpdate = 0;
        
        final output = cachedFile.openWrite(mode: 
            resumeSupported ? FileMode.writeOnlyAppend : FileMode.write);

        int currentDownloadBytes = 0;

        await response.stream.listen(
          (List<int> chunk) async {
            downloadedBytes += chunk.length;
            currentDownloadBytes += chunk.length;
            final now = DateTime.now().millisecondsSinceEpoch;
            
            // 每秒更新一次进度
            if (now - lastUpdate > 1000) {
              final elapsed = math.max(1, ((now - startTime) / 1000));
              final speed = currentDownloadBytes / elapsed;
              final percent = totalBytes > 0 
                  ? (downloadedBytes / totalBytes * 100).toStringAsFixed(1)
                  : '??';

              final displaySpeed = speed.isFinite ? speed.round() : 0;
              stdout.write('\r下载进度: $percent% | '
                  '${_formatBytes(downloadedBytes)} / ${_formatBytes(totalBytes)} | '
                  '${_formatBytes(displaySpeed)}/s  ');
              
              lastUpdate = now;
            }
            output.add(chunk);
          },
          onDone: () async {
            await output.flush();
            await output.close();
            stdout.write('\n');  // 换行结束进度条
          },
          onError: (e) {
            print('\n下载中断: $e');
            output.close();
          },
        ).asFuture();
      } finally {
        client.close();
      }
      print(" ");
    }

    // 新增文件类型识别
    final fileExtension = url.split('.').last.toLowerCase();

    var archive = Archive();
    print('将解压到 ${installDir.absolute.path.replaceAll('/', '\\')}');

    if (fileExtension == 'zip') {
      archive = ZipDecoder().decodeBytes(await cachedFile.readAsBytes());
    } else if (fileExtension == 'tgz' || fileExtension == 'gz') {
      final gzip = GZipDecoder().decodeBytes(await cachedFile.readAsBytes());
      archive = TarDecoder().decodeBytes(gzip);
    } else {
      throw Exception("不支持的压缩格式: $fileExtension");
    }

    await extractArchiveToDisk(archive, installDir.path);

    print('安装成功');

  } catch (e) {
    print('安装失败: $e');
  }
}

// 新增辅助方法格式化字节数
String _formatBytes(int bytes) {
  if (bytes <= 0) return "0 B";
  const suffixes = ["B", "KB", "MB", "GB"];
  final i = (math.log(bytes) / math.log(1024)).floor();
  return '${(bytes / math.pow(1024, i)).toStringAsFixed(1)} ${suffixes[i]}';
}

// 更新后的软链接创建方法
Future<String> useCommand(String section, String version, config) async {

  final url = config.get(section, version);
  if (url == null) {
    print('错误: 未找到版本 $version');
    return '';
  }

  String finalTargetPath = '';

  if (!url.startsWith('http') && !url.startsWith('https')) {
    // 新增多路径解析逻辑
    final cleanedPath = url.replaceAll('"', ''); // 去除引号
    final paths = cleanedPath.split(';')          // 按分号分割
        .map((p) => p.trim())                     // 去除两端空格
        .map((p) => p.replaceAll('/', Platform.pathSeparator)) // 统一路径格式
        .toList();
    
    print('本地路径: ${paths.join(';')}');

    // 检测路径是否存在
    // final validPaths = paths.where((p) => 
    //     Directory(p).existsSync() || File(p).existsSync()).toList();
    // if (validPaths.isEmpty) {
    //   print('错误: 所有本地路径均不存在 - ${paths.join(';')}');
    //   return;
    // }
    final validPaths = paths;

    try {
      final targetPaths = validPaths.join(';').replaceAllMapped(
          RegExp(r'(?<!\\)%'), (m) => '^%');
      unsetCommand(section, config);
      final userPath = _getUserPath().replaceAllMapped(
          RegExp(r'(?<!\\)%'), (m) => '^%');
      final newPath = userPath.isEmpty ? targetPaths : '$targetPaths;$userPath';
      print('newPath = $newPath');
      await setUserEnvironmentVariable('PATH', newPath);
      finalTargetPath = targetPaths.split(';').first;
      print('PATH += $targetPaths');
    } catch (e) {
      print('操作失败: $e');
    }
    return finalTargetPath;
  }

  final targetDir = Directory('install/$section/$version');

  // 安装状态检查
  if (!targetDir.existsSync()) {
    print('错误: 未安装版本 $version');
    return '';
  }

  // 查找最优的路径
  String findBestPath(Directory dir) {
    // 优先查找 bin 目录
    var current = dir;

    while (true) {
      final entries = current.listSync();
      final subDirs = entries.whereType<Directory>().toList();
      
      bool findBinDir = true;

      // 存在 bin 目录直接返回
      final binDir = subDirs.firstWhere(
        (d) => d.path.split(Platform.pathSeparator).last.toLowerCase() == 'bin',
        orElse: () {
          findBinDir = false;
          return targetDir;
        },
      );
    
      if (findBinDir) return binDir.absolute.path;

      // 没有 bin 则检查是否有多个子目录
      if (subDirs.length > 1 || entries.length > 1) {
        return current.absolute.path;
      }

      // 继续向下一级查找
      if (subDirs.isEmpty) break;
      current = subDirs.first;
    }
    // 最终回退到原始目录
    return dir.absolute.path;
  }

  try {
    final bestDir = findBestPath(targetDir);
  
    // 统一转换为 Windows 路径格式
    final targetPath = bestDir.replaceAll('/', '\\');

    unsetCommand(section, config);

    final userPath =
        _getUserPath().replaceAllMapped(RegExp(r'(?<!\\)%'), (m) => '^%');

    final newPath = userPath.isEmpty ? targetPath : '$targetPath;$userPath';
    await setUserEnvironmentVariable('PATH', newPath);
    finalTargetPath = targetPath.split(';').first;
    print('PATH += $targetPath');
  } catch (e) {
    print('操作失败: $e');
  }

  return finalTargetPath;
}
