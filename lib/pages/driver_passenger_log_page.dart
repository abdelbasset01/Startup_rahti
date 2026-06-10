import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import '../widgets/user_profile_avatar.dart';

class DriverPassengerLogPage extends StatefulWidget {
  final String tripId;
  final String driverName; // Just for display fallback if needed
  final int totalSeats;

  const DriverPassengerLogPage({
    super.key,
    required this.tripId,
    required this.driverName,
    this.totalSeats = 4,
  });

  @override
  State<DriverPassengerLogPage> createState() => _DriverPassengerLogPageState();
}

class _DriverPassengerLogPageState extends State<DriverPassengerLogPage> {
  // Map of seat index to passenger info
  Map<int, Map<dynamic, dynamic>> _occupiedSeats = {};
  List<Map<dynamic, dynamic>> _deliveryPackages = [];
  final Map<String, String> _usernameCache = {};
  bool _isLoading = true;
  StreamSubscription<DatabaseEvent>? _seatsSub;

  int? _asSeatIndex(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  List<int> _extractSeatIndices(dynamic raw) {
    final List<int> result = [];
    if (raw is List) {
      for (final value in raw) {
        final idx = _asSeatIndex(value);
        if (idx != null && idx > 0) result.add(idx);
      }
    } else if (raw is Map) {
      for (final value in raw.values) {
        final idx = _asSeatIndex(value);
        if (idx != null && idx > 0) result.add(idx);
      }
    } else {
      final idx = _asSeatIndex(raw);
      if (idx != null && idx > 0) result.add(idx);
    }
    return result.toSet().toList()..sort();
  }

  dynamic _seatMapValue(dynamic seatMapRaw, int index, List<int> seatIndices) {
    if (seatMapRaw == null) return null;
    
    if (seatMapRaw is List) {
      if (index >= 0 && index < seatMapRaw.length && seatMapRaw[index] != null) {
        return seatMapRaw[index];
      }
      int relativeIndex = seatIndices.indexOf(index);
      if (relativeIndex >= 0 && relativeIndex < seatMapRaw.length) {
        return seatMapRaw[relativeIndex];
      }
      return null;
    }
    
    if (seatMapRaw is Map) {
      if (seatMapRaw[index] != null) return seatMapRaw[index];
      if (seatMapRaw[index.toString()] != null) return seatMapRaw[index.toString()];
  
      for (final entry in seatMapRaw.entries) {
        final keyIndex = int.tryParse(entry.key.toString().replaceAll(RegExp(r'[^0-9]'), ''));
        if (keyIndex == index) return entry.value;
      }
      
      int relativeIndex = seatIndices.indexOf(index);
      if (relativeIndex != -1) {
         if (seatMapRaw[relativeIndex] != null) return seatMapRaw[relativeIndex];
         if (seatMapRaw[relativeIndex.toString()] != null) return seatMapRaw[relativeIndex.toString()];
      }
    }
    return null;
  }

  String _genderForSeat(Map<dynamic, dynamic> booking, int seatIndex) {
    final indices = _extractSeatIndices(booking['seatIndices']);
    final perSeatGender = _seatMapValue(booking['seatGenders'], seatIndex, indices);
    if (perSeatGender != null) {
      return perSeatGender.toString();
    }
    return booking['gender']?.toString() ?? 'unknown';
  }

  @override
  void initState() {
    super.initState();
    _listenToSeats();
  }

  @override
  void dispose() {
    _seatsSub?.cancel();
    super.dispose();
  }

  void _listenToSeats() {
    final ref = FirebaseDatabase.instance.ref().child('trips').child(widget.tripId).child('takenSeats');
    _seatsSub = ref.onValue.listen((event) {
      if (!mounted) return;
      
      final Map<int, Map<dynamic, dynamic>> occupied = {};
      final List<Map<dynamic, dynamic>> packages = [];
      
      if (event.snapshot.value != null) {
        final data = event.snapshot.value as Map<dynamic, dynamic>;
        data.forEach((key, value) {
           final booking = Map<dynamic, dynamic>.from(value as Map);
           booking['seatKey'] = key;
           final isDelivery = booking['isDelivery'] == true || booking['transportType'] == 'package' || booking['packageType'] != null;
           
           if (isDelivery) {
              if (booking['status'] == 'accepted' || booking['status'] == 'completed' || booking['status'] == 'تم التسليم' || booking['status'] == 'تم التسليم بنجاح' || booking['deliveryStatus'] == 'completed' || booking['deliveryStatus'] == 'تم التسليم' || booking['deliveryStatus'] == 'تم التسليم بنجاح') {
                 packages.add(booking);
              }
           } else {
             if (booking['status'] == 'accepted' || booking['status'] == 'completed' || booking['status'] == 'تم التسليم' || booking['status'] == 'تم التسليم بنجاح' || booking['status'] == 'cancelled') {
               final indices = _extractSeatIndices(booking['seatIndices']);
               for (final idx in indices) {
                 occupied[idx] = booking;
               }
             }
           }
        });
      }
      
      setState(() {
        _occupiedSeats = occupied;
        _deliveryPackages = packages;
        _isLoading = false;
      });
    });
  }

  Future<String> _resolveUsername(Map<dynamic, dynamic> booking) async {
    final uid = booking['userId']?.toString() ?? '';
    if (uid.isEmpty) {
      return booking['username']?.toString() ??
          booking['userName']?.toString() ??
          'passenger';
    }
    if (_usernameCache.containsKey(uid)) {
      return _usernameCache[uid]!;
    }
    try {
      final snap = await FirebaseDatabase.instance.ref().child('users').child(uid).get();
      if (snap.exists && snap.value is Map) {
        final data = snap.value as Map<dynamic, dynamic>;
        final first = data['firstName']?.toString() ?? '';
        final last = data['lastName']?.toString() ?? '';
        final full = "$first $last".trim();
        if (full.isNotEmpty) {
          _usernameCache[uid] = full;
          return full;
        }
        final username = data['username']?.toString();
        final resolved = (username != null && username.trim().isNotEmpty)
            ? username.trim()
            : (data['name']?.toString() ?? 'passenger');
        _usernameCache[uid] = resolved;
        return resolved;
      }
    } catch (_) {}
    final fallback = booking['username']?.toString() ??
        booking['userName']?.toString() ??
        'passenger';
    _usernameCache[uid] = fallback;
    return fallback;
  }

  void _showPassengerDetails(Map<dynamic, dynamic> booking) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(20),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              const SizedBox(height: 20),
              UserProfileAvatar(
                userId: booking['userId']?.toString() ?? '',
                radius: 30,
              ),
              const SizedBox(height: 16),
              const Text(
                "بيانات الراكب",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 20),
              ListTile(
                leading: const Icon(Icons.person, color: Color(0xFF43C59E)),
                title: Text(
                  "${booking['userName']?.toString() ?? 'مسافر غير معروف'} (${(booking['isDelivery'] == true || booking['transportType'] == 'package' || booking['packageType'] != null) ? 'مرسل طرد' : 'مسافر'})"
                ),
                subtitle: const Text('الاسم الكامل'),
              ),
              if (booking['phone'] != null)
                ListTile(
                  leading: const Icon(Icons.phone, color: Color(0xFF43C59E)),
                  title: Text(booking['phone'].toString()),
                  subtitle: const Text('رقم الهاتف'),
                ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF43C59E),
                  minimumSize: const Size(double.infinity, 50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  "إغلاق",
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
              const SizedBox(height: 10),
            ],
          ),
        );
      }
    );
  }

  Widget _buildSeat(int seatIndex) {
    Widget babySeatIcon(Color color) {
      return Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          Icon(Icons.event_seat_rounded, color: color, size: 20),
          Positioned(
            top: -2,
            right: -2,
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.95),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.child_care_rounded, size: 8, color: Colors.black87),
            ),
          ),
        ],
      );
    }

    if (seatIndex == 0) {
      return Column(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: Colors.black87,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                )
              ],
            ),
            child: const Icon(Icons.drive_eta, color: Colors.white, size: 24),
          ),
          const SizedBox(height: 8),
          const Text("السائق", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
        ],
      );
    }

    final isOccupied = _occupiedSeats.containsKey(seatIndex);
    Color seatColor = Colors.grey.shade300;
    String label = "فارغ";
    Map<dynamic, dynamic>? booking;
    String gender = 'unknown';

    if (isOccupied) {
       booking = _occupiedSeats[seatIndex]!;
       
       gender = _genderForSeat(booking, seatIndex);

       if (gender == 'male') {
         seatColor = Colors.blue.shade800;
       } else if (gender == 'female') {
         seatColor = Colors.pink.shade400;
       } else if (gender == 'kids') {
         seatColor = Colors.orange;
       } else {
         seatColor = const Color(0xFF43C59E); // Generic occupied
       }
       
       label = booking['username']?.toString() ??
           booking['userName']?.toString() ??
           "passenger";
    }

    return GestureDetector(
      onTap: () {
        if (isOccupied && booking != null) {
          _showPassengerDetails(booking);
        }
      },
      child: Column(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: seatColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade300, width: 1),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    )
                  ],
                ),
                child: isOccupied 
                    ? (gender == 'kids'
                        ? Tooltip(
                            message: "مقعد رضيع (siège auto)",
                            child: babySeatIcon(Colors.white),
                          )
                        : const Icon(Icons.person, color: Colors.white))
                    : const Icon(Icons.chair, color: Colors.white),
              ),
              if (isOccupied)
                () {
                  bool hasLuggage = false;
                  final indices = _extractSeatIndices(booking!['seatIndices']);
                  final luggageVal = _seatMapValue(booking['seatLuggage'], seatIndex, indices);
                  if (luggageVal != null) {
                    hasLuggage = luggageVal == true || luggageVal.toString().toLowerCase() == 'true';
                  } else if (booking['seatLuggage'] == null) {
                    hasLuggage = booking['hasLuggage'] == true || booking['hasLuggage']?.toString().toLowerCase() == 'true';
                  }
                  if (hasLuggage) {
                    return Positioned(
                      top: -8,
                      right: -8,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 4),
                          ],
                        ),
                        child: const Icon(Icons.luggage, color: Color(0xFF43C59E), size: 14),
                      ),
                    );
                  }
                  return const SizedBox.shrink();
                }(),
            ],
          ),
          const SizedBox(height: 8),
          if (!isOccupied)
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.normal,
                color: Colors.grey.shade600,
              ),
              overflow: TextOverflow.ellipsis,
            )
          else
            FutureBuilder<String>(
              future: _resolveUsername(booking!),
              builder: (context, snap) {
                return Text(
                  snap.data ?? label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: seatColor,
                  ),
                  overflow: TextOverflow.ellipsis,
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildCarLayout() {
    List<Widget> rows = [];
    
    // Front row
    rows.add(
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _buildSeat(0), // Driver
          if (widget.totalSeats >= 1) _buildSeat(1) else const SizedBox(width: 50),
        ],
      )
    );
    
    // Calculate remaining rows (max 3 seats per row)
    int currentSeatNumber = 2;
    while (currentSeatNumber <= widget.totalSeats) {
      List<Widget> rowSeats = [];
      for (int i = 0; i < 3; i++) {
        if (currentSeatNumber <= widget.totalSeats) {
          rowSeats.add(_buildSeat(currentSeatNumber));
          currentSeatNumber++;
        } else {
          rowSeats.add(const SizedBox(width: 50)); // Placeholder for alignment
        }
      }
      
      rows.add(const SizedBox(height: 40));
      rows.add(
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: rowSeats,
        )
      );
    }

    return Container(
      width: 300,
      padding: const EdgeInsets.all(30),
      margin: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(100),
          bottom: Radius.circular(40),
        ),
        border: Border.all(
          color: Colors.grey.shade200,
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: rows,
      ),
    );
  }

  Widget _buildLegendItem(Color color, String label, {bool hasBorder = false}) {
    return Row(
      children: [
        Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: hasBorder ? Border.all(color: Colors.grey.shade300) : null,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    int emptySeats = widget.totalSeats - _occupiedSeats.length;

    return Scaffold(
      backgroundColor: Colors.grey[50], // Very light background
      appBar: AppBar(
        title: const Text(
          "سجل الركاب",
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF43C59E),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isLoading 
         ? const Center(child: CircularProgressIndicator(color: Color(0xFF43C59E)))
         : SingleChildScrollView(
            child: Column(
              children: [
                const SizedBox(height: 20),
                
                // Info Card
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 20),
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 2))
                    ]
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                       Expanded(
                         child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                               Text("الركاب", style: TextStyle(color: Colors.grey.shade600, fontSize: 14)),
                               const SizedBox(height: 4),
                               Text("${_occupiedSeats.length} / ${widget.totalSeats}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 24, color: Color(0xFF43C59E))),
                            ],
                         ),
                       ),
                       Container(width: 1, height: 40, color: Colors.grey.shade200),
                       Expanded(
                         child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                               Text("المقاعد الشاغرة", style: TextStyle(color: Colors.grey.shade600, fontSize: 14)),
                               const SizedBox(height: 4),
                               Text(emptySeats.toString(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 24, color: Colors.black87)),
                            ],
                         ),
                       ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 30),
                
                // Legend
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      _buildLegendItem(Colors.grey.shade300, "فارغ", hasBorder: true),
                      _buildLegendItem(Colors.blue.shade800, "ذكر 13+"),
                      _buildLegendItem(Colors.pink.shade400, "أنثى"),
                      _buildLegendItem(Colors.orange, "طفل -13"),
                    ],
                  ),
                ),
                
                const SizedBox(height: 30),
                
                // Vehicle Layout
                Center(child: _buildCarLayout()),
                
                const SizedBox(height: 30),
                
                // Safety Guidelines for Driver
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 20),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.warning_amber_rounded, color: Colors.red.shade700, size: 24),
                          const SizedBox(width: 8),
                          Text(
                            "شروط السلامة والقوانين",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: Colors.red.shade800,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _buildRuleText("• يُمنع حمل طفل أقل من 3 سنوات في الحضن داخل السيارة."),
                        _buildRuleText("• الأطفال من 3 سنوات فما فوق: يجب الجلوس في مقعد مناسب (مقعد أطفال أو مقعد عادي آمن)."),
                        _buildRuleText("• القاصرون (أقل من 18 سنة): مسموح فقط بإذن من الولي أو مع مرافق بالغ."),
                      ],  
                  ),
                ),
                
                if (_deliveryPackages.isNotEmpty) ...[
                  const SizedBox(height: 40),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        "الطرود المضافة",
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF43C59E),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  ..._deliveryPackages.map((pkg) => _buildPackageCard(pkg)),
                ],
                const SizedBox(height: 40),
              ],
            ),
         ),
    );
  }

  Future<void> _showOTPValidationDialog(Map<dynamic, dynamic> pkg) async {
    final seatKey = pkg['seatKey']?.toString();
    final userId = pkg['userId']?.toString();
    String? currentOtp = pkg['otp']?.toString();
    if (currentOtp != null && currentOtp.trim().isEmpty) {
      currentOtp = null;
    }

    // Some records may miss local otp field in list payload; fetch latest before failing.
    if (currentOtp == null && seatKey != null) {
      try {
        final seatSnap = await FirebaseDatabase.instance
            .ref()
            .child('trips')
            .child(widget.tripId)
            .child('takenSeats')
            .child(seatKey)
            .child('otp')
            .get();
        if (seatSnap.exists && seatSnap.value != null) {
          currentOtp = seatSnap.value.toString();
        }
      } catch (_) {}
    }

    if (currentOtp == null && userId != null && seatKey != null) {
      try {
        final bookingSnap = await FirebaseDatabase.instance
            .ref()
            .child('bookings')
            .child(userId)
            .child(seatKey)
            .child('otp')
            .get();
        if (bookingSnap.exists && bookingSnap.value != null) {
          currentOtp = bookingSnap.value.toString();
        }
      } catch (_) {}
    }

    if (currentOtp == null || currentOtp.trim().isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('عذرًا، لا يوجد رمز لهذا الطرد حتى الآن.')),
        );
      }
      return;
    }
    pkg['otp'] = currentOtp;

    final TextEditingController otpCtrl = TextEditingController();
    String? errorMessage;
    int localAttempts = 0;
    final rawAttempts = pkg['otpAttempts'];
    if (rawAttempts is num) {
      localAttempts = rawAttempts.toInt();
    } else if (rawAttempts is String) {
      localAttempts = int.tryParse(rawAttempts) ?? 0;
    }
    bool isSubmitting = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (stateContext, setState) {
            return AlertDialog(
              title: const Text("تأكيد التسليم", style: TextStyle(color: Color(0xFF43C59E), fontWeight: FontWeight.bold)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(":يرجى إدخال الرمز  لتأكيد استلام الطرد", style: TextStyle(fontSize: 14)),              
                  const SizedBox(height: 16),
                  TextField(
                    controller: otpCtrl,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: 4),
                    decoration: InputDecoration(
                      hintText: "------",
                      filled: true,
                      fillColor: Colors.grey.shade50,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF43C59E), width: 2)),
                    ),
                  ),
                  if (errorMessage != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12.0),
                      child: Text(errorMessage!, style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                    ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text("إلغاء", style: TextStyle(color: Colors.grey)),
                ),
                ElevatedButton(
                  onPressed: isSubmitting ? null : () async {
                    final input = otpCtrl.text.trim();
                    if (input.isNotEmpty && input == pkg['otp'].toString().trim()) {
                      Navigator.pop(dialogContext);
                      await _confirmDelivery(pkg);
                    } else {
                      localAttempts += 1;
                      pkg['otpAttempts'] = localAttempts;

                      // Update driver UI immediately and independently from Firebase writes.
                      setState(() {
                        errorMessage = 'تعذّر تأكيد رمز التحقق. المحاولات المتبقية: ${3 - localAttempts}.';
                        otpCtrl.clear();
                      });

                      if (localAttempts >= 3) {
                        final random = Random();
                        final newOtp = (100000 + random.nextInt(900000)).toString();
                        final seatKey = pkg['seatKey'];
                        final userId = pkg['userId'];

                        setState(() => isSubmitting = true);
                        bool updatedAtLeastOneNode = false;

                        try {
                          if (seatKey != null && userId != null) {
                            final tripRef = FirebaseDatabase.instance.ref().child('trips').child(widget.tripId).child('takenSeats').child(seatKey);
                            await tripRef.update({'otp': newOtp, 'otpAttempts': 0});
                            updatedAtLeastOneNode = true;

                            final bookingRef = FirebaseDatabase.instance.ref().child('bookings').child(userId).child(seatKey);
                            try {
                              await bookingRef.update({'otp': newOtp, 'otpAttempts': 0, 'otpMsg': 'تم تحديث رمز التحقق'});
                              updatedAtLeastOneNode = true;
                            } catch (e) {
                              debugPrint('Failed to update booking OTP node: $e');
                            }

                            pkg['otp'] = newOtp;
                            pkg['otpAttempts'] = 0;
                          }
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  updatedAtLeastOneNode
                                      ? 'انتهت صلاحية رمز التحقق. تم تحديث الرمز لأسباب أمنية، يرجى استخدامه مرة أخرى.'
                                      : 'تعذر تحديث الرمز. يرجى المحاولة مرة أخرى لاحقًا.',
                                ),
                                backgroundColor: updatedAtLeastOneNode ? Colors.red : Colors.orange,
                              ),  
                            );
                          }
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ في الاتصال: $e'), backgroundColor: Colors.orange));
                          }
                        } finally {
                          if (mounted) {
                            setState(() => isSubmitting = false);
                            Navigator.pop(dialogContext);
                          }
                        }
                      } else {
                        // Fire and forget, or try/catch so to not block the UI
                        try {
                          final seatKey = pkg['seatKey'];
                          final userId = pkg['userId'];
                          if (seatKey != null) {
                            await FirebaseDatabase.instance.ref().child('trips').child(widget.tripId).child('takenSeats').child(seatKey).update({'otpAttempts': localAttempts});
                          }
                          if (userId != null && seatKey != null) {
                            await FirebaseDatabase.instance.ref().child('bookings').child(userId).child(seatKey).update({'otpAttempts': localAttempts});
                          }
                        } catch (e) {
                          debugPrint('Failed to update attempts online: $e');
                        }
                      }
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF43C59E),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text("تأكيد", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ],
            );
          }
        );
      }
    );
  }

  Future<void> _confirmDelivery(Map<dynamic, dynamic> pkg) async {
    final seatKey = pkg['seatKey'];
    final userId = pkg['userId'];
    if (seatKey == null || userId == null) return;
    
    try {
      await FirebaseDatabase.instance.ref()
          .child('trips')
          .child(widget.tripId)
          .child('takenSeats')
          .child(seatKey)
          .update({'deliveryStatus': 'تم التسليم بنجاح', 'status': 'تم التسليم بنجاح'});
          
      await FirebaseDatabase.instance.ref()
          .child('bookings')
          .child(userId)
          .child(seatKey)
          .update({'deliveryStatus': 'تم التسليم بنجاح', 'status': 'تم التسليم بنجاح', 'passengerSeen': false});
          
      if (mounted) {
         ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ تم التسليم بنجاح', style: TextStyle(color: Colors.white)), backgroundColor: Colors.green));
      }
    } catch(e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: $e')));
    }
  }

  Widget _buildPackageCard(Map<dynamic, dynamic> pkg) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.orange.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.inventory_2, color: Colors.orange, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      pkg['packageType'] ?? 'طرد',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      pkg['packageDetails'] ?? 'لا يوجد وصف',
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                    ),
                  ],
                ),
              ),
              if (pkg['price'] != null || pkg['suggestedPrice'] != null || pkg['totalPrice'] != null || pkg['basePrice'] != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF43C59E).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    "${pkg['suggestedPrice'] ?? pkg['price'] ?? pkg['totalPrice'] ?? pkg['basePrice']} دج",
                    style: const TextStyle(color: Color(0xFF43C59E), fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 8),
          _buildInfoRow(Icons.person, "المُرسِل", pkg['userName'] ?? pkg['senderName'] ?? 'غير معروف'),
          const SizedBox(height: 8),
          _buildInfoRow(Icons.call, "رقم المستلِم", pkg['senderPhone'] ?? 'غير متوفر'),
          const SizedBox(height: 8),
          _buildInfoRow(Icons.location_on, "المسار", "${pkg['from'] ?? ''} ← ${pkg['to'] ?? ''}"),
          
          const SizedBox(height: 16),
          if (pkg['deliveryStatus'] == 'completed' ||
              pkg['deliveryStatus'] == 'تم التسليم' ||
              pkg['deliveryStatus'] == 'تم التسليم بنجاح' ||
              pkg['status'] == 'تم التسليم بنجاح')
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.green.shade200),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Icon(Icons.check_circle, color: Colors.green),
                  SizedBox(width: 8),
                  Text("تم التسليم بنجاح", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green, fontSize: 16)),
                ],
              ),
            )
          else
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _showOTPValidationDialog(pkg),
                icon: const Icon(Icons.password_rounded, color: Colors.white),
                label: const Text("تأكيد التسليم", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF43C59E),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 14, color: Colors.grey.shade500),
        const SizedBox(width: 8),
        Text("$label: ", style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
        Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12))),
      ],
    );
  }

  Widget _buildRuleText(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          color: Colors.red.shade900,
          height: 1.4,
        ),
      ),
    );
  }
}
