import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import '../models/chat_message.dart';
import '../services/chat_service.dart';
import 'chat_page.dart';
import '../widgets/logout_confirmation_dialog.dart';
import '../widgets/message_badge.dart';
import '../widgets/global_app_bar_actions.dart';
import '../widgets/user_profile_avatar.dart';
import '../widgets/history_badge.dart';

class MessagesPage extends StatefulWidget {
  final bool isDriverMode;
  const MessagesPage({super.key, this.isDriverMode = false});

  @override
  State<MessagesPage> createState() => _MessagesPageState();
}

class _MessagesPageState extends State<MessagesPage> {
  final ChatService _chatService = ChatService();
  final String _currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';
  int _currentIndex = 2; // Index for Messages in Customer view

  late bool _isDriver;
  String _searchQuery = "";

  int _tripSortKey(Map<String, dynamic> trip) {
    int parse(dynamic v) => (v as num?)?.toInt() ?? 0;
    return [
      parse(trip['updatedAt']),
      parse(trip['lastMessageAt']),
      parse(trip['bookingTimestamp']),
      parse(trip['finishedAt']),
      parse(trip['createdAt']),
      parse(trip['bookingTime']),
      parse(trip['timestamp']),
    ].reduce((a, b) => a > b ? a : b);
  }

  @override
  void initState() {
    super.initState();
    _isDriver = widget.isDriverMode;
    if (!_isDriver) {
      _checkRole();
    }
  }

  Future<void> _checkRole() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final snap = await FirebaseDatabase.instance.ref().child('users').child(user.uid).child('currentRole').get();
      if (snap.exists && snap.value == 'driver') {
        setState(() {
          _isDriver = true;
          _currentIndex = -1;
        });
      }
    }
  }

  void _onBottomNavTapped(int index) {
    if (index == _currentIndex) return;
    
    setState(() {
      _currentIndex = index;
    });

    if (index == 0) {
      Navigator.pushReplacementNamed(context, '/home');
    } else if (index == 1) {
      Navigator.pushReplacementNamed(context, '/history');
    } else if (index == 2) {
      // Already here
    } else if (index == 3) {
      Navigator.pushReplacementNamed(context, '/delivery');
    } else if (index == 4) {
      Navigator.pushReplacementNamed(context, '/discount');
    } else if (index == 5) {
      Navigator.pushNamed(context, '/quran');
    }
  }

  Future<void> _logout() async {
    final shouldLogout = await showLogoutConfirmationDialog(context);
    if (shouldLogout != true) return;

    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
  }

  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);

    if (difference.inDays == 0 && now.day == timestamp.day) {
      final hour = timestamp.hour == 0 ? 12 : (timestamp.hour > 12 ? timestamp.hour - 12 : timestamp.hour);
      final period = timestamp.hour >= 12 ? 'م' : 'ص';
      return "$hour:${timestamp.minute.toString().padLeft(2, '0')} $period";
    } else if (difference.inDays == 1 || (difference.inDays == 0 && now.day != timestamp.day)) {
      return "الأمس";
    } else if (difference.inDays < 7) {
      const weekdays = ['الاثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت', 'الأحد'];
      return weekdays[timestamp.weekday - 1];
    } else {
      return "${timestamp.year}/${timestamp.month}/${timestamp.day}";
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        if (_currentIndex != 0) {
           Navigator.pushReplacementNamed(context, '/home');
           return false;
        }
        return true;
      },
      child: DefaultTabController(
        length: 2,
        child: Scaffold(
        backgroundColor: Colors.grey[50],
        appBar: widget.isDriverMode ? null : AppBar(
          title: const Align(
    alignment: Alignment.centerLeft, // 👈 force left
    child: Text(
      'الرسائل',
      style: TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.bold,
        fontSize: 20,
      ),
    ),
  ),
          backgroundColor: const Color(0xFF43C59E),
          elevation: 0,
          automaticallyImplyLeading: _isDriver, 
          actions: const [
            GlobalAppBarActions()
          ],
        ),
        body: Column(
          children: [
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  )
                ]
              ),
              child: const TabBar(
                labelColor: Color(0xFF43C59E),
                unselectedLabelColor: Colors.grey,
                indicatorColor: Color(0xFF43C59E),
                indicatorWeight: 3,
                labelStyle: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                tabs: [
                  Tab(text: 'النشطة'),
                  Tab(text: 'السابقة'),
                ],
              ),
            ),
            // Search Bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              color: Colors.grey[50],
              child: TextField(
                onChanged: (val) {
                  setState(() { _searchQuery = val.toLowerCase(); });
                },
                decoration: InputDecoration(
                  hintText: 'البحث عن محادثة...',
                  prefixIcon: const Icon(Icons.search, color: Colors.grey),
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(vertical: 0),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide(color: Colors.grey.shade200),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide(color: Colors.grey.shade200),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: const BorderSide(color: Color(0xFF43C59E)),
                  ),
                ),
              ),
            ),
            Expanded(
              child: StreamBuilder<DatabaseEvent>(
                stream: FirebaseDatabase.instance.ref().child('trips').onValue,
                builder: (context, snapshot) {
                  return TabBarView(
                    children: [
                      _buildTripsList(isActive: true, snapshot: snapshot),
                      _buildTripsList(isActive: false, snapshot: snapshot),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
        bottomNavigationBar: (widget.isDriverMode || _isDriver) ? null : Directionality(
          textDirection: TextDirection.ltr,
          child: BottomNavigationBar(
            currentIndex: _currentIndex,
            type: BottomNavigationBarType.fixed,
            selectedItemColor: const Color(0xFF43C59E),
            unselectedItemColor: Colors.grey,
            onTap: _onBottomNavTapped,
            items: [
              const BottomNavigationBarItem(icon: Icon(Icons.home), label: 'الرئيسية'),
              const BottomNavigationBarItem(icon: HistoryBadge(child: Icon(Icons.history)), label: 'السجل'),
              BottomNavigationBarItem(
                icon: MessageBadge(isDriverMode: _isDriver, child: const Icon(Icons.message)), 
                label: 'الرسائل'
              ),
              const BottomNavigationBarItem(icon: Icon(Icons.delivery_dining), label: 'توصيل'),
              const BottomNavigationBarItem(icon: Icon(Icons.discount), label: 'خصومات'),
              const BottomNavigationBarItem(icon: Icon(Icons.menu_book), label: 'اقرأ'),
            ],
          ),
        ),
      ),
      ),
    );
  }

  Widget _buildTripsList({required bool isActive, required AsyncSnapshot<DatabaseEvent> snapshot}) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: Color(0xFF43C59E)));
        }

        if (snapshot.hasError) {
          return Center(child: Text('خطأ: ${snapshot.error}'));
        }

        if (!snapshot.hasData || snapshot.data?.snapshot.value == null) {
          return _buildEmptyState(isActive);
        }

        final tripsData = snapshot.data!.snapshot.value as Map<dynamic, dynamic>;
        final List<Map<String, dynamic>> userTrips = [];

        tripsData.forEach((key, value) {
          final tripMap = Map<String, dynamic>.from(value);
          bool isParticipant = false;

          // Driver -> passenger explicit separation filtering
          if (_isDriver) {
            if (tripMap['driverId'] == _currentUserId) {
              bool hasAcceptedPassenger = false;
              
              final seats = tripMap['seats'] as Map<dynamic, dynamic>?;
              if (seats != null) {
                for (var seatVal in seats.values) {
                   final seatMap = seatVal as Map<dynamic, dynamic>;
                   final status = seatMap['status']?.toString();
                   if (status == 'accepted' || status == 'completed' || status == 'تم التسليم' || status == 'تم التسليم بنجاح') {
                      hasAcceptedPassenger = true;
                      break;
                   }
                }
              }
              
              if (!hasAcceptedPassenger) {
                final takenSeats = tripMap['takenSeats'] as Map<dynamic, dynamic>?;
                if (takenSeats != null) {
                   for (var seatVal in takenSeats.values) {
                      final seatMap = seatVal as Map<dynamic, dynamic>;
                      final status = seatMap['status']?.toString();
                      if (status == 'accepted' || status == 'completed' || status == 'تم التسليم' || status == 'تم التسليم بنجاح') {
                         hasAcceptedPassenger = true;
                         break;
                      }
                   }
                }
              }
              
              if (hasAcceptedPassenger) {
                isParticipant = true;
              }
            }
          } else {
             final seats = tripMap['seats'] as Map<dynamic, dynamic>?;
             if (seats != null) {
                for (var seatVal in seats.values) {
                   final seatMap = seatVal as Map<dynamic, dynamic>;
                   if (seatMap['reservedBy'] == _currentUserId) {
                      final status = seatMap['status']?.toString();
                      if (status == 'accepted' || status == 'completed' || status == 'تم التسليم' || status == 'تم التسليم بنجاح') {
                        isParticipant = true;
                        break;
                      }
                   }
                }
             }
             if (!isParticipant) {
               final takenSeats = tripMap['takenSeats'] as Map<dynamic, dynamic>?;
               if (takenSeats != null) {
                  for (var seatVal in takenSeats.values) {
                     final seatMap = seatVal as Map<dynamic, dynamic>;
                     if (seatMap['userId'] == _currentUserId) {
                        final status = seatMap['status']?.toString();
                        if (status == 'accepted' || status == 'completed' || status == 'تم التسليم' || status == 'تم التسليم بنجاح') {
                          isParticipant = true;
                          break;
                        }
                     }
                  }
               }
             }
          }

          // If the driver removed this passenger from the trip,
          // we still want the conversation to remain in "نشط" without archiving,
          // even if the passenger seat was removed from `takenSeats`.
          final chatStatusRawMaybe = tripMap['chatStatus'];
          final chatStatusMaybe = (chatStatusRawMaybe is Map)
              ? chatStatusRawMaybe[_currentUserId]?.toString()
              : null;
          if (chatStatusMaybe == 'deleted' || chatStatusMaybe == 'removed') {
            isParticipant = true;
          }



          if (isParticipant) {
             // Filter active vs past
            final chatStatusRaw = tripMap['chatStatus'];
            final chatStatus = (chatStatusRaw is Map) ? chatStatusRaw[_currentUserId] : null;
             final isArchived = chatStatus == 'archived';
             final status = tripMap['status']?.toString();
             final isDriverView = _isDriver && tripMap['driverId'] == _currentUserId;
             
             final isTripCancelled = status == 'cancelled';
             final isTripCompletedForDriver = status == 'completed' || status == 'archived' || status == 'finished' || status == 'cancelled';
             
             final shouldBeInHistory = isDriverView 
                 ? (isTripCompletedForDriver || isArchived)
                 : (isTripCancelled || isArchived);

             if (isActive) {
                if (!shouldBeInHistory) {
                   tripMap['id'] = key;
                   userTrips.add(tripMap);
                }
             } else {
                if (shouldBeInHistory) {
                   tripMap['id'] = key;
                   userTrips.add(tripMap);
                }
             }
          }
        });

        final dedupedTrips = (!_isDriver)
            ? () {
                final Map<String, Map<String, dynamic>> grouped = {};
                for (final trip in userTrips) {
                  final driverId = trip['driverId']?.toString() ?? '';
                  final key = driverId.isNotEmpty
                      ? driverId
                      : (trip['id']?.toString() ?? UniqueKey().toString());
                  final existing = grouped[key];
                  if (existing == null || _tripSortKey(trip) > _tripSortKey(existing)) {
                    grouped[key] = trip;
                  }
                }
                return grouped.values.toList();
              }()
            : userTrips;

        // Search filtering
        final filteredTrips = dedupedTrips.where((trip) {
           final driverName = trip['driverName']?.toString().toLowerCase() ?? "";
           final route = "${trip['fromWilaya']} ${trip['toWilaya']}".toLowerCase();
           return driverName.contains(_searchQuery) || route.contains(_searchQuery);
        }).toList();

        if (filteredTrips.isEmpty) {
          return _buildEmptyState(isActive);
        }

        // Sort by most recent trip/chat activity.
        filteredTrips.sort((a, b) => _tripSortKey(b).compareTo(_tripSortKey(a)));

        return ListView.builder(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.only(top: 8, bottom: 20),
          itemCount: filteredTrips.length,
          itemBuilder: (context, index) {
            final trip = filteredTrips[index];
            return _buildConversationTile(trip: trip, isActive: isActive);
          },
        );
  }

  Widget _buildConversationTile({required Map<String, dynamic> trip, required bool isActive}) {
    return _ConversationTile(
      trip: trip,
      isDriver: _isDriver,
      currentUserId: _currentUserId,
      chatService: _chatService,
      formatTimestamp: _formatTimestamp,
      isActive: isActive,
    );
  }
  Widget _buildEmptyState(bool isActive) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF43C59E).withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isActive ? Icons.chat_bubble_outline : Icons.history, 
              size: 64, 
              color: const Color(0xFF43C59E).withValues(alpha: 0.5)
            ),
          ),
          const SizedBox(height: 24),
          Text(
            isActive ? "لا توجد محادثات نشطة" : "لا توجد محادثات سابقة",
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black87),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              isActive 
                ? "عند حجز أو قيادة رحلة، ستظهر محادثاتك الجارية هنا."
                : "الرحلات التي اكتملت أو ألغيت ستظهر هنا كأرشيف.",
              style: TextStyle(color: Colors.grey.shade500, fontSize: 14),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}

class _ConversationTile extends StatefulWidget {
  final Map<String, dynamic> trip;
  final bool isDriver;
  final String currentUserId;
  final ChatService chatService;
  final String Function(DateTime) formatTimestamp;
  final bool isActive;

  const _ConversationTile({
    required this.trip,
    required this.isDriver,
    required this.currentUserId,
    required this.chatService,
    required this.formatTimestamp,
    required this.isActive,
  });

  @override
  State<_ConversationTile> createState() => _ConversationTileState();
}

class _ConversationTileState extends State<_ConversationTile> {
  late Stream<ChatMessage?> _lastMessageStream;
  late Stream<int> _unreadCountStream;
  Stream<bool>? _onlineStatusStream;

  @override
  void initState() {
    super.initState();
    final tripId = widget.trip['id'];
    _lastMessageStream = widget.chatService.getLastMessageStream(tripId, widget.currentUserId).asBroadcastStream();
    _unreadCountStream = widget.chatService.getUnreadCountStream(tripId, widget.currentUserId).asBroadcastStream();
    
    final driverId = widget.trip['driverId'];
    if (!widget.isDriver && driverId != null) {
      _onlineStatusStream = widget.chatService.getUserOnlineStatus(driverId).asBroadcastStream();
    }
  }

  @override
  Widget build(BuildContext context) {
    final tripId = widget.trip['id'];
    final route = "${widget.trip['fromWilaya']} → ${widget.trip['toWilaya']}";
    final driverName = widget.trip['driverName'] ?? "السائق";
    final driverId = widget.trip['driverId'];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Dismissible(
            key: Key(tripId),
            direction: DismissDirection.endToStart,
            background: Container(
              padding: const EdgeInsets.only(right: 20),
              alignment: Alignment.centerRight,
              decoration: BoxDecoration(
                color: Colors.red.shade400,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(Icons.delete_outline, color: Colors.white, size: 30),
            ),
            confirmDismiss: (direction) async {
              return await showDialog(
                context: context,
                builder: (context) {
                  return AlertDialog(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    title: Text(widget.isActive ? "أرشفة المحادثة" : "حذف المحادثة"),
                    content: Text(widget.isActive ? "هل تريد نقل هذه المحادثة إلى السابقة؟" : "هل تريد بالتأكيد حذف هذه المحادثة بشكل دائم؟"),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        child: const Text("إلغاء", style: TextStyle(color: Colors.grey)),
                      ),
                      ElevatedButton(
                        onPressed: () => Navigator.of(context).pop(true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: widget.isActive ? const Color(0xFF43C59E) : Colors.red,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        child: Text(widget.isActive ? "أرشفة" : "حذف", style: const TextStyle(color: Colors.white)),
                      ),
                    ],
                  );
                },
              );
            },
            onDismissed: (direction) {
              if (widget.isActive) {
                widget.chatService.archiveChat(tripId, widget.currentUserId);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('تم أرشفة المحادثة')),
                );
              } else {
                widget.chatService.deleteChatComplete(tripId, widget.currentUserId);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('تم حذف المحادثة')),
                );
              }
            },
            child: StreamBuilder<ChatMessage?>(
              stream: _lastMessageStream,
              builder: (context, snapshotLast) {
                final lastMessage = snapshotLast.data;
                
                return StreamBuilder<int>(
                  stream: _unreadCountStream,
                  builder: (context, snapshotUnread) {
                    final unreadCount = snapshotUnread.data ?? 0;
                    final hasUnread = unreadCount > 0;

                    return InkWell(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => ChatPage(tripId: tripId, route: route, driverName: driverName),
                          ),
                        );
                      },
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.03),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                          border: Border.all(color: Colors.grey.shade100)
                        ),
                        child: Row(
                          children: [
                            Stack(
                              children: [
                                UserProfileAvatar(
                                  userId: driverId,
                                  radius: 28,
                                ),
                                if (driverId != null && _onlineStatusStream != null)
                                  StreamBuilder<bool>(
                                    stream: _onlineStatusStream!,
                                    builder: (context, onlineSnap) {
                                      final isOnline = onlineSnap.data == true;
                                      return Positioned(
                                        bottom: 0,
                                        right: 0,
                                        child: Container(
                                          width: 14,
                                          height: 14,
                                          decoration: BoxDecoration(
                                            color: isOnline ? Colors.green : Colors.grey,
                                            shape: BoxShape.circle,
                                            border: Border.all(color: Colors.white, width: 2),
                                          ),
                                        ),
                                      );
                                    }
                                  )
                              ],
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              widget.isDriver ? "مجموعة الرحلة • $route" : "$route",
                                              style: TextStyle(
                                                fontWeight: hasUnread ? FontWeight.w900 : FontWeight.bold, 
                                                fontSize: 16,
                                                color: Colors.black87,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            if (!widget.isDriver)
                                              Padding(
                                                padding: const EdgeInsets.only(top: 2),
                                                child: Text(
                                                  "السائق: $driverName",
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    color: Colors.grey.shade600,
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                      if (lastMessage != null)
                                        Text(
                                          widget.formatTimestamp(DateTime.fromMillisecondsSinceEpoch(lastMessage.timestamp)),
                                          style: TextStyle(
                                            color: hasUnread ? const Color(0xFF43C59E) : Colors.grey.shade500, 
                                            fontSize: 12,
                                            fontWeight: hasUnread ? FontWeight.bold : FontWeight.normal
                                          ),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          lastMessage != null 
                                              ? "${lastMessage.senderId == widget.currentUserId ? 'أنت: ' : ''}${lastMessage.message}" 
                                              : "اضغط للبدء في المحادثة...",
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                              color: hasUnread ? Colors.black87 : Colors.grey.shade500,
                                              fontWeight: hasUnread ? FontWeight.bold : FontWeight.normal,
                                              fontSize: 14
                                          ),
                                        ),
                                      ),
                                      if (hasUnread)
                                        Container(
                                          margin: const EdgeInsets.only(right: 8),
                                          padding: const EdgeInsets.all(6),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF43C59E),
                                            shape: BoxShape.circle,
                                            boxShadow: [
                                              BoxShadow(
                                                color: const Color(0xFF43C59E).withValues(alpha: 0.4),
                                                blurRadius: 4,
                                                offset: const Offset(0, 2),
                                              )
                                            ],
                                          ),
                                          child: Text(
                                            unreadCount > 99 ? '99+' : unreadCount.toString(),
                                            style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                                          ),
                                        )
                                    ],
                                  ),
                                  if (!widget.isDriver && driverId != null && _onlineStatusStream != null)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: StreamBuilder<bool>(
                                        stream: _onlineStatusStream!,
                                        builder: (context, onlineSnap) {
                                          final isOnline = onlineSnap.data == true;
                                          return Text(
                                            isOnline ? "متصل الآن" : "غير متصل",
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: isOnline ? Colors.green.shade700 : Colors.grey.shade500,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }
                );
              }
            ),
          ),
        );
  }
}

