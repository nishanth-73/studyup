import 'package:flutter/foundation.dart';

/// Compatibility default for older profile records that stored portrait IDs.
const String defaultAvatarId = 'avatar1';

/// Bundled PNG portrait catalogue (`assets/images/avatars/<id>.png`).
const List<String> bundledAvatarIds = [
  'avatar1',
  'avatar2',
  'avatar3',
  'avatar4',
  'avatar5',
  'avatar6',
];

/// True for a known bundled portrait id; unknown/legacy values fall back
/// to [defaultAvatarId] at render time instead of breaking.
bool isValidAvatarId(String avatarId) => bundledAvatarIds.contains(avatarId);
const int blobVariantCount = 4;
const int defaultBlobVariant = 0;

bool isValidBlobVariant(int variant) =>
    variant >= 0 && variant < blobVariantCount;

/// The StudyUp user profile: display name + Blob identity.
/// Single record today (`ownerId: 'local'`); the owner field keeps the door
/// open for multi-account without a storage migration.
///
/// First-launch funnel flags (all persisted here, one record):
/// [slidesSeen] (3 intro slides), [setupComplete] (Blob + name + goal),
/// [demoSignedIn] (temporary local demo auth until Supabase lands).
/// Legacy installs stored only [onboardingComplete]; missing flags migrate
/// to its value so old users are never re-prompted.
///
/// `blobName` is the stable identity seed (kept separate from [displayName]
/// so renaming never changes identity data). [avatarId], [blobShape], and
/// [blobShapeId] are retained when reading older saved profiles.
@immutable
class UserProfile {
  final String ownerId;
  final String displayName;
  final String blobName;
  final bool onboardingComplete;
  final int blobVariant;
  final String avatarId;
  final double? blobShape;
  final String? blobShapeId;
  final bool slidesSeen;
  final bool setupComplete;
  final bool demoSignedIn;
  final String demoEmail;

  const UserProfile({
    this.ownerId = 'local',
    required this.displayName,
    required this.blobName,
    this.onboardingComplete = true,
    this.blobVariant = defaultBlobVariant,
    this.avatarId = defaultAvatarId,
    this.blobShape,
    this.blobShapeId,
    this.slidesSeen = true,
    this.setupComplete = true,
    this.demoSignedIn = true,
    this.demoEmail = '',
  });

  UserProfile copyWith({
    String? ownerId,
    String? displayName,
    String? blobName,
    bool? onboardingComplete,
    int? blobVariant,
    String? avatarId,
    double? blobShape,
    String? blobShapeId,
    bool? slidesSeen,
    bool? setupComplete,
    bool? demoSignedIn,
    String? demoEmail,
  }) {
    return UserProfile(
      ownerId: ownerId ?? this.ownerId,
      displayName: displayName ?? this.displayName,
      blobName: blobName ?? this.blobName,
      onboardingComplete: onboardingComplete ?? this.onboardingComplete,
      blobVariant: blobVariant ?? this.blobVariant,
      avatarId: avatarId ?? this.avatarId,
      blobShape: blobShape ?? this.blobShape,
      blobShapeId: blobShapeId ?? this.blobShapeId,
      slidesSeen: slidesSeen ?? this.slidesSeen,
      setupComplete: setupComplete ?? this.setupComplete,
      demoSignedIn: demoSignedIn ?? this.demoSignedIn,
      demoEmail: demoEmail ?? this.demoEmail,
    );
  }

  Map<String, Object?> toJson() => {
    'ownerId': ownerId,
    'displayName': displayName,
    'blobName': blobName,
    'onboardingComplete': onboardingComplete,
    'blobVariant': blobVariant,
    'avatarId': avatarId,
    if (blobShape != null) 'blobShape': blobShape,
    if (blobShapeId != null) 'blobShapeId': blobShapeId,
    'slidesSeen': slidesSeen,
    'setupComplete': setupComplete,
    'demoSignedIn': demoSignedIn,
    'demoEmail': demoEmail,
  };

  factory UserProfile.fromJson(Map<String, Object?> json) {
    // Migration: records saved before the funnel flags existed treated
    // onboardingComplete as the single gate — carry it over so legacy
    // users land straight in the app.
    final complete = json['onboardingComplete'] as bool? ?? true;
    final variant = (json['blobVariant'] as num?)?.toInt();
    return UserProfile(
      ownerId: json['ownerId'] as String? ?? 'local',
      displayName: json['displayName']! as String,
      blobName: json['blobName']! as String,
      onboardingComplete: complete,
      blobVariant: variant != null && isValidBlobVariant(variant)
          ? variant
          : defaultBlobVariant,
      avatarId: json['avatarId'] as String? ?? defaultAvatarId,
      blobShape: (json['blobShape'] as num?)?.toDouble(),
      blobShapeId: json['blobShapeId'] as String?,
      slidesSeen: json['slidesSeen'] as bool? ?? complete,
      setupComplete: json['setupComplete'] as bool? ?? complete,
      demoSignedIn: json['demoSignedIn'] as bool? ?? complete,
      demoEmail: json['demoEmail'] as String? ?? '',
    );
  }
}
