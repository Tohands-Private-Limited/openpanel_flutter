import 'package:equatable/equatable.dart';

class UpdateProfilePayload extends Equatable {
  final String profileId;
  final String? firstName;
  final String? lastName;
  final String? avatar;
  final String? email;
  final Map<String, dynamic> properties;

  const UpdateProfilePayload({
    required this.profileId,
    this.firstName,
    this.lastName,
    this.avatar,
    this.email,
    this.properties = const {},
  });

  factory UpdateProfilePayload.fromJson(Map<String, dynamic> json) {
    return UpdateProfilePayload(
      profileId: json['profileId'],
      firstName: json['firstName'],
      lastName: json['lastName'],
      avatar: json['avatar'],
      email: json['email'],
      properties: json['properties'],
    );
  }

  Map<String, dynamic> toJson() {
    // Omit null optional fields — the server's Zod schema uses .optional()
    // which accepts absent keys but rejects explicit null values.
    return {
      'profileId': profileId,
      if (firstName != null) 'firstName': firstName,
      if (lastName != null) 'lastName': lastName,
      if (avatar != null) 'avatar': avatar,
      if (email != null) 'email': email,
      'properties': properties,
    };
  }

  @override
  List<Object?> get props =>
      [profileId, firstName, lastName, avatar, email, properties];
}
