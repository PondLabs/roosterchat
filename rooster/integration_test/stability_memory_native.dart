import 'dart:io';

int? sampleMemoryBytes() => ProcessInfo.currentRss;

const memoryMetric = 'process_rss_bytes';

Map<String, Object?> sampleRenderEnvironment() => {
      'operating_system': Platform.operatingSystem,
      'operating_system_version': Platform.operatingSystemVersion,
      'logical_processors': Platform.numberOfProcessors,
    };
