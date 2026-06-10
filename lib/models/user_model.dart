
class UserModel {
  final String uid;
  final String name;
  final String firstName;
  final String lastName;
  final String? email;
  final String? phone;
  final String role; // passenger / driver
  final String? profileImage;
  final int createdAt;
  final bool isOnline;
  final String loginId;
  final String? password;
  final int updatedAt;

  // Passenger specific
  final bool isStudent;
  final String? studentCardURL;

  // Driver specific
  final String? gender;
  final Map<dynamic, dynamic>? vehicle;

  UserModel({
    required this.uid,
    required this.name,
    required this.firstName,
    required this.lastName,
    this.email,
    this.phone,
    required this.role,
    this.profileImage,
    required this.createdAt,
    this.isOnline = true,
    required this.loginId,
    this.password,
    required this.updatedAt,
    this.isStudent = false,
    this.studentCardURL,
    this.gender,
    this.vehicle,
  });

  factory UserModel.fromMap(String uid, Map<dynamic, dynamic> map) {
    return UserModel(
      uid: uid,
      name: map['name'] ?? '',
      firstName: map['firstName'] ?? '',
      lastName: map['lastName'] ?? '',
      email: map['email'],
      phone: map['phone'],
      role: map['role'] ?? 'passenger',
      profileImage: map['profileImage'],
      createdAt: map['createdAt'] ?? DateTime.now().millisecondsSinceEpoch,
      isOnline: map['isOnline'] ?? false,
      loginId: map['loginId'] ?? '',
      password: map['password'],
      updatedAt: map['updatedAt'] ?? DateTime.now().millisecondsSinceEpoch,
      isStudent: map['isStudent'] ?? false,
      studentCardURL: map['studentCardURL'],
      gender: map['gender'],
      vehicle: map['vehicle'] != null ? Map<dynamic, dynamic>.from(map['vehicle']) : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'firstName': firstName,
      'lastName': lastName,
      'email': email,
      'phone': phone,
      'role': role,
      'profileImage': profileImage,
      'createdAt': createdAt,
      'isOnline': isOnline,
      'loginId': loginId,
      'password': password,
      'updatedAt': updatedAt,
      'isStudent': isStudent,
      'studentCardURL': studentCardURL,
      'gender': gender,
      'vehicle': vehicle,
    };
  }
}
