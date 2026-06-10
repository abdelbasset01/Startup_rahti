import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';

class UserProfileAvatar extends StatelessWidget {
  final String userId;
  final double radius;

  const UserProfileAvatar({super.key, required this.userId, this.radius = 20});

  @override
  Widget build(BuildContext context) {
    if (userId.isEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: const Color(0xFF43C59E),
        child: Icon(Icons.person, size: radius * 1.2, color: Colors.white),
      );
    }
    return StreamBuilder<DatabaseEvent>(
      stream: FirebaseDatabase.instance.ref().child('users').child(userId).onValue,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          if (kDebugMode) {
            debugPrint('UserProfileAvatar: ${snapshot.error}');
          }
          return _buildFallback();
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildFallback();
        }

        final raw = snapshot.data?.snapshot.value;
        if (raw is! Map) {
          return _buildFallback();
        }

        final data = raw as Map<dynamic, dynamic>;
        final isEnabled = data['isProfilePictureEnabled'] == true;
        final rawImage = data['profileImage'];
        final imageUrl = rawImage == null ? '' : rawImage.toString().trim();
        final hasImage = imageUrl.isNotEmpty && isEnabled;

        if (!hasImage) {
          return _buildFallback();
        }

        return ClipOval(
          child: Container(
            width: radius * 2,
            height: radius * 2,
            color: const Color(0xFF43C59E),
            child: Image.network(
              imageUrl,
              fit: BoxFit.cover,
              width: radius * 2,
              height: radius * 2,
              loadingBuilder: (context, child, loadingProgress) {
                if (loadingProgress == null) return child;
                return Center(
                  child: SizedBox(
                    width: radius,
                    height: radius,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                      value: loadingProgress.expectedTotalBytes != null
                          ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                          : null,
                    ),
                  ),
                );
              },
              errorBuilder: (context, error, stackTrace) {
                return Icon(Icons.person, size: radius * 1.2, color: Colors.white);
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildFallback() {
    return CircleAvatar(
      radius: radius,
      backgroundColor: const Color(0xFF43C59E),
      child: Icon(Icons.person, size: radius * 1.2, color: Colors.white),
    );
  }
}
