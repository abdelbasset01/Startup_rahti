import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import '../widgets/logout_confirmation_dialog.dart';
import '../widgets/message_badge.dart';
import 'dart:async';
import 'report_forgotten_item_page.dart';
import '../widgets/global_app_bar_actions.dart';
import '../widgets/user_profile_avatar.dart';
import '../widgets/history_badge.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/services.dart';
import '../services/pricing_service.dart';
class HistoryTrip {
  final String id;
  /// Firebase node key under `bookings/{uid}/…` and `trips/…/takenSeats/…`.
  final String bookingKey;
  final String tripId;
  final String from;
  final String to;
  final String date;
  final String time;
  final double basePrice;
  final double price;
  final String vehicleName;
  final String status;
  final double? suggestedPrice;
  final bool hasPackage;
  final int seats;
  final int luggagePrice;
  final String? promoCode;
  final String transportType;
  final String driverId;
  final String gender;
  final List<int> seatIndices;
  // Per-seat gender/luggage maps saved during seat selection.
  // Keys are typically seat numbers as strings (e.g. "1", "2", ...).
  final Map<dynamic, dynamic> seatGenders;
  final Map<dynamic, dynamic> seatLuggage;
  final int totalSeats;
  final String? packageType;
  final String? packageDetails;
  final String? senderName;
  final String? senderPhone;
  final String? passengerName;
  final bool isDelivery;
  final int sortTimestamp;
  final String? otp;
  final String? otpMsg;
  final String? deliveryStatus;
  final bool isRejoin;

  HistoryTrip({
    required this.id,
    required this.bookingKey,
    required this.tripId,
    required this.from,
    required this.to,
    required this.date,
    required this.time,
    required this.basePrice,
    required this.price,
    required this.vehicleName,
    required this.status,
    this.suggestedPrice,
    this.hasPackage = false,
    int seats = 1,
    this.luggagePrice = 0,
    this.promoCode,
    this.transportType = 'car',
    this.driverId = '',
    this.gender = '',
    this.seatIndices = const [],
    this.seatGenders = const {},
    this.seatLuggage = const {},
    this.totalSeats = 4,
    this.packageType,
    this.packageDetails,
    this.senderName,
    this.senderPhone,
    this.passengerName,
    this.isDelivery = false,
    this.sortTimestamp = 0,
    this.otp,
    this.otpMsg,
    this.deliveryStatus,
    this.passengerSeen = true,
    this.isRejoin = false,
  }) : seats = seats;

  final bool passengerSeen;
}

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> with SingleTickerProviderStateMixin {
  List<HistoryTrip> historyTrips = [];
  List<Map<String, dynamic>> _lostItems = [];
  StreamSubscription<DatabaseEvent>? _historySubscription;
  StreamSubscription<DatabaseEvent>? _lostItemsSubscription;
  StreamSubscription<DatabaseEvent>? _passengerTripsSubscription;

  String? _showingDialogForTripId;

  int _currentIndex = 1; // History page index
  int _historyFilter = 0; // 0: Today, 1: Past
  late TabController _tabController;

  bool _isLocalDeliveryObj(HistoryTrip t) => t.isDelivery;

  void _markSeenForActiveTab() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    Future.delayed(const Duration(milliseconds: 500), () {
      if (!mounted) return;

      for (var t in historyTrips) {
        if (t.passengerSeen == false) {
          FirebaseDatabase.instance.ref()
             .child('bookings')
             .child(user.uid)
             .child(t.bookingKey)
             .update({'passengerSeen': true});
        }
      }

      for (var item in _lostItems) {
        if (item['passengerSeen'] == false) {
          FirebaseDatabase.instance.ref()
             .child('forgottenItems')
             .child(item['driverId'])
             .child(item['id'])
             .update({'passengerSeen': true});
        }
      }
    });
  }

  int _asIntTimestamp(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  int _dateToComparableValue(String dateStr) {
    if (dateStr.contains('-')) {
      try {
        final d = DateTime.parse(dateStr);
        return d.millisecondsSinceEpoch;
      } catch (_) {}
    }
    try {
      final parts = dateStr.split('/');
      if (parts.length == 3) {
        final d = int.tryParse(parts[0]);
        final m = int.tryParse(parts[1]);
        final y = int.tryParse(parts[2]);
        if (d != null && m != null && y != null) {
          return DateTime(y, m, d).millisecondsSinceEpoch;
        }
      }
    } catch (_) {}
    return 0;
  }

  bool _isToday(String dateStr) {
     final now = DateTime.now();
     final todayStr = "${now.day}/${now.month}/${now.year}";
     final todayStr2 = "${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}";
     if (dateStr == todayStr || dateStr == todayStr2) return true;
     final todayIso = "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
     if (dateStr == todayIso) return true;
     if (dateStr.contains('-')) {
        try {
           final d = DateTime.parse(dateStr);
           return d.year == now.year && d.month == now.month && d.day == now.day;
        } catch (_) {}
     }
     try {
       final parts = dateStr.split('/');
       if (parts.length == 3) {
         final d = int.tryParse(parts[0]);
         final m = int.tryParse(parts[1]);
         final y = int.tryParse(parts[2]);
         if (d == now.day && m == now.month && y == now.year) return true;
       }
     } catch (_) {}
     return false;
  }

  bool _isItemToday(Map<String, dynamic> item) {
     if (item['timestamp'] != null) {
        final d = DateTime.fromMillisecondsSinceEpoch((item['timestamp'] as num).toInt());
        final now = DateTime.now();
        return d.year == now.year && d.month == now.month && d.day == now.day;
     }
     return _isToday(item['date']?.toString() ?? '');
  }

  Future<void> _passengerNegotiateDeliveryPrice(HistoryTrip trip, double newPrice) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final logId = DateTime.now().millisecondsSinceEpoch.toString();
      final logEntry = {
        'sender': 'passenger',
        'price': newPrice,
        'timestamp': ServerValue.timestamp,
      };

      final tripRef = FirebaseDatabase.instance.ref().child('trips').child(trip.tripId).child('takenSeats').child(trip.bookingKey);
      await tripRef.child('negotiationLog').child(logId).set(logEntry);
      await tripRef.update({
        'suggestedPrice': newPrice,
        'status': 'passenger_countered',
        'driverSeen': false,
      });
      final bookingRef = FirebaseDatabase.instance.ref().child('bookings').child(user.uid).child(trip.bookingKey);
      await bookingRef.child('negotiationLog').child(logId).set(logEntry);
      await bookingRef.update({
        'suggestedPrice': newPrice,
        'status': 'passenger_countered',
        'commissionAmount': PricingService.calculateCommission(newPrice),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم إرسال اقتراح السعر للسائق', style: TextStyle(color: Colors.white)), backgroundColor: Color(0xFF43C59E)));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  void _showPassengerNegotiateDialog(BuildContext context, HistoryTrip trip) {
     double currentPrice = trip.suggestedPrice ?? trip.price;
     if (currentPrice == 0) currentPrice = 500; // Default if 0
     
     final TextEditingController priceCtrl = TextEditingController(text: currentPrice.toStringAsFixed(0));
     showDialog(
       context: context,
       builder: (context) {
         return AlertDialog(
           title: const Text("تفاوض على السعر", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Color(0xFF43C59E))),
           shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
           content: TextField(
             controller: priceCtrl,
             keyboardType: TextInputType.number,
             decoration: InputDecoration(
               labelText: "سعر التوصيل المقترح",
               suffixText: "دج",
               filled: true,
               fillColor: Colors.grey.shade50,
               border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
               focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF43C59E))),
             ),
           ),
           actions: [
             TextButton(onPressed: () => Navigator.pop(context), child: const Text("إلغاء", style: TextStyle(color: Colors.grey))),
             ElevatedButton(
               onPressed: () {
                 final val = double.tryParse(priceCtrl.text) ?? 0.0;
                 if (val > 0) {
                    if (trip.isDelivery) {
                       double maxLimit = PricingService.getMaxPrice(trip.basePrice);
                       double minLimit = PricingService.getMinPrice(trip.basePrice);
                       if (val > maxLimit || val < minLimit) {
                         ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('السعر يجب أن يكون بين ${minLimit.toInt()} و ${maxLimit.toInt()} دج')));
                         return;
                       }
                    }
                    _passengerNegotiateDeliveryPrice(trip, val);
                    Navigator.pop(context);
                 }
               },
               style: ElevatedButton.styleFrom(
                 backgroundColor: const Color(0xFF43C59E),
                 shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
               ),
               child: const Text("تأكيد السعر", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
             )
           ],
         );
       }
     );
  }

  void _handleTabSelection() {
    if (_tabController.indexIsChanging) return;
    _markSeenForActiveTab();
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(_handleTabSelection);
    _loadHistory();
    _loadLostItems();
    _listenToPassengerActiveTrips();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _historySubscription?.cancel();
    _lostItemsSubscription?.cancel();
    _passengerTripsSubscription?.cancel();
    super.dispose();
  }

  void _loadHistory() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final historyRef = FirebaseDatabase.instance
        .ref()
        .child('bookings')
        .child(user.uid);

    _historySubscription = historyRef.onValue.listen((event) {
      if (event.snapshot.value == null) {
        setState(() {
          historyTrips = [];
        });
        return;
      }

      final Map<dynamic, dynamic> historyMap =
          event.snapshot.value as Map<dynamic, dynamic>;

      final List<HistoryTrip> trips = [];

      historyMap.forEach((key, value) {
        try {
          final tripData = value as Map<dynamic, dynamic>;
          final status = tripData['status']?.toString() ?? 'pending';
          
          double basePrice = (tripData['basePrice'] as num?)?.toDouble() ?? 
                             (tripData['price'] as num?)?.toDouble() ?? 0.0;
          
          final promoDiscount = (tripData['promoDiscount'] as num?)?.toDouble();
          final suggestedPrice = (tripData['suggestedPrice'] as num?)?.toDouble();
          
          double displayPrice = basePrice;

          if (suggestedPrice != null && (status == 'accepted' || status == 'pending')) {
             displayPrice = suggestedPrice;
          }

          if (promoDiscount != null && promoDiscount > 0) {
            displayPrice = displayPrice * (1 - (promoDiscount / 100));
            if (displayPrice < 0) displayPrice = 0;
          }

          final int seats = (tripData['seats'] as num?)?.toInt() ?? 
                            (tripData['seatsBooked'] as num?)?.toInt() ?? 1;
          final rawSeatIndices = tripData['seatIndices'];
          List<int> seatIndices = [];
          if (rawSeatIndices != null) {
            seatIndices = _extractSeatIndices(rawSeatIndices);
          }

          final rawSeatGenders = tripData['seatGenders'];
          Map<dynamic, dynamic> seatGenders = {};
          if (rawSeatGenders is Map) {
            seatGenders = Map<dynamic, dynamic>.from(rawSeatGenders);
          } else if (rawSeatGenders is List) {
            for (int i = 0; i < rawSeatGenders.length; i++) {
              if (rawSeatGenders[i] != null) seatGenders[i.toString()] = rawSeatGenders[i];
            }
          }

          final rawSeatLuggage = tripData['seatLuggage'];
          Map<dynamic, dynamic> seatLuggage = {};
          if (rawSeatLuggage is Map) {
            seatLuggage = Map<dynamic, dynamic>.from(rawSeatLuggage);
          } else if (rawSeatLuggage is List) {
            for (int i = 0; i < rawSeatLuggage.length; i++) {
              if (rawSeatLuggage[i] != null) seatLuggage[i.toString()] = rawSeatLuggage[i];
            }
          }

          final sortTs = _asIntTimestamp(tripData['bookingTimestamp']) > 0
              ? _asIntTimestamp(tripData['bookingTimestamp'])
              : (_asIntTimestamp(tripData['bookingTime']) > 0
                  ? _asIntTimestamp(tripData['bookingTime'])
                  : (_asIntTimestamp(tripData['timestamp']) > 0
                      ? _asIntTimestamp(tripData['timestamp'])
                      : _asIntTimestamp(tripData['createdAt'])));

          trips.add(
            HistoryTrip(
              id: tripData['requestId']?.toString() ?? key.toString(),
              bookingKey: key.toString(),
              tripId: tripData['tripId']?.toString() ?? '',
              from: tripData['from']?.toString() ?? '',
              to: tripData['to']?.toString() ?? '',
              date: tripData['date']?.toString() ?? '',
              time: tripData['time']?.toString() ?? '',
              basePrice: basePrice,
              price: displayPrice,
              vehicleName: tripData['driverName']?.toString() ?? 'سائق',
              status: status,
              suggestedPrice: suggestedPrice,
              hasPackage: tripData['hasPackage'] == true,
              seats: seats > 0 ? seats : 1,
              luggagePrice: 0, 
              promoCode: tripData['promoCode']?.toString(),
              transportType: tripData['transportType']?.toString() ?? tripData['transport_type']?.toString() ?? 'car',
              driverId: tripData['driverId']?.toString() ?? '',
              gender: tripData['gender']?.toString() ?? 'بدون تفضيل',
              seatIndices: seatIndices,
              seatGenders: seatGenders,
              seatLuggage: seatLuggage,
              totalSeats: (tripData['totalSeats'] as num?)?.toInt() ?? 4,
              packageType: tripData['packageType']?.toString(),
              packageDetails: tripData['packageDetails']?.toString(),
              senderName: tripData['senderName']?.toString(),
              senderPhone: tripData['senderPhone']?.toString(),
              passengerName: tripData['username']?.toString() ?? tripData['userName']?.toString() ?? tripData['senderName']?.toString(),
              isDelivery: tripData['isDelivery'] == true || tripData['transportType'] == 'package' || tripData['packageType'] != null,
              sortTimestamp: sortTs,
              otp: tripData['otp']?.toString(),
              otpMsg: tripData['otpMsg']?.toString(),
              deliveryStatus: tripData['deliveryStatus']?.toString(),
              passengerSeen: tripData['passengerSeen'] ?? true,
              isRejoin: tripData['isRejoin'] == true,
            ),
          );
        } catch (e) {
          debugPrint("Error parsing trip in history: $e");
        }
      });

      trips.sort((a, b) {
        if (b.sortTimestamp != a.sortTimestamp) {
          return b.sortTimestamp.compareTo(a.sortTimestamp);
        }
        return _dateToComparableValue(b.date).compareTo(_dateToComparableValue(a.date));
      });

      setState(() {
        historyTrips = trips;
      });
      _markSeenForActiveTab();
    });
  }

  void _loadLostItems() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // Listen to all forgotten items to find those reported by this passenger
    _lostItemsSubscription = FirebaseDatabase.instance
        .ref()
        .child('forgottenItems')
        .onValue
        .listen((event) {
      final data = event.snapshot.value as Map<dynamic, dynamic>?;
      if (data == null) {
        if (mounted) setState(() { _lostItems = []; });
        return;
      }

      final List<Map<String, dynamic>> items = [];
      
      // forgottenItems is structured as: forgottenItems -> driverId -> itemId -> itemData
      data.forEach((driverId, driverItems) {
        final itemsMap = driverItems as Map<dynamic, dynamic>;
        itemsMap.forEach((itemId, itemData) {
          final item = Map<String, dynamic>.from(itemData as Map);
          if (item['passengerId'] == user.uid) {
            item['driverId'] = driverId;
            items.add(item);
          }
        });
      });

      items.sort((a, b) => (b['timestamp'] ?? 0).compareTo(a['timestamp'] ?? 0));

      if (mounted) {
        setState(() {
          _lostItems = items;
        });
        _markSeenForActiveTab();
      }
    });
  }

  void _listenToPassengerActiveTrips() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final historyRef = FirebaseDatabase.instance.ref().child('bookings').child(user.uid);
    
    _passengerTripsSubscription = historyRef.onValue.listen((event) {
      if (!mounted || event.snapshot.value == null) return;
      
      final data = event.snapshot.value as Map<dynamic, dynamic>;
      data.forEach((key, value) {
        final bookingData = Map<String, dynamic>.from(value as Map);
        
        // If driver just started the trip and passenger hasn't responded yet
        if (bookingData['tripStatus'] == 'starting' && 
            bookingData['passengerConfirmed'] == null &&
            bookingData['status'] == 'accepted') {
            
            _showStartTripConfirmationDialog(bookingData['tripId']?.toString() ?? '', key.toString(), bookingData);
        }
      });
    });
  }

  void _showStartTripConfirmationDialog(String tripId, String historyKey, Map<String, dynamic> bookingData) {
    if (_showingDialogForTripId == tripId || !mounted) return;
    _showingDialogForTripId = tripId;

    final driverName = bookingData['driverName'] ?? 'سائق';
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text("بدء الرحلة", style: TextStyle(color: Color(0xFF43C59E), fontWeight: FontWeight.bold)),
          content: Text("هل بدأت الرحلة؟ هل أنت داخل مركبة $driverName؟"),
          actions: [
            TextButton(
              onPressed: () {
                _handlePassengerConfirmation(tripId, historyKey, bookingData, false);
                Navigator.pop(context);
                _showingDialogForTripId = null;
              },
              child: const Text("لا", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
            ),
            ElevatedButton(
              onPressed: () {
                _handlePassengerConfirmation(tripId, historyKey, bookingData, true);
                Navigator.pop(context);
                _showingDialogForTripId = null;
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF43C59E),
              ),
              child: const Text("نعم", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      }
    );
  }

  Future<void> _handlePassengerConfirmation(String tripId, String historyKey, Map<String, dynamic> bookingData, bool isConfirmed) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      await FirebaseDatabase.instance.ref()
          .child('bookings')
          .child(user.uid)
          .child(historyKey)
          .update({'passengerConfirmed': isConfirmed});

      final tripRef = FirebaseDatabase.instance.ref().child('trips').child(tripId);
      final tripSnapshot = await tripRef.get();
      if (tripSnapshot.exists) {
         final tripMap = tripSnapshot.value as Map<dynamic, dynamic>;
         final takenSeats = tripMap['takenSeats'] as Map<dynamic, dynamic>?;
         if (takenSeats != null) {
            String? seatIndex;
            for (var entry in takenSeats.entries) {
               final seatVal = entry.value as Map<dynamic, dynamic>;
               if (seatVal['userId'] == user.uid) {
                  seatIndex = entry.key.toString();
                  break;
               }
            }
            if (seatIndex != null) {
               await tripRef.child('takenSeats').child(seatIndex).update({'passengerConfirmed': isConfirmed});
            }
         }
      }
    } catch(e) {
      debugPrint("Error confirming passenger trip: $e");
    }
  }

  void _onBottomNavTapped(int index) {
    if (index == _currentIndex) return;

    setState(() {
      _currentIndex = index;
    });

    if (index == 0) {
      Navigator.pushReplacementNamed(context, '/home');
    } else if (index == 2) {
      Navigator.pushReplacementNamed(context, '/messages');
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

  @override
  Widget build(BuildContext context) {
    final passengerTrips = historyTrips.where((t) => !t.isDelivery).toList();
    final packageTrips = historyTrips.where((t) => t.isDelivery).toList();

    final passengerUnseenCount = passengerTrips.where((t) => !t.passengerSeen).length;
    final packageUnseenCount = packageTrips.where((t) => !t.passengerSeen).length;
    final lostUnseenCount = _lostItems.where((t) => t['passengerSeen'] == false).length;

    return WillPopScope(
      onWillPop: () async {
        Navigator.pushReplacementNamed(context, '/home');
        return false;
      },
      child: Scaffold(
        backgroundColor: Colors.grey[100],
        appBar: AppBar(
          backgroundColor: const Color(0xFF43C59E),
          elevation: 0,
          centerTitle: false,
          title: const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'رحلاتي', // keep your title
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
          ),
          actions: const [
            GlobalAppBarActions(), // adds settings, logout, avatar, etc. just like DiscountPage
          ],
        ),
      body: Column(
        children: [
          Container(
            color: Colors.white,
            child: TabBar(
              controller: _tabController,
              isScrollable: true,
              tabAlignment: TabAlignment.center,
              labelPadding: const EdgeInsets.symmetric(horizontal: 24),
              labelColor: const Color(0xFF43C59E),
              unselectedLabelColor: Colors.grey,
              indicatorColor: const Color(0xFF43C59E),
              labelStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              unselectedLabelStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              tabs: [
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text("الرحلات"),
                      if (passengerUnseenCount > 0) ...[
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.all(5),
                          decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                          child: Text(passengerUnseenCount.toString(), style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                        )
                      ]
                    ],
                  ),
                ),
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text("الطرود"),
                      if (packageUnseenCount > 0) ...[
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.all(5),
                          decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                          child: Text(packageUnseenCount.toString(), style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                        )
                      ]
                    ],
                  ),
                ),
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text("المفقودات"),
                      if (lostUnseenCount > 0) ...[
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.all(5),
                          decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                          child: Text(lostUnseenCount.toString(), style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                        )
                      ]
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildTripsList(passengerTrips, "لا توجد رحلات سابقة بعد", "ستظهر رحلاتك كراكب المنتهية هنا."),
                _buildTripsList(packageTrips, "لا توجد عمليات توصيل طرود", "ستظهر عمليات توصيل الطرود المنتهية هنا."),
                _buildLostItemsList(_lostItems),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: Directionality(
        textDirection: TextDirection.ltr,
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          type: BottomNavigationBarType.fixed,
          selectedItemColor: const Color(0xFF43C59E),
          unselectedItemColor: Colors.grey,
          backgroundColor: Colors.white,
          elevation: 10,
          onTap: _onBottomNavTapped,
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.home), label: 'الرئيسية'),
            BottomNavigationBarItem(icon: HistoryBadge(child: Icon(Icons.history)), label: 'السجل'),
            BottomNavigationBarItem(icon: MessageBadge(child: Icon(Icons.message)), label: 'الرسائل'),
            BottomNavigationBarItem(
              icon: Icon(Icons.local_shipping),
              label: 'توصيل',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.discount),
              label: 'خصومات',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.menu_book),
              label: 'اقرأ',
            ),
          ],
        ),
      ),
      ),
    );
  }

  Widget _buildTripsList(List<HistoryTrip> trips, String emptyTitle, String emptySubtitle) {
    if (trips.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(30),
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withValues(alpha: 0.2),
                    blurRadius: 4,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: const Icon(
                Icons.history_toggle_off,
                size: 60,
                color: Color(0xFF43C59E),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              emptyTitle,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              emptySubtitle,
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: trips.length,
      itemBuilder: (context, index) {
        return _buildHistoryCard(trips[index]);
      },
    );
  }

  Widget _buildLostItemsList(List<Map<String, dynamic>> items) {
    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(30),
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withValues(alpha: 0.2),
                    blurRadius: 4,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: const Icon(
                Icons.help_outline,
                size: 60,
                color: Color(0xFF43C59E),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              "لم يتم الإبلاغ عن عناصر مفقودة",
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "ستظهر العناصر التي أبلغت عن نسيانها هنا.",
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        final isResolved = item['status'] != 'Pending';
        
        return Container(
          margin: const EdgeInsets.only(bottom: 20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 5,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                decoration: BoxDecoration(
                  color: isResolved ? Colors.grey.shade50 : Colors.orange.shade50,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Icon(Icons.help_outline, color: isResolved ? Colors.grey : Colors.orange, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              "السائق: ${item['driverName']} • ${item['date']}",
                              style: TextStyle(
                                fontWeight: FontWeight.bold, 
                                fontSize: 12, 
                                color: isResolved ? Colors.grey.shade700 : Colors.orange.shade800
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      item['status'] == 'Found' ? 'تم العثور عليه' : (item['status'] == 'Not Found' ? 'لم يتم العثور عليه' : 'قيد الانتظار'),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: item['status'] == 'Found' 
                            ? const Color(0xFF43C59E) 
                            : (item['status'] == 'Not Found' ? Colors.red : Colors.orange),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("الرحلة: ${item['from']} → ${item['to']}", style: const TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    Text("الوصف: ${item['description']}", style: TextStyle(color: Colors.grey.shade700)),
                    const SizedBox(height: 4),
                    Text("الموقع المحتمل: ${item['location']}", style: TextStyle(color: Colors.grey.shade700)),
                    if (item['status'] == 'Found') ...[
                      const SizedBox(height: 8),
                      FutureBuilder<DataSnapshot>(
                        future: FirebaseDatabase.instance.ref().child('users').child(item['driverId']).child('phone').get(),
                        builder: (context, snapshot) {
                          if (snapshot.hasData && snapshot.data!.value != null) {
                            return Text(
                              "تواصل مع السائق لاسترجاعه: ${snapshot.data!.value}",
                              style: TextStyle(
                                color: Colors.green.shade700,
                                fontWeight: FontWeight.bold,
                              ),
                            );
                          }
                          return const SizedBox.shrink();
                        },
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  dynamic _resolveSeatMap(Map<dynamic, dynamic> map, dynamic seatIndex, List<int> seatIndices) {
    if (map[seatIndex] != null) return map[seatIndex];
    if (map[seatIndex.toString()] != null) return map[seatIndex.toString()];

    int parsedIndex = int.tryParse(seatIndex.toString()) ?? -1;
    if (parsedIndex != -1 && map[parsedIndex] != null) return map[parsedIndex];

    for (final entry in map.entries) {
      final keyIndex = int.tryParse(entry.key.toString().replaceAll(RegExp(r'[^0-9]'), ''));
      if (keyIndex == parsedIndex) return entry.value;
    }

    if (parsedIndex != -1) {
      int relativeIndex = seatIndices.indexOf(parsedIndex);
      if (relativeIndex != -1) {
        if (map[relativeIndex] != null) return map[relativeIndex];
        if (map[relativeIndex.toString()] != null) return map[relativeIndex.toString()];
      }
    }
    
    return null;
  }

  String _getSeatsDescription(HistoryTrip trip) {
    int regular = 0;
    int withLuggage = 0;
    int baby = 0;
    int babyWithLuggage = 0;
    int seatsBooked = trip.seats > 0 ? trip.seats : 1;

    final indices = trip.seatIndices.isNotEmpty 
        ? trip.seatIndices 
        : _extractSeatIndices(trip.seatIndices); // robust fallback

    final genders = trip.seatGenders;
    final luggages = trip.seatLuggage;

    if (indices.isNotEmpty) {
      for (var idx in indices) {
        String gender = _normalizeGenderToken(
          _resolveSeatMap(genders, idx, indices)?.toString() ?? 
          trip.gender
        );
        if (gender.isEmpty || gender == 'بدون تفضيل') gender = 'male';

        dynamic lugVal = _resolveSeatMap(luggages, idx, indices);
        bool luggage = lugVal == true || lugVal.toString().toLowerCase() == 'true';
        
        if (gender == 'kids') {
          if (luggage) babyWithLuggage++;
          else baby++;
        } else if (luggage) {
          withLuggage++;
        } else {
          regular++;
        }
      }
    } else if (luggages.isNotEmpty || genders.isNotEmpty) {
      int processed = 0;
      final Set<dynamic> allKeys = {...luggages.keys, ...genders.keys};
      for (var key in allKeys) {
        if (processed >= seatsBooked) break;
        String gender = _normalizeGenderToken(genders[key.toString()]?.toString() ?? genders[key]?.toString() ?? trip.gender);
        if (gender.isEmpty || gender == 'بدون تفضيل') gender = 'male';
        bool luggage = luggages[key.toString()] == true || luggages[key] == true;
        
        if (gender == 'kids') {
          if (luggage) babyWithLuggage++;
          else baby++;
        } else if (luggage) {
          withLuggage++;
        } else {
          regular++;
        }
        processed++;
      }
      while (processed < seatsBooked) {
         if (trip.gender == 'kids') baby++;
         else regular++;
         processed++;
      }
    } else {
      String gender = _normalizeGenderToken(trip.gender);
      if (gender.isEmpty || gender == 'بدون تفضيل') gender = 'male';
      bool hasPackage = trip.hasPackage;

      if (gender == 'kids') {
         if (hasPackage) {
           babyWithLuggage = 1;
           baby = seatsBooked > 1 ? seatsBooked - 1 : 0;
         } else {
           baby = seatsBooked;
         }
      } else if (hasPackage) {
         withLuggage = 1;
         regular = seatsBooked > 1 ? seatsBooked - 1 : 0;
      } else {
         regular = seatsBooked;
      }
    }

    List<String> parts = [];
    if (regular > 0) parts.add('\u200F$regular مقعد عادي\u200F');
    if (withLuggage > 0) parts.add('\u200F$withLuggage مقعد مع أمتعة\u200F');
    if (baby > 0) parts.add('\u200F$baby مقعد طفل\u200F');
    if (babyWithLuggage > 0) parts.add('\u200F$babyWithLuggage مقعد طفل مع أمتعة\u200F');

    if (parts.isEmpty) return '\u200F$seatsBooked مقعد عادي\u200F';
    return parts.join(' و ');
  }

  Widget _buildHistoryCard(HistoryTrip trip) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 5,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF43C59E).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        trip.date,
                        style: const TextStyle(
                          color: Color(0xFF43C59E),
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    StreamBuilder<DatabaseEvent>(
                      stream: FirebaseDatabase.instance
                          .ref()
                          .child('bookings')
                          .child(FirebaseAuth.instance.currentUser!.uid)
                          .child(trip.bookingKey)
                          .onValue,
                      builder: (context, snapshot) {
                        String currentStatus = trip.status;
                        
                        if (snapshot.hasData && snapshot.data!.snapshot.value != null) {
                          final data = snapshot.data!.snapshot.value as Map<dynamic, dynamic>;
                          currentStatus = data['status']?.toString() ?? trip.status;
                          debugPrint("Passenger Stream bookingKey=${trip.bookingKey} | Status is now: $currentStatus");
                        } else {
                          debugPrint("Passenger Stream bookingKey=${trip.bookingKey} | Status: $currentStatus (No change)");
                        }

                        Color bgColor;
                        Color borderColor;
                        Color textColor;
                        String displayText;

                        switch (currentStatus.toLowerCase()) {
                          case 'accepted':
                            bgColor = Colors.green.shade50;
                            borderColor = Colors.green;
                            textColor = Colors.green;
                            displayText = 'تم القبول';
                            break;
                          case 'rejected':
                          case 'refused':
                            bgColor = Colors.red.shade50;
                            borderColor = Colors.red;
                            textColor = Colors.red;
                            displayText = 'مرفوض';
                            break;
                          case 'cancelled':
                            bgColor = Colors.red.shade50;
                            borderColor = Colors.red;
                            textColor = Colors.red;
                            displayText = 'ملغاة';
                            break;
                          case 'driver_countered':
                            bgColor = Colors.blue.shade50;
                            borderColor = Colors.blue;
                            textColor = Colors.blue;
                            displayText = 'تم إرسال العرض';
                            break;
                          case 'passenger_countered':
                            bgColor = Colors.purple.shade50;
                            borderColor = Colors.purple;
                            textColor = Colors.purple;
                            displayText = 'تم تقديم عرض مضاد';
                            break;
                          case 'تم التسليم بنجاح':
                          case 'تم التسليم':
                          case 'completed':
                            bgColor = Colors.teal.shade50;
                            borderColor = Colors.teal;
                            textColor = Colors.teal;
                            displayText = currentStatus == 'completed' ? 'مكتمل' : 'تم التسليم بنجاح';
                            break;
                          case 'pending':
                          case 'booked':
                          default:
                            if (trip.isRejoin) {
                              bgColor = Colors.blue.shade50;
                              borderColor = Colors.blue;
                              textColor = Colors.blue;
                              displayText = 'طلب إعادة الانضمام للرحلة';
                            } else {
                              bgColor = Colors.orange.shade50;
                              borderColor = Colors.orange;
                              textColor = Colors.orange;
                              displayText = 'قيد الانتظار';
                            }
                            break;
                        }

                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: bgColor,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: borderColor,
                            ),
                          ),
                          child: Text(
                            displayText,
                            style: TextStyle(
                              color: textColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 10,
                            ),
                          ),
                        );
                      }
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Column(
                      children: [
                        const Icon(
                          Icons.circle,
                          color: Color(0xFF43C59E),
                          size: 12,
                        ),
                        Container(
                          height: 24,
                          width: 2,
                          color: Colors.grey.shade200,
                          margin: const EdgeInsets.symmetric(vertical: 4),
                        ),
                        const Icon(
                          Icons.location_on,
                          color: Colors.pink,
                          size: 12,
                        ),
                      ],
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            trip.from,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            trip.to,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (!trip.isDelivery)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.chair_alt, size: 16, color: Colors.grey),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            _getSeatsDescription(trip),
                            textDirection: TextDirection.rtl,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                              color: Colors.black87,
                            ),
                            softWrap: true,
                            overflow: TextOverflow.visible,
                          ),
                        ),
                        if (trip.promoCode != null && trip.promoCode!.isNotEmpty) ...[
                          const SizedBox(width: 16),
                          const Icon(Icons.local_offer, size: 16, color: Color(0xFF43C59E)),
                          const SizedBox(width: 4),
                          Text(
                            trip.promoCode!,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: Color(0xFF43C59E),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                const SizedBox(height: 20),
                const Divider(height: 1),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        UserProfileAvatar(
                          userId: trip.driverId,
                          radius: 16,
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              trip.vehicleName,
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          trip.isDelivery
                             ? '${(trip.suggestedPrice ?? trip.price).toStringAsFixed(0)} د.ج'
                             : (trip.price > 0
                                ? '${(trip.suggestedPrice != null && trip.status == 'accepted' ? trip.suggestedPrice! : trip.price).toStringAsFixed(0)} د.ج'
                                : '0 د.ج'),
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color:
                                trip.suggestedPrice != null &&
                                    trip.status == 'accepted'
                                ? const Color(0xFF43C59E)
                                : Colors.black,
                          ),
                        ),
                        if (!trip.isDelivery && trip.suggestedPrice != null &&
                            trip.price > 0 &&
                            trip.price != trip.suggestedPrice &&
                            trip.status == 'accepted')
                          Text(
                            '${trip.price.toStringAsFixed(0)} د.ج',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                              decoration: TextDecoration.lineThrough,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
                if (trip.isDelivery)
                  Padding(
                    padding: const EdgeInsets.only(top: 12.0),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.orange.shade200),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: const [
                              Icon(Icons.inventory_2, size: 16, color: Colors.orange),
                              SizedBox(width: 8),
                              Text(
                                "تفاصيل الطرد",
                                style: TextStyle(color: Colors.orange, fontSize: 13, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          if (trip.packageType != null && trip.packageType!.isNotEmpty)
                            Text("النوع: ${trip.packageType}", style: TextStyle(fontSize: 12, color: Colors.orange.shade800)),
                          if (trip.packageDetails != null && trip.packageDetails!.isNotEmpty)
                            Text("الوصف: ${trip.packageDetails}", style: TextStyle(fontSize: 12, color: Colors.orange.shade800)),
                          if (trip.passengerName != null && trip.passengerName!.isNotEmpty)
                            Text("اسم طالب التوصيل: ${trip.passengerName}", style: TextStyle(fontSize: 12, color: Colors.orange.shade800)),
                          if (trip.senderName != null && trip.senderName!.isNotEmpty)
                            Text("اسم المرسل إليه (المستلم): ${trip.senderName}", style: TextStyle(fontSize: 12, color: Colors.orange.shade800)),
                          if (trip.senderPhone != null && trip.senderPhone!.isNotEmpty)
                            Text("رقم التواصل: ${trip.senderPhone}", style: TextStyle(fontSize: 12, color: Colors.orange.shade800)),
                        ],
                      ),
                    ),
                  ),

                if (trip.isDelivery && (trip.status == 'accepted' || trip.status == 'completed' || trip.status == 'تم التسليم' || trip.status == 'تم التسليم بنجاح' || trip.deliveryStatus == 'completed' || trip.deliveryStatus == 'تم التسليم' || trip.deliveryStatus == 'تم التسليم بنجاح'))
                  Padding(
                    padding: const EdgeInsets.only(top: 12.0),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: ((trip.deliveryStatus == 'completed' || trip.deliveryStatus == 'تم التسليم' || trip.deliveryStatus == 'تم التسليم بنجاح') || (trip.status == 'completed' || trip.status == 'تم التسليم' || trip.status == 'تم التسليم بنجاح')) ? Colors.green.shade50 : const Color(0xFF43C59E).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: ((trip.deliveryStatus == 'completed' || trip.deliveryStatus == 'تم التسليم' || trip.deliveryStatus == 'تم التسليم بنجاح') || (trip.status == 'completed' || trip.status == 'تم التسليم' || trip.status == 'تم التسليم بنجاح')) ? Colors.green.shade200 : const Color(0xFF43C59E).withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            ((trip.deliveryStatus == 'completed' || trip.deliveryStatus == 'تم التسليم' || trip.deliveryStatus == 'تم التسليم بنجاح') || (trip.status == 'completed' || trip.status == 'تم التسليم' || trip.status == 'تم التسليم بنجاح')) ? Icons.check_circle : Icons.password_rounded,
                            color: ((trip.deliveryStatus == 'completed' || trip.deliveryStatus == 'تم التسليم' || trip.deliveryStatus == 'تم التسليم بنجاح') || (trip.status == 'completed' || trip.status == 'تم التسليم' || trip.status == 'تم التسليم بنجاح')) ? Colors.green : const Color(0xFF43C59E),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ((trip.deliveryStatus == 'completed' || trip.deliveryStatus == 'تم التسليم' || trip.deliveryStatus == 'تم التسليم بنجاح') || (trip.status == 'completed' || trip.status == 'تم التسليم' || trip.status == 'تم التسليم بنجاح'))
                                ? const Text(
                                    "تم التحقق من الرمز بنجاح",
                                    style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green, fontSize: 16),
                                  )
                                : Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        "رمز تأكيد التسليم (OTP)",
                                        style: TextStyle(fontSize: 12, color: Colors.black54),
                                      ),
                                      const SizedBox(height: 4),
                                      StreamBuilder<DatabaseEvent>(
                                        stream: FirebaseDatabase.instance.ref().child('bookings').child(FirebaseAuth.instance.currentUser!.uid).child(trip.bookingKey).onValue,
                                        builder: (context, snapshot) {
                                          if (!snapshot.hasData || snapshot.data!.snapshot.value == null) {
                                            return Text(
                                              trip.otp ?? '...جاري انشاء الرمز',
                                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20, letterSpacing: 1, color: Color(0xFF43C59E)),
                                            );
                                          }
                                          
                                          final data = snapshot.data!.snapshot.value as Map<dynamic, dynamic>;
                                          final currentOtp = data['otp']?.toString() ?? trip.otp ?? '...جاري انشاء الرمز';
                                          final currentOtpMsg = data['otpMsg']?.toString();
                                          final hasOtpChanged = (trip.otp ?? '').isNotEmpty && currentOtp != trip.otp;
                                          final noticeMessage = (currentOtpMsg != null && currentOtpMsg.trim().isNotEmpty)
                                              ? currentOtpMsg
                                              : (hasOtpChanged ? 'تم تحديث رمز التحقق' : null);
                                          
                                          return Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                currentOtp,
                                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20, letterSpacing: 1, color: Color(0xFF43C59E)),
                                              ),
                                              if (noticeMessage != null)
                                                Container(
                                                  margin: const EdgeInsets.only(top: 8.0, bottom: 4.0),
                                                  padding: const EdgeInsets.all(8),
                                                  decoration: BoxDecoration(
                                                    color: Colors.red.shade50,
                                                    borderRadius: BorderRadius.circular(8),
                                                    border: Border.all(color: Colors.red.shade200),
                                                  ),
                                                  child: Row(
                                                    children: [
                                                      const Icon(Icons.info_outline, color: Colors.red, size: 20),
                                                      const SizedBox(width: 8),
                                                      Expanded(
                                                        child: Text(
                                                          noticeMessage,
                                                          style: const TextStyle(color: Colors.red, fontSize: 13, fontWeight: FontWeight.bold),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                            ],
                                          );
                                        }
                                      ),
                                      const SizedBox(height: 4),
                                      const Text(
                                        "يرجى تزويد المستلم بهذا الرمز. سيطلبه السائق لتأكيد التسليم.",
                                        style: TextStyle(fontSize: 11, color: Colors.black54, height: 1.3),
                                      ),
                                    ],
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ),

                if (trip.isDelivery)
                   StreamBuilder<DatabaseEvent>(
                     stream: FirebaseDatabase.instance.ref().child('bookings').child(FirebaseAuth.instance.currentUser!.uid).child(trip.bookingKey).child('negotiationLog').orderByChild('timestamp').onValue,
                     builder: (context, snapshot) {
                        if (!snapshot.hasData || snapshot.data!.snapshot.value == null) return const SizedBox.shrink();
                        
                        final logsRaw = snapshot.data!.snapshot.value;
                        List<Map<dynamic, dynamic>> logs = [];
                        if (logsRaw is Map) {
                           logsRaw.forEach((key, value) {
                             if (value is Map) logs.add(value);
                           });
                        }
                        if (logs.isEmpty) return const SizedBox.shrink();

                        logs.sort((a, b) => (a['timestamp'] ?? 0).compareTo(b['timestamp'] ?? 0));

                        return Container(
                          margin: const EdgeInsets.only(top: 12),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey.shade200),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.history, size: 16, color: Colors.grey.shade700),
                                  const SizedBox(width: 8),
                                  Text("سجل التفاوض", style: TextStyle(color: Colors.grey.shade700, fontSize: 13, fontWeight: FontWeight.bold)),
                                ],
                              ),
                              const SizedBox(height: 8),
                              ...logs.map((log) {
                                 bool isDriver = log['sender'] == 'driver';
                                 return Padding(
                                   padding: const EdgeInsets.only(bottom: 4),
                                   child: Row(
                                     mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                     children: [
                                       Text(isDriver ? "عرض السائق:" : "عرضك:", style: TextStyle(fontSize: 12, color: isDriver ? const Color(0xFF43C59E) : Colors.blue.shade700)),
                                       Text("${log['price']} د.ج", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                     ],
                                   ),
                                 );
                              }).toList(),
                            ],
                          ),
                        );
                     }
                   ),

                if (trip.isDelivery && (trip.status == 'pending' || trip.status == 'driver_countered') && trip.suggestedPrice != null && trip.price != trip.suggestedPrice) ...[
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        flex: 1,
                        child: TextButton(
                          onPressed: () async {
                              await FirebaseDatabase.instance.ref()
                                 .child('trips')
                                 .child(trip.tripId)
                                 .child('takenSeats')
                                 .child(trip.bookingKey)
                                 .update({'status': 'refused', 'driverSeen': false});
                              await FirebaseDatabase.instance.ref()
                                 .child('bookings')
                                 .child(FirebaseAuth.instance.currentUser!.uid)
                                 .child(trip.bookingKey)
                                 .update({'status': 'refused'});
                              if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم رفض العرض')));
                          },
                          style: TextButton.styleFrom(
                            backgroundColor: Colors.red.shade50,
                            foregroundColor: Colors.red,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          child: const Text("رفض", style: TextStyle(fontWeight: FontWeight.bold)),
                        )
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: OutlinedButton(
                          onPressed: () => _showPassengerNegotiateDialog(context, trip),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Color(0xFF43C59E)),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          child: const Text("تفاوض", style: TextStyle(color: Color(0xFF43C59E), fontWeight: FontWeight.bold)),
                        )
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton(
                          onPressed: () async {
                             // Passenger accepts driver's suggested price, instantly confirms
                             await FirebaseDatabase.instance.ref()
                                .child('trips')
                                .child(trip.tripId)
                                .child('takenSeats')
                                .child(trip.bookingKey)
                                .update({'status': 'accepted', 'price': trip.suggestedPrice, 'driverSeen': false});
                             await FirebaseDatabase.instance.ref()
                                .child('bookings')
                                .child(FirebaseAuth.instance.currentUser!.uid)
                                .child(trip.bookingKey)
                                .update({'status': 'accepted', 'price': trip.suggestedPrice});
                             if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم تأكيد الحجز')));
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF43C59E),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          child: const Text("قبول السعر", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        )
                      ),
                    ]
                  )
                ],
                if ((trip.status.toLowerCase() == 'accepted' || trip.status.toLowerCase() == 'cancelled') && !trip.isDelivery) ...[
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () => _showPassengerReservedSeatModal(context, trip),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF43C59E),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      icon: const Icon(
                        Icons.event_seat,
                        color: Colors.white,
                        size: 18,
                      ),
                      label: const Text(
                        "سجل الرحلة",
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  if (trip.status.toLowerCase() == 'accepted')
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => ReportForgottenItemPage(
                                  tripId: trip.tripId,
                                  driverName: trip.vehicleName, 
                                  date: trip.date,
                                  from: trip.from,
                                  to: trip.to,
                                ),
                              ),
                            );
                          },
                          icon: const Icon(
                            Icons.help_outline,
                            size: 16,
                            color: Colors.orange,
                          ),
                          label: const Text(
                            "عنصر مفقود",
                            style: TextStyle(color: Colors.orange),
                          ),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Colors.orange),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'accepted':
        return Colors.green;
      case 'refused':
      case 'rejected':
        return Colors.red;
      case 'pending':
      case 'booked':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  Future<void> _shareTripDetails(HistoryTrip trip) async {
    try {
      String vehicleType = "غير محدد";
      String vehicleColor = "غير محدد";
      String plateNumber = "غير محدد";

      if (trip.driverId.isNotEmpty) {
        final driverSnap = await FirebaseDatabase.instance.ref().child('users').child(trip.driverId).get();
        if (driverSnap.exists && driverSnap.value is Map) {
          final driverData = driverSnap.value as Map<dynamic, dynamic>;
          vehicleType = driverData['vehicleType']?.toString() ?? "غير محدد";
          vehicleColor = driverData['vehicleColor']?.toString() ?? "غير محدد";
          plateNumber = driverData['plateNumber']?.toString() ?? "غير محدد";
        }
      }

      final shareText = '''
تفاصيل الرحلة (تطبيق راحتي)
من: ${trip.from}
إلى: ${trip.to}
التاريخ: ${trip.date}
السائق: ${trip.vehicleName}
المركبة: $vehicleType ($vehicleColor)
لوحة التسجيل: $plateNumber
'''.trim();

      await Share.share(shareText, subject: 'تفاصيل مسار رحلتي');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تعذر جلب تفاصيل المشاركة.')));
      }
    }
  }

  void _showReportProblemDialog(BuildContext context, HistoryTrip trip) {
    String selectedProblemType = 'تأخير';
    final List<String> problemTypes = ['تأخير', 'سلوك السائق', 'مشكلة في الدفع', 'مشكلة في الحجز', 'أخرى'];
    final TextEditingController descriptionController = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Row(
                children: [
                  Icon(Icons.report_problem, color: Colors.red),
                  SizedBox(width: 8),
                  Text("الإبلاغ عن مشكلة", style: TextStyle(color: Colors.red, fontSize: 18, fontWeight: FontWeight.bold)),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("نوع المشكلة", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          isExpanded: true,
                          value: selectedProblemType,
                          items: problemTypes.map((val) => DropdownMenuItem(value: val, child: Text(val))).toList(),
                          onChanged: (val) {
                            if (val != null) setState(() => selectedProblemType = val);
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text("الوصف (اختياري)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: descriptionController,
                      maxLines: 3,
                      decoration: InputDecoration(
                        hintText: "صف المشكلة باختصار...",
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        contentPadding: const EdgeInsets.all(12),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text("إلغاء", style: TextStyle(color: Colors.grey)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () async {
                    final desc = descriptionController.text.trim();
                    try {
                      final logRef = FirebaseDatabase.instance.ref().child('reports').push();
                      await logRef.set({
                        'tripId': trip.tripId,
                        'bookingKey': trip.bookingKey,
                        'passengerId': FirebaseAuth.instance.currentUser?.uid,
                        'driverId': trip.driverId,
                        'problemType': selectedProblemType,
                        'description': desc,
                        'timestamp': ServerValue.timestamp,
                        'status': 'pending',
                      });
                      if (dialogContext.mounted) {
                        Navigator.pop(dialogContext);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text("تم إرسال بلاغك بنجاح. فريق الدعم سيتابع الحالة قريباً.", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                            backgroundColor: Colors.green,
                          ),
                        );
                      }
                    } catch (e) {
                       if (dialogContext.mounted) {
                         ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("حدث خطأ أثناء الإرسال: $e")));
                       }
                    }
                  },
                  child: const Text("إرسال البلاغ", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ],
            );
          }
        );
      }
    );
  }

  Future<Map<dynamic, dynamic>?> _fetchPassengerBookingForSeatModal(HistoryTrip trip) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final seatsRef =
        FirebaseDatabase.instance.ref().child('trips').child(trip.tripId).child('takenSeats');
    final direct = await seatsRef.child(trip.bookingKey).get();
    if (direct.exists && direct.value is Map) {
      return Map<dynamic, dynamic>.from(direct.value as Map);
    }
    final all = await seatsRef.get();
    if (!all.exists || all.value is! Map) return null;
    final map = all.value as Map<dynamic, dynamic>;
    final alt = map[trip.bookingKey];
    if (alt is Map) return Map<dynamic, dynamic>.from(alt);
    for (final e in map.entries) {
      if (e.value is Map) {
        final m = e.value as Map<dynamic, dynamic>;
        if (m['bookingKey']?.toString() == trip.bookingKey) {
          return Map<dynamic, dynamic>.from(m);
        }
      }
    }
    if (uid != null) {
      for (final e in map.entries) {
        if (e.value is Map) {
          final m = e.value as Map<dynamic, dynamic>;
          if (m['userId']?.toString() == uid) {
            return Map<dynamic, dynamic>.from(m);
          }
        }
      }
    }
    return null;
  }

  String _normalizeGenderToken(String g) {
    final s = g.trim().toLowerCase();
    if (s == 'female' || s == 'نساء' || s == 'انثى' || s == 'أنثى') return 'female';
    if (s == 'kids' ||
        s == 'أطفال' ||
        s == 'children' ||
        s == 'auto' ||
        s == 'siege auto' ||
        s == 'siège auto' ||
        s == 'child seat') {
      return 'kids';
    }
    if (s == 'male' || s == 'رجال' || s == 'ذكر') return 'male';
    return 'male';
  }

  List<int> _extractSeatIndices(dynamic raw) {
    if (raw == null) return const [];
    
    if (raw is String) {
      try {
        final str = raw.trim();
        if (str.startsWith('[') && str.endsWith(']')) {
          final content = str.substring(1, str.length - 1);
          if (content.isEmpty) return const [];
          return content.split(',').map((e) => int.tryParse(e.trim())).whereType<int>().toList();
        } else {
          final n = int.tryParse(str);
          if (n != null) return [n];
        }
      } catch (_) {}
      return const [];
    }

    if (raw is List) {
      final parsed = <int>[];
      for (final entry in raw) {
        if (entry == null) continue;
        if (entry is num) {
          parsed.add(entry.toInt());
        } else {
          final n = int.tryParse(entry.toString());
          if (n != null) parsed.add(n);
        }
      }
      return parsed;
    }
    if (raw is Map) {
      final parsed = <int>[];
      for (final entry in raw.values) {
        if (entry == null) continue;
        if (entry is num) {
          parsed.add(entry.toInt());
        } else {
          final n = int.tryParse(entry.toString());
          if (n != null) parsed.add(n);
        }
      }
      return parsed;
    }
    return const [];
  }

  bool _containsSeatIndex(dynamic indices, int index) {
    if (indices is List || indices is Iterable) {
      for (final x in (indices as Iterable)) {
        if (x is num && x.toInt() == index) return true;
        if (int.tryParse(x.toString()) == index) return true;
      }
    }
    return false;
  }

  dynamic _seatMapValue(dynamic seatMapRaw, int index) {
    if (seatMapRaw == null) return null;
    
    if (seatMapRaw is List) {
      if (index >= 0 && index < seatMapRaw.length) {
        return seatMapRaw[index];
      }
      return null;
    }
    
    if (seatMapRaw is Map) {
      if (seatMapRaw[index] != null) return seatMapRaw[index];
      if (seatMapRaw[index.toString()] != null) return seatMapRaw[index.toString()];
  
      // Some records store keys like "seat_2" / "s2".
      for (final entry in seatMapRaw.entries) {
        final keyIndex = int.tryParse(entry.key.toString().replaceAll(RegExp(r'[^0-9]'), ''));
        if (keyIndex == index) return entry.value;
      }
    }
    return null;
  }

  void _showPassengerReservedSeatModal(BuildContext context, HistoryTrip trip) {
    final barrierLabel = MaterialLocalizations.of(context).modalBarrierDismissLabel;
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: barrierLabel,
      barrierColor: Colors.black.withValues(alpha: 0.32),
      transitionDuration: const Duration(milliseconds: 420),
      pageBuilder: (ctx, animation, secondaryAnimation) {
        return SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Material(
                color: Colors.transparent,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 400),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(28),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(28),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.12),
                            blurRadius: 40,
                            offset: const Offset(0, 18),
                            spreadRadius: -4,
                          ),
                        ],
                      ),
                      child: FutureBuilder<List<dynamic>>(
                        future: Future.wait([
                          _fetchPassengerBookingForSeatModal(trip),
                          FirebaseDatabase.instance.ref().child('trips').child(trip.tripId).child('takenSeats').get(),
                        ]),
                        builder: (context, snap) {
                          if (snap.connectionState == ConnectionState.waiting) {
                            return const Padding(
                              padding: EdgeInsets.symmetric(vertical: 48, horizontal: 32),
                              child: Center(
                                child: SizedBox(
                                  width: 32,
                                  height: 32,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    color: Color(0xFF43C59E),
                                  ),
                                ),
                              ),
                            );
                          }

                          // Prefer takenSeats booking; fallback to bookings data so seat info always shows.
                          Map<dynamic, dynamic>? booking = snap.data?[0] as Map<dynamic, dynamic>?;
                          Map<dynamic, dynamic> takenSeatsData = {};
                          if (snap.data != null && snap.data!.length > 1) {
                            final tsSnap = snap.data![1] as DataSnapshot;
                            if (tsSnap.exists && tsSnap.value != null) {
                              takenSeatsData = tsSnap.value as Map<dynamic, dynamic>;
                            }
                          }
                          
                          if (booking == null) {
                            booking = {
                              'gender': trip.gender,
                              'seatIndices': trip.seatIndices,
                              'seatGenders': trip.seatGenders,
                              'seatLuggage': trip.seatLuggage,
                              'userName': trip.passengerName,
                              'firstName': '',
                              'lastName': '',
                            };
                          }
                          final fromBooking = booking['gender']?.toString().trim();
                          final tripGenderRaw = (fromBooking != null && fromBooking.isNotEmpty)
                              ? fromBooking
                              : trip.gender.trim();
                          final genderToken = (tripGenderRaw.isEmpty || tripGenderRaw == 'بدون تفضيل')
                              ? 'male'
                              : _normalizeGenderToken(tripGenderRaw);
                          final tripPrice = (trip.suggestedPrice != null && trip.status == 'accepted')
                              ? trip.suggestedPrice!
                              : trip.price;
                          final bookingSeatIndices = _extractSeatIndices(booking['seatIndices']);
                          final effectiveSeatIndices = bookingSeatIndices.isNotEmpty
                              ? bookingSeatIndices
                              : trip.seatIndices;
                          final selectedSeatLabel = effectiveSeatIndices.toSet().toList()..sort();

                          return SingleChildScrollView(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.fromLTRB(20, 18, 12, 14),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF8FBFA),
                                    border: Border(
                                      bottom: BorderSide(color: Colors.grey.shade200),
                                    ),
                                  ),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius: BorderRadius.circular(16),
                                          boxShadow: [
                                            BoxShadow(
                                              color: const Color(0xFF43C59E).withValues(alpha: 0.15),
                                              blurRadius: 12,
                                              offset: const Offset(0, 4),
                                            ),
                                          ],
                                        ),
                                        child: const Icon(
                                          Icons.event_seat_rounded,
                                          color: Color(0xFF43C59E),
                                          size: 26,
                                        ),
                                      ),
                                      const SizedBox(width: 14),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'مقعدك المحجوز',
                                              style: TextStyle(
                                                fontSize: 20,
                                                fontWeight: FontWeight.w800,
                                                letterSpacing: -0.3,
                                                color: Colors.grey.shade900,
                                                height: 1.15,
                                              ),
                                            ),
                                            const SizedBox(height: 6),
                                            Text(
                                              selectedSeatLabel.isNotEmpty
                                                  ? "المقاعد: ${selectedSeatLabel.join(' - ')}"
                                                  : 'معاينة سريعة لحجزك',
                                              style: TextStyle(
                                                fontSize: 13,
                                                height: 1.3,
                                                color: Colors.grey.shade600,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      IconButton(
                                        onPressed: () => Navigator.of(ctx).pop(),
                                        style: IconButton.styleFrom(
                                          backgroundColor: Colors.grey.shade100,
                                          foregroundColor: Colors.grey.shade700,
                                        ),
                                        icon: const Icon(Icons.close_rounded, size: 22),
                                      ),
                                    ],
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                                  child: _buildSeatLayout(
                                    effectiveSeatIndices,
                                    trip.totalSeats > 0 ? trip.totalSeats : 4,
                                    takenSeatsData,
                                    genderToken,
                                    passengerName: trip.passengerName,
                                    passengerOnlyView: false,
                                    passengerBooking: booking,
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                                    decoration: BoxDecoration(
                                      color: Colors.grey.shade50,
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(color: Colors.grey.shade200),
                                    ),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.schedule_rounded, size: 18, color: Colors.grey.shade600),
                                        const SizedBox(width: 8),
                                        Flexible(
                                          child: Text(
                                            "${trip.date} · ${trip.time}",
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              fontSize: 13,
                                              color: Colors.grey.shade800,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                                  child: Text(
                                    "${tripPrice.toStringAsFixed(0)} د.ج",
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 15,
                                      color: const Color(0xFF43C59E),
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                                  child: FilledButton.tonal(
                                    onPressed: () => Navigator.of(ctx).pop(),
                                    style: FilledButton.styleFrom(
                                      minimumSize: const Size.fromHeight(48),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      foregroundColor: Colors.grey.shade800,
                                    ),
                                    child: const Text(
                                      'تم',
                                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.91, end: 1.0).animate(curved),
            child: child,
          ),
        );
      },
    );
  }

  Widget _buildSeatLayout(
    List<int> passengerIndices,
    int totalSeats,
    Map<dynamic, dynamic> takenSeatsData,
    String fallbackGender, {
    String? passengerName,
    bool passengerOnlyView = false,
    Map<dynamic, dynamic>? passengerBooking,
  }) {
    List<Widget> rows = [];
    
    // Front row
    rows.add(
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _buildSeatItem("السائق", 0, passengerIndices, takenSeatsData, fallbackGender,
              isDriver: true, passengerOnlyView: passengerOnlyView, passengerBooking: passengerBooking),
          if (totalSeats >= 1) 
            _buildSeatItem("1", 1, passengerIndices, takenSeatsData, fallbackGender,
                passengerName: passengerName, passengerOnlyView: passengerOnlyView, passengerBooking: passengerBooking)
          else 
            const SizedBox(width: 48),
        ],
      )
    );
    
    // Calculate remaining rows (max 3 seats per row)
    int currentSeatNumber = 2;
    while (currentSeatNumber <= totalSeats) {
      List<Widget> rowSeats = [];
      for (int i = 0; i < 3; i++) {
        if (currentSeatNumber <= totalSeats) {
          rowSeats.add(_buildSeatItem(currentSeatNumber.toString(), currentSeatNumber, passengerIndices, takenSeatsData, fallbackGender,
              passengerName: passengerName, passengerOnlyView: passengerOnlyView, passengerBooking: passengerBooking));
          currentSeatNumber++;
        } else {
          rowSeats.add(const SizedBox(width: 48)); // Placeholder for alignment
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!passengerOnlyView) ...[
          const Text(
            "توزيع المقاعد في المركبة",
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 16),
        ],
        Center(
          child: Container(
            width: 300,
            padding: const EdgeInsets.all(30),
            margin: const EdgeInsets.symmetric(horizontal: 20),
            decoration: BoxDecoration(
              color: passengerOnlyView ? const Color(0xFFF4F7F6) : Colors.white,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(100),
                bottom: Radius.circular(40),
              ),
              border: Border.all(
                color: Colors.grey.shade200,
                width: passengerOnlyView ? 1 : 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: passengerOnlyView ? 0.04 : 0.03),
                  blurRadius: passengerOnlyView ? 24 : 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              children: rows,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSeatItem(
    String label,
    int index,
    List<int> passengerIndices,
    Map<dynamic, dynamic> takenSeatsData,
    String fallbackGender, {
    bool isDriver = false,
    String? passengerName,
    bool passengerOnlyView = false,
    Map<dynamic, dynamic>? passengerBooking,
  }) {
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

    if (isDriver) {
      return Container(
        decoration: BoxDecoration(
          color: Colors.grey.shade200,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.grey.shade300),
        ),
        width: 48,
        height: 48,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(Icons.directions_car, color: Colors.grey, size: 24),
            SizedBox(height: 4),
            Text("السائق", style: TextStyle(fontSize: 10, color: Colors.grey)),
          ],
        ),
      );
    }

    final isPassengerSeat = passengerIndices.contains(index);

    Map<dynamic, dynamic>? takenSeatInfo;
    if (passengerOnlyView) {
      final booking = passengerBooking;
      if (isPassengerSeat && booking != null) {
        final indices = booking['seatIndices'];
        takenSeatInfo = _containsSeatIndex(indices, index) ? booking : null;
      }
    } else {
      takenSeatsData.forEach((key, value) {
        if (value is Map<dynamic, dynamic>) {
          final indices = value['seatIndices'];
          if (_containsSeatIndex(indices, index)) takenSeatInfo = value;
        }
      });
    }

    String seatGender = _normalizeGenderToken(fallbackGender);
    final seatInfo = takenSeatInfo;
    if (seatInfo != null) {
      final perSeatGender = _seatMapValue(seatInfo['seatGenders'], index);
      if (perSeatGender != null) {
        seatGender = _normalizeGenderToken(perSeatGender.toString());
      } else {
        seatGender = _normalizeGenderToken(
          seatInfo['gender']?.toString() ??
              seatInfo['userGender']?.toString() ??
              fallbackGender,
        );
      }
    }

    Color seatColor = Colors.white;
    Widget seatContent;
    bool hasLuggage = false;
    if (isPassengerSeat && seatInfo != null) {
      final luggageVal = _seatMapValue(seatInfo['seatLuggage'], index);
      if (luggageVal != null) {
        hasLuggage = luggageVal == true || luggageVal.toString().toLowerCase() == 'true';
      } else if (seatInfo['seatLuggage'] == null) {
        hasLuggage = seatInfo['hasLuggage'] == true || seatInfo['hasLuggage']?.toString().toLowerCase() == 'true';
      }
    }

    if (isPassengerSeat) {
      if (!passengerOnlyView && seatInfo != null) {
        String fName = seatInfo['firstName']?.toString() ?? '';
        String lName = seatInfo['lastName']?.toString() ?? '';
        if (fName.isNotEmpty || lName.isNotEmpty) {
          passengerName = '$fName $lName'.trim();
        } else {
          passengerName = seatInfo['userName']?.toString() ?? passengerName;
        }
      }

      seatColor = seatGender == 'female'
          ? Colors.pink.shade400
          : (seatGender == 'kids' ? Colors.orange : Colors.blue.shade800);

      Widget centerContent;
      if (seatGender == 'kids') {
        centerContent = Tooltip(
          message: "مقعد رضيع (siège auto)",
          child: babySeatIcon(Colors.white),
        );
      } else if (passengerOnlyView) {
        centerContent = Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        );
      } else if (passengerName != null && passengerName.trim().isNotEmpty) {
        String displayName = passengerName.trim();
        final nameParts = displayName.split(RegExp(r'\s+'));
        if (nameParts.length > 1) {
          displayName = '${nameParts.first}\n${nameParts.last}';
        }

        centerContent = FittedBox(
          fit: BoxFit.scaleDown,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2.0),
            child: Text(
              displayName,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                height: 1.1,
                fontSize: 10,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
            ),
          ),
        );
      } else {
        centerContent = Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        );
      }

      seatContent = Stack(
        children: [
          Center(child: centerContent),
          Positioned(
            bottom: 2,
            right: 2,
            child: seatGender == 'kids'
                ? const SizedBox.shrink()
                : Icon(
                    seatGender == 'female' ? Icons.female : Icons.male,
                    color: Colors.white70,
                    size: 14,
                  ),
          ),
        ],
      );
    } else if (seatInfo != null && !passengerOnlyView) {
      seatColor = seatGender == 'female'
          ? Colors.pink.shade50
          : (seatGender == 'kids' ? Colors.orange.shade50 : Colors.blue.shade50);

      final iconColor = seatGender == 'female'
          ? Colors.pink.shade800
          : (seatGender == 'kids' ? Colors.orange.shade800 : Colors.blue.shade800);

      seatContent = Center(
        child: Icon(
          seatGender == 'kids' ? Icons.event_seat_rounded : Icons.close,
          color: iconColor,
          size: seatGender == 'kids' ? 20 : 24,
        ),
      );
      if (seatGender == 'kids') {
        seatContent = Center(child: babySeatIcon(iconColor));
      }
    } else {
      seatContent = Center(
        child: Text(
          label,
          style: TextStyle(
            color: Colors.grey.shade400,
            fontSize: 16,
          ),
        ),
      );
    }

    final borderColor = isPassengerSeat
        ? (passengerOnlyView ? Colors.white.withValues(alpha: 0.55) : Colors.black)
        : Colors.grey.shade300;
    final borderWidth = isPassengerSeat ? (passengerOnlyView ? 1.5 : 2.0) : 1.0;

    final seatBox = Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: seatColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: borderColor,
          width: borderWidth,
        ),
        boxShadow: [
          if (isPassengerSeat)
            BoxShadow(
              color: seatColor.withValues(alpha: passengerOnlyView ? 0.22 : 0.3),
              blurRadius: passengerOnlyView ? 10 : 8,
              spreadRadius: passengerOnlyView ? 0 : 0,
              offset: const Offset(0, 3),
            ),
        ],
      ),
      child: seatContent,
    );

    if (isPassengerSeat && hasLuggage) {
      return Stack(
        clipBehavior: Clip.none,
        children: [
          seatBox,
          Positioned(
            top: -5,
            right: -3,
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFF43C59E), width: 1),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: const Icon(
                Icons.luggage_rounded,
                size: 10,
                color: Color(0xFF2A9D74),
              ),
            ),
          ),
        ],
      );
    }

    return seatBox;
  }

  void _showTripDetailsModal(BuildContext context, HistoryTrip trip) {
    debugPrint('SEAT LAYOUT DEBUG: trip.seatIndices=${trip.seatIndices}');
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
          ),
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          child: SafeArea(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 5,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    "تفاصيل الرحلة",
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // 1. Seat Layout
                  FutureBuilder<DataSnapshot?>(
                    future: FirebaseDatabase.instance.ref().child('trips').child(trip.tripId).child('takenSeats').get(),
                    builder: (context, snapshot) {
                      Map<dynamic, dynamic> takenSeatsData = {};
                      if (snapshot.hasData && snapshot.data!.exists) {
                        takenSeatsData = snapshot.data!.value as Map<dynamic, dynamic>;
                      }
                      
                      return _buildSeatLayout(
                        trip.seatIndices,
                        trip.totalSeats > 0 ? trip.totalSeats : ((trip.seatIndices.isNotEmpty ? trip.seatIndices.reduce((a, b) => a > b ? a : b) : 4).clamp(4, 6)),
                        takenSeatsData,
                        trip.gender,
                        passengerName: trip.passengerName,
                      );
                    }
                  ),
                  const SizedBox(height: 32),

                  // 2. Passenger Preferences
                  _buildDetailRow(
                    icon: Icons.accessibility_new,
                    title: "تفضيلات الراكب",
                    value: trip.gender.isNotEmpty 
                        ? "${trip.gender == 'male' ? 'رجال' : trip.gender == 'female' ? 'نساء' : 'أطفال'} فقط"
                        : "لا يوجد تفضيل للجنس",
                  ),
                  const Divider(height: 32),

                  // 3. Departure Time
                  _buildDetailRow(
                    icon: Icons.access_time,
                    title: "وقت المغادرة",
                    value: trip.time,
                  ),
                  const Divider(height: 32),

                  // 4. Vehicle Details (Includes Plate if data exists)
                  FutureBuilder<DataSnapshot?>(
                    future: trip.driverId.isNotEmpty
                        ? FirebaseDatabase.instance.ref().child('users').child(trip.driverId).child('vehicle').get()
                        : Future.value(null),
                    builder: (context, snapshot) {
                      String plateNumber = "N/A";
                      if (snapshot.hasData && snapshot.data!.exists) {
                        final data = snapshot.data!.value as Map<dynamic, dynamic>;
                        plateNumber = data['plateNumber']?.toString() ?? "N/A";
                      }

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildDetailRow(
                            icon: Icons.directions_car,
                            title: "تفاصيل المركبة",
                            value: "${trip.vehicleName}\nاللوحة: $plateNumber",
                          ),
                          const SizedBox(height: 32),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: () {
                                Navigator.pop(context); // Close the bottom sheet
                                Navigator.pushNamed(
                                  context,
                                  '/chat',
                                  arguments: {
                                    'tripId': trip.tripId,
                                    'route': "${trip.from} → ${trip.to}",
                                    'driverName': trip.vehicleName,
                                  },
                                );
                              },
                              icon: const Icon(Icons.message, color: Colors.white),
                              label: const Text(
                                "مراسلة", 
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF43C59E),
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                elevation: 0,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildDetailRow({required IconData icon, required String title, required String value}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFF43C59E).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: const Color(0xFF43C59E), size: 20),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 16,
                  color: Colors.black87,
                  fontWeight: FontWeight.bold,
                  height: 1.4,
                ),
              ),
            ],
            
          ),
        ),
      ],
    );
  }
}
