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

  factory DvrProfile.fromJson(Map<String, dynamic> json) => DvrProfile(
        id: json['id'] as String,
        name: json['name'] as String,
        host: json['host'] as String,
        rtspPort: (json['rtspPort'] as num).toInt(),
        username: json['username'] as String,
        channelCount: (json['channelCount'] as num).toInt(),
      );

  @override
  List<Object?> get props => [id, name, host, rtspPort, username, channelCount];
}
