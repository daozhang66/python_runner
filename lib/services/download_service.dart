import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// 文件下载服务（单例）
///
/// 使用 Dio 库实现高性能下载，支持：
/// - 长超时（30分钟）
/// - 精确进度回调
/// - 取消下载
/// - 断点续传（可选）
class DownloadService {
  DownloadService._();
  static final DownloadService instance = DownloadService._();
  factory DownloadService() => instance;

  late final Dio _dio;

  /// 初始化下载专用 Dio 实例
  void initialize() {
    _dio = Dio(BaseOptions(
      receiveTimeout: const Duration(minutes: 30),
      sendTimeout: const Duration(minutes: 5),
      connectTimeout: const Duration(seconds: 30),
    ));
    debugPrint('[DownloadService] 初始化完成');
  }

  /// 下载文件到本地
  ///
  /// [url] 下载地址
  /// [savePath] 保存路径（绝对路径）
  /// [onProgress] 进度回调 (received, total)
  /// [cancelToken] 取消令牌
  Future<void> download({
    required String url,
    required String savePath,
    required void Function(int received, int total) onProgress,
    CancelToken? cancelToken,
  }) async {
    await _dio.download(
      url,
      savePath,
      onReceiveProgress: onProgress,
      cancelToken: cancelToken,
      options: Options(
        followRedirects: true,
        maxRedirects: 5,
        receiveTimeout: const Duration(minutes: 30),
      ),
    );
  }

  /// 支持断点续传的下载（可选功能）
  ///
  /// 检查已下载大小，从断点处继续下载
  Future<void> downloadWithResume({
    required String url,
    required String savePath,
    required void Function(int received, int total) onProgress,
    CancelToken? cancelToken,
  }) async {
    // TODO: 实现断点续传
    // 1. 检查文件是否已存在
    // 2. 获取已下载大小
    // 3. 设置 Range header
    // 4. 追加写入文件

    // 暂时使用普通下载
    await download(
      url: url,
      savePath: savePath,
      onProgress: onProgress,
      cancelToken: cancelToken,
    );
  }

  /// 获取 Dio 实例（用于自定义配置）
  Dio get dio => _dio;
}
