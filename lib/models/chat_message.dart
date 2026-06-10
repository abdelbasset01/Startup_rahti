class ChatMessage {
  final String id;
  final String senderId;
  final String senderName;
  final String message;
  final int timestamp;
  final String status; // 'sent', 'delivered', 'read'
  final bool isSystemMessage;

  ChatMessage({
    required this.id,
    required this.senderId,
    required this.senderName,
    required this.message,
    required this.timestamp,
    this.status = 'sent',
    this.isSystemMessage = false,
  });

  factory ChatMessage.fromMap(Map<dynamic, dynamic> data, String id) {
    return ChatMessage(
      id: id,
      senderId: data['senderId']?.toString() ?? '',
      senderName: data['senderName']?.toString() ?? '',
      message: data['message']?.toString() ?? '',
      timestamp: (data['timestamp'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
      status: data['status']?.toString() ?? 'sent',
      isSystemMessage: data['isSystemMessage'] == true,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'senderId': senderId,
      'senderName': senderName,
      'message': message,
      'timestamp': timestamp,
      'status': status,
      'isSystemMessage': isSystemMessage,
    };
  }
}
