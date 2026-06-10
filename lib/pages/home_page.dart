import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'dart:async';
import '../models/trip_model.dart';
import '../data/wilaya_districts.dart';
import '../widgets/logout_confirmation_dialog.dart';
import '../widgets/message_badge.dart';
import '../widgets/global_app_bar_actions.dart';
import '../widgets/user_profile_avatar.dart';
import '../widgets/history_badge.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // ... (existing state variables)
  String? selectedFromWilaya;
  String? selectedFromDistrict;
  String? selectedToWilaya;
  String? selectedToDistrict;
  String priceFilter = 'all';

  int _currentIndex = 0; // For BottomNavigationBar

  List<Trip> allTrips = [];
  bool _isLoading = true;
  StreamSubscription<DatabaseEvent>? _tripsSubscription;
  StreamSubscription<DatabaseEvent>? _passengerTripsSubscription;
  StreamSubscription<DatabaseEvent>? _userSubscription;
  Map<dynamic, dynamic>? _userData;

  DateTime? _parseTripDate(String? dateStr) {
    if (dateStr == null || dateStr.trim().isEmpty) return null;
    final s = dateStr.trim();

    if (s.contains('-')) {
      return DateTime.tryParse(s);
    }

    final parts = s.split('/');
    if (parts.length == 3) {
      final d = int.tryParse(parts[0]);
      final m = int.tryParse(parts[1]);
      final y = int.tryParse(parts[2]);
      if (d != null && m != null && y != null) {
        return DateTime(y, m, d);
      }
    }
    return null;
  }

  DateTime? _parseTripDateTime(String? dateStr, String? timeStr) {
    final tripDate = _parseTripDate(dateStr);
    if (tripDate == null || timeStr == null || timeStr.trim().isEmpty) return null;

    var t = timeStr.trim().toUpperCase();
    t = t.replaceAll('ص', 'AM').replaceAll('م', 'PM');
    t = t.replaceAll(RegExp(r'\s+'), ' ');

    final timeMatch = RegExp(r'^(\d{1,2}):(\d{1,2})(?:\s*(AM|PM))?$').firstMatch(t);
    if (timeMatch == null) return DateTime(tripDate.year, tripDate.month, tripDate.day, 23, 59);

    int hour = int.tryParse(timeMatch.group(1) ?? '') ?? 0;
    final minute = int.tryParse(timeMatch.group(2) ?? '') ?? 0;
    final suffix = timeMatch.group(3);

    if (suffix != null) {
      if (suffix == 'PM' && hour < 12) hour += 12;
      if (suffix == 'AM' && hour == 12) hour = 0;
    }

    return DateTime(tripDate.year, tripDate.month, tripDate.day, hour.clamp(0, 23), minute.clamp(0, 59));
  }

  @override
  void initState() {
    super.initState();
    _listenToTrips();
    _listenToPassengerActiveTrips();
    _listenToUserData();
  }
  
  @override
  void dispose() {
    _tripsSubscription?.cancel();
    _passengerTripsSubscription?.cancel();
    _userSubscription?.cancel();
    super.dispose();
  }

  void _listenToUserData() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    _userSubscription = FirebaseDatabase.instance.ref().child('users').child(user.uid).onValue.listen((event) {
      if (mounted && event.snapshot.value != null) {
        setState(() {
          _userData = event.snapshot.value as Map<dynamic, dynamic>;
        });
      }
    });
  }

  void _listenToTrips() {
    _tripsSubscription?.cancel();
    setState(() => _isLoading = true);

    Query tripsQuery = FirebaseDatabase.instance.ref().child('trips');

    if (selectedFromWilaya == null && selectedToWilaya == null) {
      tripsQuery = tripsQuery.limitToLast(100);
    }

    _tripsSubscription = tripsQuery.onValue.listen((event) {
      if (!mounted) return;

      final user = FirebaseAuth.instance.currentUser;
      final List<Trip> loadedTrips = [];

      if (event.snapshot.value != null) {
        final data = event.snapshot.value as Map<dynamic, dynamic>;

        // Get today's date with time set to 00:00:00 for accurate comparison
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);

        data.forEach((key, value) {
          try {
            final tripMap = Map<String, dynamic>.from(value as Map);
            final status = tripMap['status']?.toString() ?? 'active';
            if (!(status == 'active' || status == 'full')) {
              return;
            }

            // 1. Data Cleanup: Remove trips with empty mandatory fields
            if (tripMap['from'] == null ||
                tripMap['to'] == null ||
                (tripMap['from'] as String).isEmpty ||
                (tripMap['to'] as String).isEmpty) {
              FirebaseDatabase.instance
                  .ref()
                  .child('trips')
                  .child(key.toString())
                  .remove();
              return;
            }

            // 2. Filter: Hide driver's own trips when looking as a passenger
            if (user != null && tripMap['driverId'] == user.uid) {
              return; // Skip adding to list
            }

            // 3. Filter/archive expired trips:
            // - any date before today
            // - today's trip if its departure time already passed
            final tripDate = _parseTripDate(tripMap['date']?.toString());
            if (tripDate != null) {
              if (tripDate.isBefore(today)) {
                if (status != 'archived') {
                  FirebaseDatabase.instance.ref().child('trips').child(key.toString()).update({'status': 'archived'});
                }
                return;
              }

              if (tripDate.year == today.year && tripDate.month == today.month && tripDate.day == today.day) {
                final tripDateTime = _parseTripDateTime(tripMap['date']?.toString(), tripMap['time']?.toString());
                if (tripDateTime != null && DateTime.now().isAfter(tripDateTime)) {
                  if (status != 'archived') {
                    FirebaseDatabase.instance.ref().child('trips').child(key.toString()).update({'status': 'archived'});
                  }
                  return;
                }
              }
            }

            // Add ID if not present in map (it's the key)
            tripMap['id'] = key;
            loadedTrips.add(Trip.fromMap(tripMap, key.toString()));
          } catch (e) {
            debugPrint("Error parsing trip $key: $e");
          }
        });
      }

      setState(() {
        allTrips = loadedTrips;
        _isLoading = false;
      });
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
            
            // Mark as 'showing_dialog' locally or immediately show to prevent multiple popups
            // We just show the dialog if it isn't already showing.
            _showStartTripConfirmationDialog(bookingData['tripId']?.toString() ?? '', key.toString(), bookingData);
        }
      });
    });
  }

  // To prevent multiple dialogs for the same trip
  String? _showingDialogForTripId;

  void _showStartTripConfirmationDialog(String tripId, String historyKey, Map<String, dynamic> bookingData) {
    if (_showingDialogForTripId == tripId || !mounted) return;
    _showingDialogForTripId = tripId;

    final driverName = bookingData['driverName'] ?? 'Driver';
    
    showDialog(
      context: context,
      barrierDismissible: false, // Must answer
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text("بدء الرحلة", style: TextStyle(color: const Color(0xFF43C59E), fontWeight: FontWeight.bold)),
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
      // 1. Update customer history
      await FirebaseDatabase.instance.ref()
          .child('bookings')
          .child(user.uid)
          .child(historyKey)
          .update({'passengerConfirmed': isConfirmed});

      // 2. Update trip takenSeats
      final tripRef = FirebaseDatabase.instance.ref().child('trips').child(tripId);
      final tripSnapshot = await tripRef.get();
      if (tripSnapshot.exists) {
         final tripMap = tripSnapshot.value as Map<dynamic, dynamic>;
         final takenSeats = tripMap['takenSeats'] as Map<dynamic, dynamic>?;
         if (takenSeats != null) {
            String? seatIndex;
            // Find the seat matching this userId
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

  List<Trip> get filteredTrips {
    final validTrips = List<Trip>.from(allTrips);

    bool hasLocationFilter = selectedFromWilaya != null || selectedToWilaya != null;

    var result = validTrips.where((trip) {
      bool matchesFrom = true;
      bool matchesTo = true;

      if (selectedFromWilaya != null) {
        matchesFrom = trip.fromWilaya == selectedFromWilaya;
        if (selectedFromDistrict != null) {
          matchesFrom = matchesFrom && trip.fromDistrict == selectedFromDistrict;
        }
      }

      if (selectedToWilaya != null) {
        matchesTo = trip.toWilaya == selectedToWilaya;
        if (selectedToDistrict != null) {
          matchesTo = matchesTo && trip.toDistrict == selectedToDistrict;
        }
      }

      return matchesFrom && matchesTo;
    }).toList();

    if (!hasLocationFilter) {
      result.sort((a, b) => b.id.compareTo(a.id));
      if (result.length > 20) {
        result = result.sublist(0, 20);
      }
    } else if (hasLocationFilter) {
      // Sort by price lowest first
      result.sort((a, b) => a.price.compareTo(b.price));
    }

    return result;
  }

  void _onBottomNavTapped(int index) {
    if (index == _currentIndex) return;

    setState(() {
      _currentIndex = index;
    });

    // Case 0 (Home) doesn't need explicit navigation as it's the current page.
    if (index == 1) {
      Navigator.pushReplacementNamed(context, '/history');
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
    return WillPopScope(
      onWillPop: () async {
        // Prevent accidental exit from Home
        return await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('تسجيل الخروج'),
            content: const Text('هل تريد الخروج من التطبيق؟'),
            actions: [
              TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('لا')),
              TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('نعم')),
            ],
          ),
        ) ?? false;
      },
      child: Scaffold(
        backgroundColor: Colors.grey[50],
  appBar: AppBar(
  backgroundColor: const Color(0xFF43C59E),
  elevation: 0,
  centerTitle: false, // 👈 change this only

  title: const Align(
    alignment: Alignment.centerLeft, // 👈 force left
    child: Text(
      'الرئيسية',
      style: TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.bold,
        fontSize: 18,
      ),
    ),
  ),

  actions: const [
    GlobalAppBarActions()
  ],
),

      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: Column(
              children: [
                // From → To Card
                Container(
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFF43C59E),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.12),
                        blurRadius: 6,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // FROM Section
                  Row(
                    children: [
                      const Icon(
                        Icons.my_location,
                        color: Colors.white,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'من',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: selectedFromWilaya,
                          isExpanded: true,
                          decoration: InputDecoration(
                            filled: true,
                            fillColor: Colors.white,
                            hintText: 'اختر الولاية',
                            hintStyle: TextStyle(
                              color: Colors.grey.shade400,
                              fontSize: 13,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 0,
                            ),
                            suffixIcon: selectedFromWilaya != null
                                ? IconButton(
                                    icon: const Icon(
                                      Icons.clear,
                                      size: 16,
                                      color: Colors.grey,
                                    ),
                                    onPressed: () => setState(() {
                                      selectedFromWilaya = null;
                                      selectedFromDistrict = null;
                                    }),
                                  )
                                : null,
                          ),
                          items: wilayaDistricts.keys
                              .map(
                                (w) => DropdownMenuItem(
                                  value: w,
                                  child: Text(
                                    w,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (val) {
                            setState(() {
                              selectedFromWilaya = val;
                              selectedFromDistrict = null;
                            });
                            _listenToTrips();
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: selectedFromDistrict,
                          isExpanded: true,
                          decoration: InputDecoration(
                            filled: true,
                            fillColor: Colors.white,
                            hintText: 'اختر الدائرة',
                            hintStyle: TextStyle(
                              color: Colors.grey.shade400,
                              fontSize: 13,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 0,
                            ),
                            suffixIcon: selectedFromDistrict != null
                                ? IconButton(
                                    icon: const Icon(
                                      Icons.clear,
                                      size: 16,
                                      color: Colors.grey,
                                    ),
                                    onPressed: () => setState(
                                      () => selectedFromDistrict = null,
                                    ),
                                  )
                                : null,
                          ),
                          items:
                              (selectedFromWilaya == null
                                      ? <String>[]
                                      : wilayaDistricts[selectedFromWilaya]!)
                                  .map(
                                    (d) => DropdownMenuItem(
                                      value: d,
                                      child: Text(
                                        d,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 13),
                                      ),
                                    ),
                                  )
                                  .toList(),
                          onChanged: (val) {
                            setState(() {
                              selectedFromDistrict = val;
                            });
                            _listenToTrips();
                          },
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  // TO Section
                  Row(
                    children: [
                      const Icon(
                        Icons.location_on,
                        color: Colors.white,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'إلى',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: selectedToWilaya,
                          isExpanded: true,
                          decoration: InputDecoration(
                            filled: true,
                            fillColor: Colors.white,
                            hintText: 'اختر الولاية',
                            hintStyle: TextStyle(
                              color: Colors.grey.shade400,
                              fontSize: 13,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 0,
                            ),
                            suffixIcon: selectedToWilaya != null
                                ? IconButton(
                                    icon: const Icon(
                                      Icons.clear,
                                      size: 16,
                                      color: Colors.grey,
                                    ),
                                    onPressed: () => setState(() {
                                      selectedToWilaya = null;
                                      selectedToDistrict = null;
                                    }),
                                  )
                                : null,
                          ),
                          items: wilayaDistricts.keys
                              .map(
                                (w) => DropdownMenuItem(
                                  value: w,
                                  child: Text(
                                    w,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (val) {
                            setState(() {
                              selectedToWilaya = val;
                              selectedToDistrict = null;
                            });
                            _listenToTrips();
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: selectedToDistrict,
                          isExpanded: true,
                          decoration: InputDecoration(
                            filled: true,
                            fillColor: Colors.white,
                            hintText: 'اختر الدائرة',
                            hintStyle: TextStyle(
                              color: Colors.grey.shade400,
                              fontSize: 13,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 0,
                            ),
                            suffixIcon: selectedToDistrict != null
                                ? IconButton(
                                    icon: const Icon(
                                      Icons.clear,
                                      size: 16,
                                      color: Colors.grey,
                                    ),
                                    onPressed: () => setState(
                                      () => selectedToDistrict = null,
                                    ),
                                  )
                                : null,
                          ),
                          items:
                              (selectedToWilaya == null
                                      ? <String>[]
                                      : wilayaDistricts[selectedToWilaya]!)
                                  .map(
                                    (d) => DropdownMenuItem(
                                      value: d,
                                      child: Text(
                                        d,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 13),
                                      ),
                                    ),
                                  )
                                  .toList(),
                          onChanged: (val) {
                            setState(() {
                              selectedToDistrict = val;
                            });
                            _listenToTrips();
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 16),
              ],
            ),
          ),

          // Trips List
          if (_isLoading)
            const SliverToBoxAdapter(
              child: Center(
                child: Padding(
                  padding: EdgeInsets.all(20.0),
                  child: CircularProgressIndicator(
                    color: Color(0xFF43C59E),
                  ),
                ),
              ),
            )
          else if (filteredTrips.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(top: 50),
                child: Center(
                  child: Text(
                      "لا توجد رحلات متاحة لهذا المسار",
                    style: const TextStyle(color: Colors.grey, fontSize: 16),
                  ),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final trip = filteredTrips[index];
                final isFullyBooked = trip.availableSeats <= 0;

                return GestureDetector(
                  onTap: isFullyBooked
                      ? null
                      : () {
                          Navigator.pushNamed(
                            context,
                            '/seat-selection',
                            arguments: trip,
                          );
                        },
                  child: Opacity(
                    opacity: isFullyBooked ? 0.6 : 1.0,
                    child: Container(
                          margin: const EdgeInsets.only(bottom: 16),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.grey.withValues(alpha: 0.05),
                                blurRadius: 6,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Driver Info / Image placeholder
                              UserProfileAvatar(
                                userId: trip.driverId,
                                radius: 25,
                              ),
                              const SizedBox(width: 16),

                              // Details
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            trip.driverName,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 16,
                                            ),
                                          ),
                                        ),
                                        if (trip.allowsPackages)
                                          const Padding(
                                            padding: EdgeInsets.symmetric(horizontal: 4.0),
                                            child: Icon(
                                              Icons.inventory_2,
                                              color: Colors.orange,
                                              size: 20,
                                            ),
                                          ),
                                        if (isFullyBooked)
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: Colors.red.shade600,
                                              borderRadius: BorderRadius.circular(12),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                const Icon(Icons.check_circle_outline, color: Colors.white, size: 12),
                                                const SizedBox(width: 4),
                                                const Text(
                                                  "ممتلئة",
                                                  style: TextStyle(
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 10,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF43C59E).withValues(alpha: 0.1),
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: const Text(
                                            "🚗 سيارة",
                                            style: TextStyle(
                                              color: Color(0xFF1E824C),
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            '${trip.vehicleName} . ${trip.carType}',
                                            style: TextStyle(
                                              color: Colors.grey.shade600,
                                              fontSize: 13,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: isFullyBooked ? Colors.red.withOpacity(0.1) : Colors.orange.withOpacity(0.1),
                                            borderRadius: BorderRadius.circular(8),
                                            border: Border.all(color: isFullyBooked ? Colors.red.withOpacity(0.3) : Colors.orange.withOpacity(0.3)),
                                          ),
                                          child: Text(
                                            isFullyBooked
                                                ? 'لا توجد مقاعد متاحة'
                                                : '${trip.availableSeats} مقاعد متبقية',
                                            style: TextStyle(
                                              color: isFullyBooked ? Colors.red.shade700 : Colors.orange.shade800,
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),

                                    // Meeting Point
                                    if (trip.meetingPoint.isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: 8.0,
                                        ),
                                        child: Row(
                                          children: [
                                            const Icon(
                                              Icons.meeting_room,
                                              size: 14,
                                              color: Colors.blueGrey,
                                            ),
                                            const SizedBox(width: 4),
                                            Expanded(
                                              child: Text(
                                                "نقطة الالتقاء: ${trip.meetingPoint}",
                                                style: TextStyle(
                                                  color: Colors.blueGrey,
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),

                                    // Route
                                    Row(
                                      children: [
                                        const Icon(
                                          Icons.circle,
                                          size: 8,
                                          color: Color(0xFF43C59E),
                                        ),
                                        const SizedBox(width: 4),
                                        Expanded(
                                          child: Text(
                                            '${trip.fromWilaya}, ${trip.fromDistrict}',
                                            overflow: TextOverflow.ellipsis,
                                            maxLines: 1,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 2),
                                    Row(
                                      children: [
                                        const Icon(
                                          Icons.location_on,
                                          size: 8,
                                          color: Colors.red,
                                        ),
                                        const SizedBox(width: 4),
                                        Expanded(
                                          child: Text(
                                            '${trip.toWilaya}, ${trip.toDistrict}',
                                            overflow: TextOverflow.ellipsis,
                                            maxLines: 1,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),

                                    // Time and Price
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Row(
                                          children: [
                                            const Icon(
                                              Icons.calendar_today,
                                              size: 14,
                                              color: Colors.grey,
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              trip.date,
                                              style: const TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            const Icon(
                                              Icons.access_time,
                                              size: 16,
                                              color: Colors.grey,
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              trip.time,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ],
                                        ),
                                        Text(
                                          '${trip.price.toStringAsFixed(0)} دج',
                                          style: const TextStyle(
                                            color: Color(0xFF43C59E),
                                            fontWeight: FontWeight.bold,
                                            fontSize: 18,
                                          ),
                                        ),
                                      ],
                                    ),

                                    const SizedBox(height: 8),
                                    // Rating
                                    StreamBuilder<DatabaseEvent>(
                                      stream: FirebaseDatabase.instance.ref().child('users').child(trip.driverId).onValue,
                                      builder: (context, userSnap) {
                                        final userData = userSnap.data?.snapshot.value as Map<dynamic, dynamic>? ?? {};
                                        final rating = (userData['rating'] as num?)?.toDouble() ?? 0;
                                        final ratingCount = (userData['ratingCount'] as num?)?.toInt() ?? 0;
                                        return Row(
                                          children: [
                                            Text(
                                              "⭐ ${rating.toStringAsFixed(1)} ($ratingCount)",
                                              style: const TextStyle(fontWeight: FontWeight.bold),
                                            ),
                                          ],
                                        );
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            ], // closes Row children
                          ), // closes Row
                        ), // closes Container
                  ),
                );
                  },
                  childCount: filteredTrips.length,
                ),
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 20)),
        ],
      ),
      bottomNavigationBar: Directionality(
        textDirection: TextDirection.ltr,
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          type: BottomNavigationBarType.fixed,
          selectedItemColor: const Color(0xFF43C59E),
          unselectedItemColor: Colors.grey,
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
}
