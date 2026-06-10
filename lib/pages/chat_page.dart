import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import '../models/chat_message.dart';
import '../services/chat_service.dart';
import '../services/trip_service.dart';
import 'dart:async';
import '../widgets/user_profile_avatar.dart';

class ChatPage extends StatefulWidget {
  final String tripId;
  final String route;
  final String driverName;

  const ChatPage({
    super.key,
    required this.tripId,
    required this.route,
    required this.driverName,
  });

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final TextEditingController _messageController = TextEditingController();
  final ChatService _chatService = ChatService();
  final String _currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';
  bool _isRemovedFromChat = false;
  
  String _currentUserName = 'مستخدم';
  String? _driverId;
  Timer? _typingTimer;
  
  late Stream<List<ChatMessage>> _messagesStream;
  late Stream<bool> _typingStream;
  late Stream<DatabaseEvent> _tripStatusStream;
  late Stream<DatabaseEvent> _tripParticipantsStream;
  StreamSubscription<DatabaseEvent>? _myChatStatusSub;
  Map<String, String> _userRoles = {};
  List<Map<String, dynamic>> _latestParticipants = const [];

  bool _isDeliverySeat(Map<String, dynamic> seat) {
    final transportType = seat['transportType']?.toString().trim().toLowerCase();
    final packageType = seat['packageType']?.toString().trim();
    final hasPackageType = packageType != null && packageType.isNotEmpty;

    return seat['isDelivery'] == true ||
        transportType == 'package' ||
        hasPackageType;
  }

  @override
  void initState() {
    super.initState();
    _fetchCurrentUserName();
    _fetchDriverId();
    _chatService.markMessagesAsRead(widget.tripId, _currentUserId);
    
    _messagesStream = _chatService.getMessagesStream(widget.tripId, _currentUserId).asBroadcastStream();
    _typingStream = _chatService.getAnyTypingStatus(widget.tripId, _currentUserId).asBroadcastStream();
    _tripStatusStream = FirebaseDatabase.instance.ref().child('trips').child(widget.tripId).child('status').onValue.asBroadcastStream();
    _tripParticipantsStream = FirebaseDatabase.instance.ref().child('trips').child(widget.tripId).onValue.asBroadcastStream();

    // If a passenger was removed by the driver, `chatStatus/{userId}` is set to `removed`.
    // In that case we must disable sending messages and hide the rating card.
    if (_currentUserId.isNotEmpty) {
      _loadInitialRemovedState();
      _myChatStatusSub = FirebaseDatabase.instance
          .ref()
          .child('trips')
          .child(widget.tripId)
          .child('chatStatus')
          .child(_currentUserId)
          .onValue
          .listen((event) {
        final status = event.snapshot.value?.toString();
        final isDeleted = status == 'deleted' || status == 'removed';
        if (!mounted) return;
        if (_isRemovedFromChat != isDeleted) {
          setState(() => _isRemovedFromChat = isDeleted);
        }
      });
    }

    _tripParticipantsStream.listen((event) {
      if (event.snapshot.exists && event.snapshot.value != null && mounted) {
        final participants = _extractTripParticipants(event.snapshot.value);
        final newRoles = <String, String>{};
        for (final seat in participants) {
          final passengerId = seat['userId']?.toString();
          if (passengerId != null) {
            final isDelivery = _isDeliverySeat(seat);
            newRoles[passengerId] = isDelivery ? "مرسل طرد" : "مسافر";
          }
        }
        if (mounted) {
          setState(() {
            _userRoles = newRoles;
            _latestParticipants = participants;
          });
        }
      }
    });
  }

  List<Map<String, dynamic>> _extractTripParticipants(dynamic tripRaw) {
    if (tripRaw is! Map) return const [];
    final tripData = Map<dynamic, dynamic>.from(tripRaw);
    final participants = <Map<String, dynamic>>[];
    final chatStatusRaw = tripData['chatStatus'];
    final chatStatus =
        chatStatusRaw is Map ? Map<dynamic, dynamic>.from(chatStatusRaw) : null;

    void addFromMap(dynamic sourceRaw, String sourceType) {
      if (sourceRaw is! Map) return;
      final source = Map<dynamic, dynamic>.from(sourceRaw);
      for (final entry in source.entries) {
        if (entry.value is! Map) continue;
        final seat = Map<String, dynamic>.from(Map<dynamic, dynamic>.from(entry.value as Map));
        seat['seatKey'] = entry.key.toString();
        seat['sourceType'] = sourceType;

        // Normalize old schema (trips/seats -> reservedBy) to current one (userId).
        seat['userId'] = seat['userId']?.toString() ?? seat['reservedBy']?.toString() ?? '';
        if ((seat['userName'] == null || seat['userName'].toString().trim().isEmpty) &&
            seat['username'] != null) {
          seat['userName'] = seat['username'];
        }
        participants.add(seat);
      }
    }

    addFromMap(tripData['takenSeats'], 'takenSeats');
    addFromMap(tripData['seats'], 'seats');

    participants.sort((a, b) {
      final aTs = (a['bookingTime'] as num?)?.toInt() ??
          (a['timestamp'] as num?)?.toInt() ??
          0;
      final bTs = (b['bookingTime'] as num?)?.toInt() ??
          (b['timestamp'] as num?)?.toInt() ??
          0;
      return bTs.compareTo(aTs);
    });

    // Deduplicate so each passenger only shows once
    final uniqueParticipants = <Map<String, dynamic>>[];
    final seenUserIds = <String>{};
    for (final p in participants) {
      final uid = p['userId']?.toString() ?? '';
      final userName = p['userName']?.toString() ?? p['username']?.toString() ?? '';
      final dedupKey = uid.isNotEmpty ? uid : userName;

      if (dedupKey.isNotEmpty && seenUserIds.contains(dedupKey)) {
        continue;
      }
      if (dedupKey.isNotEmpty) {
        // If driver removed this passenger from chat, hide it from the admin list.
        final isDeleted = chatStatus != null &&
            chatStatus[dedupKey] != null &&
            (chatStatus[dedupKey].toString() == 'deleted' ||
                chatStatus[dedupKey].toString() == 'removed');
        if (isDeleted) {
          continue;
        }
        seenUserIds.add(dedupKey);
      }
      uniqueParticipants.add(p);
    }

    return uniqueParticipants;
  }

  @override
  void dispose() {
    _messageController.dispose();
    _typingTimer?.cancel();
    _myChatStatusSub?.cancel();
    _chatService.setTypingStatus(widget.tripId, _currentUserId, false);
    super.dispose();
  }

  Future<void> _fetchDriverId() async {
    final snap = await FirebaseDatabase.instance.ref().child('trips').child(widget.tripId).child('driverId').get();
    if (snap.exists && mounted) {
      setState(() {
        _driverId = snap.value?.toString();
      });
    }
  }

  Future<void> _fetchCurrentUserName() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final snap = await FirebaseDatabase.instance.ref().child('users').child(user.uid).get();
      if (snap.exists) {
        final data = snap.value as Map<dynamic, dynamic>;
        setState(() {
          _currentUserName = "${data['firstName'] ?? ''} ${data['lastName'] ?? ''}".trim();
          if (_currentUserName.isEmpty) {
            _currentUserName = data['name'] ?? "مستخدم";
          }
        });
      }
    }
  }

  void _onMessageChanged(String text) {
    _chatService.setTypingStatus(widget.tripId, _currentUserId, text.isNotEmpty);
    
    // Automatically stop after 3 seconds of no typing
    _typingTimer?.cancel();
    _typingTimer = Timer(const Duration(seconds: 3), () {
      _chatService.setTypingStatus(widget.tripId, _currentUserId, false);
    });
  }

  void _sendMessage() async {
    // Removed passengers can't send on this trip chat anymore.
    if (_isRemovedFromChat) return;
    final messageText = _messageController.text;
    _messageController.clear();
    _chatService.setTypingStatus(widget.tripId, _currentUserId, false);
    
    if (messageText.trim().isNotEmpty) {
      await _chatService.sendMessage(
        widget.tripId,
        _currentUserId,
        _currentUserName,
        messageText,
      );
    }
  }

  Future<void> _loadInitialRemovedState() async {
    try {
      final snap = await FirebaseDatabase.instance
          .ref()
          .child('trips')
          .child(widget.tripId)
          .child('chatStatus')
          .child(_currentUserId)
          .get();
      if (!mounted) return;
      setState(() {
        final status = snap.value?.toString();
        _isRemovedFromChat = status == 'deleted' || status == 'removed';
      });
    } catch (_) {
      // If status can't be loaded, fall back to listener updates.
    }
  }

  String _formatTime(DateTime timestamp) {
    return "${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}";
  }

  Widget _buildOnlineStatus() {
    if (_driverId == null || _driverId == _currentUserId) {
      return const SizedBox.shrink(); // Hide if I am driver or not yet loaded
    }
    return StreamBuilder<bool>(
      stream: _chatService.getUserOnlineStatus(_driverId!),
      builder: (context, snapshot) {
        final isOnline = snapshot.data ?? false;
        return Text(
          isOnline ? "متصل الآن" : "غير متصل",
          style: TextStyle(
            fontSize: 12,
            color: isOnline ? Colors.greenAccent.shade100 : Colors.white70,
            fontWeight: FontWeight.w600,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.route,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontSize: 16, 
                color: Colors.white,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Row(
              children: [
                Flexible(
                  child: Text(
                    "السائق: ${widget.driverName}",
                    style: const TextStyle(fontSize: 12, color: Colors.white70),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (_driverId != null)
                  StreamBuilder<DatabaseEvent>(
                    stream: FirebaseDatabase.instance.ref().child('users').child(_driverId!).onValue,
                    builder: (context, snapshot) {
                      final userData = snapshot.data?.snapshot.value as Map<dynamic, dynamic>? ?? {};
                      final rating = (userData['rating'] as num?)?.toDouble() ?? 0.0;
                      final ratingCount = (userData['ratingCount'] as num?)?.toInt() ?? 0;
                      return Text(
                        "  ⭐ ${rating.toStringAsFixed(1)} ($ratingCount)",
                        style: const TextStyle(fontSize: 12, color: Colors.amberAccent),
                      );
                    },
                  ),
                const SizedBox(width: 8),
                _buildOnlineStatus(),
              ],
            ),
          ],
        ),
        backgroundColor: const Color(0xFF43C59E),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (_driverId != null && _driverId == _currentUserId)
            StreamBuilder<DatabaseEvent>(
              stream: _tripStatusStream,
              builder: (context, snapshot) {
                final status = snapshot.data?.snapshot.value?.toString();
                if (status != 'completed' && status != 'archived' && status != 'finished') {
                  return Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.people, color: Colors.white),
                        tooltip: 'قائمة الركاب',
                        onPressed: _showPassengersList,
                      ),
                      TextButton(
                        onPressed: () async {
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              title: const Text("إنهاء الرحلة"),
                              content: const Text("هل أنت متأكد أنك تريد إنهاء الرحلة؟", textAlign: TextAlign.center),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx, false),
                                  child: const Text("إلغاء", style: TextStyle(color: Colors.grey)),
                                ),
                                ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.red,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                  onPressed: () => Navigator.pop(ctx, true),
                                  child: const Text("إنهاء", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                ),
                              ],
                            ),
                          );
                          
                          if (confirm != true) return;

                          try {
                            await tripService.finishTrip(widget.tripId, _currentUserId);
                            if (!context.mounted) return;
                            if (Navigator.of(context).canPop()) {
                              Navigator.pop(context);
                            } else {
                              Navigator.pushReplacementNamed(context, '/messages');
                            }
                          } catch (e) {
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text("فشل إنهاء الرحلة: $e")),
                            );
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text("إنهاء الرحلة", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 12)),
                        ),
                      ),
                    ],
                  );
                }
                return const SizedBox.shrink();
              }
            ),
              const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<List<ChatMessage>>(
              stream: _messagesStream,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: Color(0xFF43C59E)));
                }

                if (snapshot.hasError) {
                  return Center(child: Text("خطأ: ${snapshot.error}"));
                }

                final messages = snapshot.data ?? [];

                // Side effect: Mark as read if any new message came in
                if (messages.any((m) => m.senderId != _currentUserId && m.status != 'read')) {
                   WidgetsBinding.instance.addPostFrameCallback((_) {
                      _chatService.markMessagesAsRead(widget.tripId, _currentUserId);
                   });
                }

                if (messages.isEmpty) {
                  return const Center(
                    child: Text(
                      "لا توجد رسائل بعد. قُل مرحباً!",
                      style: TextStyle(color: Colors.grey, fontSize: 16),
                    ),
                  );
                }

                return ListView.builder(
                  reverse: true, // Auto-scrolls to the bottom natively
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 20),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final message = messages[index];
                    final isMe = message.senderId == _currentUserId;

                    return _buildMessageBubble(message, isMe);
                  },
                );
              },
            ),
          ),
          _buildTypingIndicator(),
          _buildBottomArea(),
        ],
      ),
    );
  }

  void _showPassengersList() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      backgroundColor: Colors.white,
      builder: (bottomSheetCtx) {
        return Container(
          padding: const EdgeInsets.all(16),
          height: MediaQuery.of(context).size.height * 0.5,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text("إدارة الركاب", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black)),
                  Icon(Icons.people, color: Color(0xFF43C59E)),
                ],
              ),
              const Divider(thickness: 1, height: 24),
              Expanded(
                child: StreamBuilder<DatabaseEvent>(
                  stream: _tripParticipantsStream,
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      if (_latestParticipants.isNotEmpty) {
                        return _buildPassengersList(bottomSheetCtx, _latestParticipants);
                      }
                      return const Center(
                        child: Text("تعذر تحميل الركاب حالياً. حاول مرة أخرى.", style: TextStyle(color: Colors.grey)),
                      );
                    }

                    final hasStreamData = snapshot.hasData && snapshot.data?.snapshot.value != null;
                    final passengerList = hasStreamData
                        ? _extractTripParticipants(snapshot.data!.snapshot.value)
                        : _latestParticipants;

                    return _buildPassengersList(bottomSheetCtx, passengerList);
                  }
                )
              )
            ]
          )
        );
      }
    );
  }

  Widget _buildPassengersList(BuildContext bottomSheetCtx, List<Map<String, dynamic>> passengerList) {
    if (passengerList.isEmpty) {
      return const Center(child: Text("لا توجد مقاعد محجوزة حالياً.", style: TextStyle(color: Colors.grey)));
    }
    return ListView.builder(
      itemCount: passengerList.length,
      itemBuilder: (context, index) {
        final seat = passengerList[index];
        final key = seat['seatKey'];
        final passengerId = seat['userId']?.toString() ?? '';
        final firstName = seat['firstName']?.toString() ?? '';
        final lastName = seat['lastName']?.toString() ?? '';
        final passengerName = ("$firstName $lastName").trim().isNotEmpty
            ? ("$firstName $lastName").trim()
            : (seat['userName'] ?? "راكب غير معروف");
        final isDelivery = _isDeliverySeat(seat);
        final roleLabel = isDelivery ? "مرسل طرد" : "مسافر";
        final status = seat['status']?.toString() ?? '';
        final from = seat['from']?.toString() ?? '';
        final to = seat['to']?.toString() ?? '';
        final routeLabel = (from.isNotEmpty || to.isNotEmpty) ? "$from → $to" : null;

        return Card(
          elevation: 0,
          color: Colors.grey.shade50,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey.shade200)),
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: UserProfileAvatar(userId: passengerId, radius: 20),
            title: Text("$passengerName ($roleLabel)", style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (routeLabel != null) Text(routeLabel, style: TextStyle(color: Colors.grey.shade700, fontSize: 12)),
                if (status.isNotEmpty) Text("الحالة: $status", style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
              ],
            ),
            trailing: IconButton(
              icon: const Icon(Icons.person_remove, color: Colors.redAccent),
              tooltip: 'إزالة الراكب',
              onPressed: () async {
                final confirm = await showDialog<bool>(
                  context: bottomSheetCtx,
                  builder: (ctx) => AlertDialog(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    title: const Text("إزالة الراكب"),
content: Text(
  " $passengerName هل أنت متأكد أنك تريد إزالة\n"
  "من الدردشة والرحلة؟",
  textAlign: TextAlign.center,
),                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("إلغاء", style: TextStyle(color: Colors.grey))),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.red, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text("إزالة", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                );
                if (confirm == true) {
                  if (passengerId.isEmpty) {
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("تعذر إزالة هذا الراكب: معرّف المستخدم غير موجود")),
                    );
                    return;
                  }
                  await _chatService.removePassenger(widget.tripId, key, passengerId);
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text("تمت إزالة $passengerName من الدردشة والرحلة")),
                  );
                }
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildTypingIndicator() {
     if (_driverId == null) return const SizedBox.shrink();
     
     // Which string ID to track? Both passenger and driver could type.
     // For simplicity in group context, we can track if driver is typing (if we are passenger)
     // or track generic typing.
     // A better way is to listen to the whole `typing` node directly, but `chat_service` takes a userId.
     return StreamBuilder<bool>(
        stream: _typingStream,
        builder: (context, snapshot) {
           if (snapshot.data == true) {
              return Container(
                 padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                 alignment: Alignment.centerLeft,
                 child: Text("يكتب الآن...", style: TextStyle(color: Colors.grey.shade600, fontStyle: FontStyle.italic, fontSize: 12)),
              );
           }
           return const SizedBox.shrink();
        }
     );
  }

  Widget _buildMessageBubble(ChatMessage message, bool isMe) {
    if (message.isSystemMessage) {
      return Center(
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 8),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.grey.shade300,
            borderRadius: BorderRadius.circular(16)
          ),
          child: Text(
            message.message,
            style: const TextStyle(fontSize: 12, color: Colors.black54),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    String roleLabel = message.senderId == _driverId 
        ? "(سائق)" 
        : "(${_userRoles[message.senderId] ?? "مسافر"})";

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMe) ...[
            UserProfileAvatar(userId: message.senderId, radius: 16),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.70, // Slightly reduced width
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isMe ? const Color(0xFF43C59E) : Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(isMe ? 16 : 0),
                  topRight: Radius.circular(isMe ? 0 : 16),
                  bottomLeft: const Radius.circular(16),
                  bottomRight: const Radius.circular(16),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 2,
                    offset: const Offset(0, 1),
                  )
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!isMe) ...[
                    Text(
                      "${message.senderName} $roleLabel",
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: Color(0xFF43C59E),
                      ),
                    ),
                    const SizedBox(height: 4),
                  ],
                    Text(
                    message.message,
                    style: TextStyle(fontSize: 14, color: isMe ? Colors.white : Colors.black87),
                  ),
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.bottomRight,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          _formatTime(DateTime.fromMillisecondsSinceEpoch(message.timestamp)),
                          style: TextStyle(
                            fontSize: 10,
                            color: isMe ? Colors.white70 : Colors.black.withValues(alpha: 0.4),
                          ),
                        ),
                        if (isMe) ...[
                          const SizedBox(width: 4),
                          Icon(
                            message.status == 'read' ? Icons.done_all : Icons.check,
                            size: 14,
                            color: message.status == 'read' ? Colors.lightBlueAccent : Colors.white70,
                          )
                        ]
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (isMe) ...[
            const SizedBox(width: 8),
            UserProfileAvatar(userId: message.senderId, radius: 16),
          ],
        ],
      ),
    );
  }

  Widget _buildMessageInput() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.grey.shade300)
                ),
                child: TextField(
                  controller: _messageController,
                  maxLines: null,
                  textInputAction: TextInputAction.send,
                  onChanged: _onMessageChanged,
                  onSubmitted: (_) => _sendMessage(),
                  decoration: const InputDecoration(
                    hintText: "اكتب رسالة...",
                    border: InputBorder.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              decoration: const BoxDecoration(
                color: Color(0xFF43C59E),
                shape: BoxShape.circle,
              ),
              child: IconButton(
                icon: const Icon(Icons.send, color: Colors.white),
                onPressed: _sendMessage,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomArea() {
    return StreamBuilder<DatabaseEvent>(
      stream: _tripStatusStream,
      builder: (context, snapshot) {
        final status = snapshot.data?.snapshot.value?.toString();

        // Removed passenger: don't allow sending messages and don't show rating prompt.
        if (_isRemovedFromChat) {
          return Container(
            padding: const EdgeInsets.all(16),
            color: Colors.white,
            alignment: Alignment.center,
            child: const Text(
              "تمت إزالتك من الرحلة بواسطة السائق",
              style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold),
            ),
          );
        }
        
        if (status == 'completed' || status == 'archived' || status == 'finished') {
          if (_driverId == _currentUserId) {
             return Container(
                padding: const EdgeInsets.all(16),
                color: Colors.white,
                alignment: Alignment.center,
                child: const Text("تم إنهاء الرحلة. بانتظار تقييم الركاب.", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
             );
          } else {
             return StreamBuilder<bool>(
                stream: _driverId != null ? _chatService.hasPassengerRated(_driverId!, widget.tripId, _currentUserId) : const Stream.empty(),
                builder: (context, rateSnap) {
                   final hasRated = rateSnap.data ?? false;
                   if (hasRated) {
                      return Container(
                         padding: const EdgeInsets.all(16),
                         color: Colors.white,
                         alignment: Alignment.center,
                         child: const Text("تم التقييم بنجاح. شكراً لك!", style: TextStyle(color: Color(0xFF43C59E), fontWeight: FontWeight.bold)),
                      );
                   } else {
                      return _buildRatingCard();
                   }
                }
             );
          }
        }
        
        return _buildMessageInput();
      }
    );
  }

  int _currentRating = 0;

  Widget _buildRatingCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, -5))],
      ),
      child: Column(
        children: [
          const Text("كيف كانت رحلتك؟", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text("يرجى تقييم السائق لمساعدتنا في تحسين الخدمة", style: TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(5, (index) {
              return IconButton(
                onPressed: () {
                   setState(() { _currentRating = index + 1; });
                },
                icon: Icon(
                  index < _currentRating ? Icons.star : Icons.star_border,
                  color: Colors.orange,
                  size: 32,
                ),
              );
            }),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: _currentRating > 0 && _driverId != null ? () async {
                     try {
                       await _chatService.submitRating(
                         _driverId!,
                         widget.tripId,
                         _currentUserId,
                         _currentRating.toDouble(),
                       );
                       // submitRating already archives the chat
                       if (!context.mounted) return;
                       ScaffoldMessenger.of(context).showSnackBar(
                         const SnackBar(content: Text("تم إرسال التقييم بنجاح")),
                       );
                       Navigator.of(context).pop();
                     } catch (e) {
                       if (!context.mounted) return;
                       ScaffoldMessenger.of(context).showSnackBar(
                         SnackBar(content: Text("تعذر إرسال التقييم: $e")),
                       );
                     }
                  } : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF43C59E),
                    minimumSize: const Size(double.infinity, 45),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text("إرسال", style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: () async {
                    await _chatService.archiveChat(widget.tripId, _currentUserId);
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("يمكنك تقييم السائق لاحقا ")),
                    );
                    Navigator.of(context).pop();
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.grey.shade700,
                    side: BorderSide(color: Colors.grey.shade400),
                    minimumSize: const Size(double.infinity, 45),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text("لاحقاً", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
