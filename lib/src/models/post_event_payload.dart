import 'package:equatable/equatable.dart';

class PostEventPayload extends Equatable {
  final String name;
  final String? deviceId;
  final String? profileId;
  final Map<String, dynamic> properties;

  const PostEventPayload({
    required this.name,
    this.deviceId,
    this.profileId,
    this.properties = const {},
  });

  factory PostEventPayload.fromJson(Map<String, dynamic> json) {
    return PostEventPayload(
      name: json['name'],
      deviceId: json['deviceId'],
      profileId: json['profileId'],
      properties: json['properties'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'deviceId': deviceId,
      // Omit profileId when null (logged-out) — server resolves via deviceId.
      if (profileId != null) 'profileId': profileId,
      'properties': properties,
    };
  }

  @override
  List<Object?> get props => [name, deviceId, profileId, properties];
}
