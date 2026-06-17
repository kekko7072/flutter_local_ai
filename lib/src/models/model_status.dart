enum ModelFeatureStatus {
  available,
  unavailable,
  downloading,
  downloadable,
  unknown,
}

ModelFeatureStatus modelFeatureStatusFromString(String? value) {
  switch (value) {
    case 'available':
      return ModelFeatureStatus.available;
    case 'unavailable':
      return ModelFeatureStatus.unavailable;
    case 'downloading':
      return ModelFeatureStatus.downloading;
    case 'downloadable':
      return ModelFeatureStatus.downloadable;
    default:
      return ModelFeatureStatus.unknown;
  }
}

enum ModelDownloadStatusType {
  started,
  progress,
  completed,
  failed,
  unknown,
}

class ModelDownloadStatus {
  final ModelDownloadStatusType type;
  final int? totalBytesDownloaded;
  final String? errorMessage;

  const ModelDownloadStatus({
    required this.type,
    this.totalBytesDownloaded,
    this.errorMessage,
  });

  factory ModelDownloadStatus.fromMap(Map<String, dynamic> map) {
    final status = map['status']?.toString();
    switch (status) {
      case 'started':
        return const ModelDownloadStatus(type: ModelDownloadStatusType.started);
      case 'progress':
        return ModelDownloadStatus(
          type: ModelDownloadStatusType.progress,
          totalBytesDownloaded: (map['totalBytesDownloaded'] as num?)?.toInt(),
        );
      case 'completed':
        return const ModelDownloadStatus(
            type: ModelDownloadStatusType.completed);
      case 'failed':
        return ModelDownloadStatus(
          type: ModelDownloadStatusType.failed,
          errorMessage: map['errorMessage']?.toString(),
        );
      default:
        return const ModelDownloadStatus(type: ModelDownloadStatusType.unknown);
    }
  }
}
