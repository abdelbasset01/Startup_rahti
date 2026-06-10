import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;

class ProfileService {
  /// Uploads to Storage and returns the download URL. Throws on auth or Storage errors
  /// so the UI can show a real message instead of silently saving an empty profile.
  static Future<String> uploadProfilePicture(File imageFile) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('يجب تسجيل الدخول لرفع الصورة');
    }

    final String fileName = '${user.uid}_${DateTime.now().millisecondsSinceEpoch}.jpg';

    // Upload to Supabase bucket 'pfp'
    await Supabase.instance.client.storage
        .from('pfp')
        .upload(fileName, imageFile, fileOptions: const FileOptions(upsert: true));

    // Get public URL
    final String downloadUrl = Supabase.instance.client.storage
        .from('pfp')
        .getPublicUrl(fileName);
        
    return downloadUrl;
  }

  /// Writes the public image URL to Realtime Database under `users/{uid}/profileImage`.
  /// Uses per-field [set]/[remove] so the path is created even when a full `update` would fail.
  static Future<void> updateProfilePicture(String? imageUrl, bool isEnabled) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('يجب تسجيل الدخول لحفظ الصورة');
    }

    final DatabaseReference userRef =
        FirebaseDatabase.instance.ref().child('users').child(user.uid);

    final trimmed = imageUrl?.trim();
    if (trimmed != null && trimmed.isNotEmpty) {
      await userRef.child('profileImage').set(trimmed);
    } else {
      await userRef.child('profileImage').remove();
    }
    await userRef.child('isProfilePictureEnabled').set(isEnabled);

    if (trimmed != null && trimmed.isNotEmpty) {
      try {
        await user.updatePhotoURL(trimmed);
      } catch (_) {
        // RTDB remains the source of truth for in-app avatars.
      }
    }
  }
}
