import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'diagnostic_report.dart';

/// Manages local app-private diagnostic report storage.
///
/// Ensures reports are saved asynchronously in private sandbox storage.
/// Enforces storage bounds (max 15 reports) and rate-limiting / deduplication.
class DiagnosticStorage {
  static const int maxStoredReports = 15;
  static const Duration deduplicationWindow = Duration(seconds: 60);
  static const _channel = MethodChannel('veil_player/media');

  Directory? _reportsDirectory;

  Future<Directory> _getStorageDir() async {
    if (_reportsDirectory != null) return _reportsDirectory!;
    String? basePath;
    try {
      basePath = await _channel.invokeMethod<String>('getAppPrivateDirectory');
    } catch (_) {}

    basePath ??= Directory.systemTemp.path;
    final dir = Directory('$basePath/veil_diagnostics/reports');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _reportsDirectory = dir;
    return dir;
  }

  /// Saves a report to app-private storage asynchronously.
  /// Deduplicates identical recent reports within [deduplicationWindow].
  Future<DiagnosticReport?> saveReport(DiagnosticReport report) async {
    try {
      final dir = await _getStorageDir();

      // Check for deduplication with existing recent reports
      final existingReports = await loadAllReports();
      for (final existing in existingReports) {
        if (existing.type == report.type &&
            existing.errorCategory == report.errorCategory &&
            existing.exceptionMessage == report.exceptionMessage &&
            report.timestamp.difference(existing.timestamp).abs() < deduplicationWindow) {
          // Increment occurrence count of existing report
          final updatedReport = DiagnosticReport(
            id: existing.id,
            type: existing.type,
            timestamp: existing.timestamp,
            appVersion: existing.appVersion,
            buildNumber: existing.buildNumber,
            platform: existing.platform,
            deviceInfo: existing.deviceInfo,
            sessionInfo: existing.sessionInfo,
            playbackInfo: existing.playbackInfo,
            errorCategory: existing.errorCategory,
            exceptionMessage: existing.exceptionMessage,
            stackTrace: existing.stackTrace,
            recentEvents: report.recentEvents,
            userDescription: existing.userDescription,
            occurrenceCount: existing.occurrenceCount + 1,
          );

          await _writeReportFiles(dir, updatedReport);
          return updatedReport;
        }
      }

      // Write new report files
      await _writeReportFiles(dir, report);

      // Prune old reports if exceeding maxStoredReports limit
      await pruneOldReports();

      return report;
    } catch (e, stack) {
      debugPrint('[DiagnosticStorage] Error saving report: $e\n$stack');
      return null;
    }
  }

  /// Writes report text and JSON metadata files atomically.
  Future<void> _writeReportFiles(Directory dir, DiagnosticReport report) async {
    final textFile = File('${dir.path}/${report.id}.txt');
    final jsonFile = File('${dir.path}/${report.id}.json');

    final textContent = report.generateTextReport();
    final jsonContent = jsonEncode(report.toJson());

    await textFile.writeAsString(textContent, flush: true);
    await jsonFile.writeAsString(jsonContent, flush: true);
  }

  /// Loads all stored reports, ordered from newest to oldest.
  Future<List<DiagnosticReport>> loadAllReports() async {
    try {
      final dir = await _getStorageDir();
      final List<FileSystemEntity> entities = await dir.list().toList();

      final List<DiagnosticReport> reports = [];

      for (final entity in entities) {
        if (entity is File && entity.path.endsWith('.json')) {
          try {
            final content = await entity.readAsString();
            final json = jsonDecode(content) as Map<String, dynamic>;
            final report = DiagnosticReport.fromJson(json);
            reports.add(report);
          } catch (e) {
            debugPrint('[DiagnosticStorage] Failed parsing report json ${entity.path}: $e');
          }
        }
      }

      // Sort newest first
      reports.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      return reports;
    } catch (e) {
      debugPrint('[DiagnosticStorage] Error loading reports: $e');
      return [];
    }
  }

  /// Deletes a specific report by ID.
  Future<bool> deleteReport(String reportId) async {
    try {
      final dir = await _getStorageDir();
      final textFile = File('${dir.path}/$reportId.txt');
      final jsonFile = File('${dir.path}/$reportId.json');

      if (await textFile.exists()) await textFile.delete();
      if (await jsonFile.exists()) await jsonFile.delete();

      return true;
    } catch (e) {
      debugPrint('[DiagnosticStorage] Error deleting report $reportId: $e');
      return false;
    }
  }

  /// Deletes all diagnostic reports from app storage.
  Future<bool> deleteAllReports() async {
    try {
      final dir = await _getStorageDir();
      final entities = await dir.list().toList();
      for (final entity in entities) {
        if (entity is File) {
          await entity.delete();
        }
      }
      return true;
    } catch (e) {
      debugPrint('[DiagnosticStorage] Error deleting all reports: $e');
      return false;
    }
  }

  /// Gets the absolute path of a text report file for native sharing.
  Future<String?> getReportFilePath(String reportId) async {
    try {
      final dir = await _getStorageDir();
      final textFile = File('${dir.path}/$reportId.txt');
      if (await textFile.exists()) {
        return textFile.path;
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Enforces storage retention limits (deletes oldest reports when > maxStoredReports).
  Future<void> pruneOldReports() async {
    try {
      final reports = await loadAllReports();
      if (reports.length > maxStoredReports) {
        // Oldest reports are at the end of the sorted list
        final reportsToDelete = reports.sublist(maxStoredReports);
        for (final oldReport in reportsToDelete) {
          await deleteReport(oldReport.id);
        }
      }
    } catch (e) {
      debugPrint('[DiagnosticStorage] Error pruning old reports: $e');
    }
  }
}
