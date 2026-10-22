import 'package:equatable/equatable.dart';

/// A single DVR/NVR connection profile. Password is NOT stored here —
/// see [ProfileStore], which keeps it in secure storage keyed by [id].
class DvrProfile extends Equatable {
  final String id;
  final String name;
  final String host;
  final int rtspPort;
  final String username;
  final int channelCount;

  const DvrProfile({
    required this.id,
    required this.name,
    required this.host,
    required this.rtspPort,
    required this.username,
    required this.channelCount,
  });

  DvrProfile copyWith({
    String? name,
    String? host,
    int? rtspPort,
    String? username,
    int? channelCount,
  }) {
    return DvrProfile(
      id: id,
      name: name ?? this.name,
      host: host ?? this.host,
      rtspPort: rtspPort ?? this.rtspPort,
      username: username ?? this.username,
      channelCount: channelCount ?? this.channelCount,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'host': host,
        'rtspPort': rtspPort,
        'username': username,
        'channelCount': channelCount,
      };

  /// Decodes one persisted record.
  ///
  /// Throws [FormatException] for records missing required fields or carrying
  /// invalid ports/channel counts. [ProfileStore.loadProfiles] catches it and
  /// skips just that record instead of bricking the whole list.
  factory DvrProfile.fromJson(Map<String, dynamic> json) {
    String requireString(String key) {
      final value = json[key];
      if (value is! String || value.trim().isEmpty) {
        throw FormatException('Invalid or missing "$key"');
      }
      return value;
    }

    int requireInt(String key) {
      final value = json[key];
      if (value is! num) {
        throw FormatException('Invalid or missing "$key"');
      }
      return value.toInt();
    }

    final rtspPort = requireInt('rtspPort');
    if (rtspPort < 1 || rtspPort > 65535) {
      throw FormatException('rtspPort out of range: $rtspPort');
    }
    final channelCount = requireInt('channelCount');
    if (channelCount < 1) {
      throw const FormatException('channelCount must be positive');
    }
    return DvrProfile(
      id: requireString('id'),
      name: requireString('name'),
      host: requireString('host'),
      rtspPort: rtspPort,
      username: requireString('username'),
      channelCount: channelCount,
    );
  }

  @override
  List<Object?> get props => [id, name, host, rtspPort, username, channelCount];
}
