import 'dart:io';

int? sampleMemoryBytes() => ProcessInfo.currentRss;

const memoryMetric = 'process_rss_bytes';
