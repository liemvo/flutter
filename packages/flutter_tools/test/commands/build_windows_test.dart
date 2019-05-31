// Copyright 2019 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:file/memory.dart';
import 'package:flutter_tools/src/base/common.dart';
import 'package:flutter_tools/src/base/file_system.dart';
import 'package:flutter_tools/src/base/io.dart';
import 'package:flutter_tools/src/base/platform.dart';
import 'package:flutter_tools/src/cache.dart';
import 'package:flutter_tools/src/commands/build.dart';
import 'package:mockito/mockito.dart';
import 'package:process/process.dart';
import 'package:xml/xml.dart' as xml;

import '../src/common.dart';
import '../src/context.dart';
import '../src/mocks.dart';

void main() {
  Cache.disableLocking();
  final MockProcessManager mockProcessManager = MockProcessManager();
  final MemoryFileSystem memoryFilesystem = MemoryFileSystem(style: FileSystemStyle.windows);
  final MockProcess mockProcess = MockProcess();
  final MockPlatform windowsPlatform = MockPlatform()
      ..environment['PROGRAMFILES(X86)'] = r'C:\Program Files (x86)\';
  final MockPlatform notWindowsPlatform = MockPlatform();
  const String solutionPath = r'C:\windows\Runner.sln';
  const String visualStudioPath = r'C:\Program Files (x86)\Microsoft Visual Studio\2017\Community';
  const String vcvarsPath = visualStudioPath + r'\VC\Auxiliary\Build\vcvars64.bat';

  when(mockProcess.exitCode).thenAnswer((Invocation invocation) async {
    return 0;
  });
  when(mockProcess.stderr).thenAnswer((Invocation invocation) {
    return const Stream<List<int>>.empty();
  });
  when(mockProcess.stdout).thenAnswer((Invocation invocation) {
    return const Stream<List<int>>.empty();
  });
  when(windowsPlatform.isWindows).thenReturn(true);
  when(notWindowsPlatform.isWindows).thenReturn(false);

  // Sets up the mock environment so that lookup of vcvars64.bat will succeed.
  void enableVcvarsMocking() {
    const String vswherePath = r'C:\Program Files (x86)\Microsoft Visual Studio\Installer\vswhere.exe';
    fs.file(vswherePath).createSync(recursive: true);
    fs.file(vcvarsPath).createSync(recursive: true);

    final MockProcessResult result = MockProcessResult();
    when(result.exitCode).thenReturn(0);
    when<String>(result.stdout).thenReturn(visualStudioPath);
    when(mockProcessManager.run(<String>[
      vswherePath,
      '-latest',
      '-requires', 'Microsoft.VisualStudio.Workload.NativeDesktop',
      '-property', 'installationPath',
    ])).thenAnswer((Invocation invocation) async {
      return result;
    });
  }

  testUsingContext('Windows build fails when there is no vcvars64.bat', () async {
    final BuildCommand command = BuildCommand();
    applyMocksToCommand(command);
    fs.file(solutionPath).createSync(recursive: true);
    expect(createTestCommandRunner(command).run(
      const <String>['build', 'windows']
    ), throwsA(isInstanceOf<ToolExit>()));
  }, overrides: <Type, Generator>{
    Platform: () => windowsPlatform,
    FileSystem: () => memoryFilesystem,
  });

  testUsingContext('Windows build fails when there is no windows project', () async {
    final BuildCommand command = BuildCommand();
    applyMocksToCommand(command);
    enableVcvarsMocking();
    expect(createTestCommandRunner(command).run(
      const <String>['build', 'windows']
    ), throwsA(isInstanceOf<ToolExit>()));
  }, overrides: <Type, Generator>{
    Platform: () => windowsPlatform,
    FileSystem: () => memoryFilesystem,
  });

  testUsingContext('Windows build fails on non windows platform', () async {
    final BuildCommand command = BuildCommand();
    applyMocksToCommand(command);
    fs.file(solutionPath).createSync(recursive: true);
    enableVcvarsMocking();
    fs.file('pubspec.yaml').createSync();
    fs.file('.packages').createSync();

    expect(createTestCommandRunner(command).run(
      const <String>['build', 'windows']
    ), throwsA(isInstanceOf<ToolExit>()));
  }, overrides: <Type, Generator>{
    Platform: () => notWindowsPlatform,
    FileSystem: () => memoryFilesystem,
  });

  testUsingContext('Windows build invokes msbuild and writes generated files', () async {
    final BuildCommand command = BuildCommand();
    applyMocksToCommand(command);
    fs.file(solutionPath).createSync(recursive: true);
    enableVcvarsMocking();
    fs.file('pubspec.yaml').createSync();
    fs.file('.packages').createSync();

    when(mockProcessManager.start(<String>[
      r'C:\packages\flutter_tools\bin\vs_build.bat',
      vcvarsPath,
      fs.path.basename(solutionPath),
      'Release',
    ], workingDirectory: fs.path.dirname(solutionPath))).thenAnswer((Invocation invocation) async {
      return mockProcess;
    });

    await createTestCommandRunner(command).run(
      const <String>['build', 'windows']
    );

    // Spot-check important elements from the properties file.
    final File propsFile = fs.file(r'C:\windows\flutter\Generated.props');
    expect(propsFile.existsSync(), true);
    final xml.XmlDocument props = xml.parse(propsFile.readAsStringSync());
    expect(props.findAllElements('PropertyGroup').first.getAttribute('Label'), 'UserMacros');
    expect(props.findAllElements('ItemGroup').length, 1);
    expect(props.findAllElements('FLUTTER_ROOT').first.text, r'C:\');
  }, overrides: <Type, Generator>{
    FileSystem: () => memoryFilesystem,
    ProcessManager: () => mockProcessManager,
    Platform: () => windowsPlatform,
  });
}

class MockProcessManager extends Mock implements ProcessManager {}
class MockProcess extends Mock implements Process {}
class MockProcessResult extends Mock implements ProcessResult {}
class MockPlatform extends Mock implements Platform {
  @override
  Map<String, String> environment = <String, String>{
    'FLUTTER_ROOT': r'C:\',
  };
}
