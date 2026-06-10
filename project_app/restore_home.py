import codecs

def main():
    original_code = """import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import '../models/trip_model.dart';
import '../data/wilaya_districts.dart';
import '../services/role_service.dart';
import 'settings_page.dart';
import '../widgets/main_app_bar.dart';

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

  @override
  void initState() {
    super.initState();
    _listenToTrips();
  }

  void _listenToTrips() {
    DatabaseReference tripsRef = FirebaseDatabase.instance.ref().child('trips');
    tripsRef.onValue.listen((event) {
      if (!mounted) return;
      
      final List<Trip> loadedTrips = [];
      if (event.snapshot.value != null) {
        final data = event.snapshot.value as Map<dynamic, dynamic>;
        data.forEach((key, value) {
          try {
             final tripMap = Map<String, dynamic>.from(value as Map);
             
             // Data Cleanup: Remove trips with empty mandatory fields
             if (tripMap['from'] == null || tripMap['to'] == null || 
                 (tripMap['from'] as String).isEmpty || (tripMap['to'] as String).isEmpty) {
                // Remove from DB
                FirebaseDatabase.instance.ref().child('trips').child(key.toString()).remove();
                return; // Skip adding to list
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

  bool _isTripInFutureOrToday(Trip trip) {
    if (trip.date.isEmpty) return true;
    final parsed = DateTime.tryParse(trip.date);
    if (parsed == null) return true;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tripDate = DateTime(parsed.year, parsed.month, parsed.day);

    // keep today and future trips
    return !tripDate.isBefore(today);
  }

  List<Trip> get filteredTrips {
    return allTrips.where((trip) {
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

      final isDateOk = _isTripInFutureOrToday(trip);
      final currentUser = FirebaseAuth.instance.currentUser;
      final bool isNotDriverOwnTrip =
          currentUser == null ? true : trip.driverId != currentUser.uid;

      return matchesFrom && matchesTo && isDateOk && isNotDriverOwnTrip;
    }).toList();
  }

  void _onBottomNavTapped(int index) {
    if (index == _currentIndex) return;
    
    switch (index) {
      case 0:
        // Already on Home
        break;
      case 1:
        Navigator.pushReplacementNamed(context, '/history');
        break;
      case 2:
        Navigator.pushReplacementNamed(context, '/delivery');
        break;
      case 3:
        Navigator.pushReplacementNamed(context, '/discount');
        break;
    }
    setState(() => _currentIndex = index);
  }

  Future<void> _logout() async {
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: MainAppBar(
        title: 'Rahti',
        actions: [
          TextButton.icon(
            onPressed: () => RoleService.switchRole(context, 'driver'),
            icon: const Icon(Icons.swap_horiz, color: Colors.black),
            label: const Text('Switch to Driver', style: TextStyle(color: Colors.black)),
          ),
          IconButton(
            icon: const Icon(Icons.settings, color: Colors.black),
            onPressed: () {
               Navigator.push(context, MaterialPageRoute(builder: (context) => const SettingsPage()));
            },
          ),
        ],
      ),

      body: SingleChildScrollView(
        child: Column(
          children: [
            // From → To Card
            Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF4CE5B1),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.12),
                    blurRadius: 12,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // FROM Section
                  Row(
                    children: [
                       const Icon(Icons.my_location, color: Colors.white, size: 18),
                       const SizedBox(width: 8),
                       const Text('From',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                       Expanded(
                        child: DropdownButtonFormField<String>(
                          value: selectedFromWilaya,
                          isExpanded: true,
                          decoration: InputDecoration(
                              filled: true,
                              fillColor: Colors.white,
                              hintText: 'Choose Wilaya',
                              hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none,
                              ),
                              contentPadding:
                                  const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                              suffixIcon: selectedFromWilaya != null 
                                ? IconButton(
                                    icon: const Icon(Icons.clear, size: 16, color: Colors.grey),
                                    onPressed: () => setState(() { selectedFromWilaya = null; selectedFromDistrict = null; }),
                                  ) 
                                : null,
                          ),
                          items: wilayaDistricts.keys
                              .map((w) => DropdownMenuItem(value: w, child: Text(w, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13))))
                              .toList(),
                          onChanged: (val) {
                            setState(() {
                              selectedFromWilaya = val;
                              selectedFromDistrict = null;
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: selectedFromDistrict,
                          isExpanded: true,
                          decoration: InputDecoration(
                              filled: true,
                              fillColor: Colors.white,
                              hintText: 'Choose District',
                              hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none,
                              ),
                              contentPadding:
                                  const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                              suffixIcon: selectedFromDistrict != null 
                                ? IconButton(
                                    icon: const Icon(Icons.clear, size: 16, color: Colors.grey),
                                    onPressed: () => setState(() => selectedFromDistrict = null),
                                  ) 
                                : null,
                          ),
                          items: (selectedFromWilaya == null
                                  ? <String>[]
                                  : wilayaDistricts[selectedFromWilaya]!)
                              .map((d) => DropdownMenuItem(value: d, child: Text(d, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13))))
                              .toList(),
                          onChanged: (val) {
                            setState(() {
                              selectedFromDistrict = val;
                            });
                          },
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  // TO Section
                  Row(
                    children: [
                       const Icon(Icons.location_on, color: Colors.white, size: 18),
                       const SizedBox(width: 8),
                       const Text('To',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: selectedToWilaya,
                          isExpanded: true,
                          decoration: InputDecoration(
                              filled: true,
                              fillColor: Colors.white,
                              hintText: 'Choose Wilaya',
                              hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none,
                              ),
                              contentPadding:
                                  const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                              suffixIcon: selectedToWilaya != null 
                                ? IconButton(
                                    icon: const Icon(Icons.clear, size: 16, color: Colors.grey),
                                    onPressed: () => setState(() { selectedToWilaya = null; selectedToDistrict = null; }),
                                  ) 
                                : null,
                          ),
                          items: wilayaDistricts.keys
                              .map((w) => DropdownMenuItem(value: w, child: Text(w, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13))))
                              .toList(),
                          onChanged: (val) {
                            setState(() {
                              selectedToWilaya = val;
                              selectedToDistrict = null;
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: selectedToDistrict,
                          isExpanded: true,
                          decoration: InputDecoration(
                              filled: true,
                              fillColor: Colors.white,
                              hintText: 'Choose District',
                              hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none,
                              ),
                              contentPadding:
                                  const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                              suffixIcon: selectedToDistrict != null 
                                ? IconButton(
                                    icon: const Icon(Icons.clear, size: 16, color: Colors.grey),
                                    onPressed: () => setState(() => selectedToDistrict = null),
                                  ) 
                                : null,
                          ),
                          items: (selectedToWilaya == null
                                  ? <String>[]
                                  : wilayaDistricts[selectedToWilaya]!)
                              .map((d) => DropdownMenuItem(value: d, child: Text(d, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13))))
                              .toList(),
                          onChanged: (val) {
                            setState(() {
                              selectedToDistrict = val;
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Trips List
            ListView.builder(
              physics: const NeverScrollableScrollPhysics(),
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: filteredTrips.isEmpty ? 1 : filteredTrips.length,
              itemBuilder: (context, index) {
                if (_isLoading) {
                   return const Center(child: Padding(
                     padding: EdgeInsets.all(20.0),
                     child: CircularProgressIndicator(color: Color(0xFF4CE5B1)),
                   ));
                }

                if (filteredTrips.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.only(top: 50),
                    child: Center(
                      child: Text(
                        "No trips available for this route",
                        style: TextStyle(color: Colors.grey, fontSize: 16),
                      ),
                    ),
                  );
                }

                final trip = filteredTrips[index];
                final bool isFull = trip.availableSeats <= 0;

                Widget cardContent = Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isFull ? Colors.grey.shade300 : Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.grey.withOpacity(isFull ? 0.02 : 0.05),
                        blurRadius: isFull ? 4 : 10,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Driver Info / Image placeholder
                      Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(25),
                        ),
                        child: const Icon(Icons.person, color: Colors.grey),
                      ),
                      const SizedBox(width: 16),
                      
                      // Details
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    '${trip.driverName}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold, fontSize: 16),
                                  ),
                                ),
                                // Package Icon if enabled
                                if (trip.allowsPackages)
                                  const Icon(Icons.inventory_2, color: Colors.orange, size: 20),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text('${trip.vehicleName} . ${trip.carType}',
                                style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                            const SizedBox(height: 8),

                            // Meeting Point
                            if (trip.meetingPoint.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8.0),
                                child: Row(
                                  children: [
                                    const Icon(Icons.meeting_room, size: 14, color: Colors.blueGrey),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: Text(
                                        "Meeting Point: ${trip.meetingPoint}",
                                        style: TextStyle(color: Colors.blueGrey, fontSize: 13, fontWeight: FontWeight.w500),
                                        maxLines: 1, overflow: TextOverflow.ellipsis
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            
                            // Route
                            Row(
                              children: [
                                const Icon(Icons.circle, size: 8, color: Color(0xFF4CE5B1)),
                                const SizedBox(width: 4),
                                Expanded(child: Text('${trip.fromWilaya}, ${trip.fromDistrict}', overflow: TextOverflow.ellipsis, maxLines: 1)),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                const Icon(Icons.location_on, size: 8, color: Colors.red),
                                const SizedBox(width: 4),
                                Expanded(child: Text('${trip.toWilaya}, ${trip.toDistrict}', overflow: TextOverflow.ellipsis, maxLines: 1)),
                              ],
                            ),
                            const SizedBox(height: 12),
                            
                            // Time, Price and Seats
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    const Icon(Icons.access_time, size: 16, color: Colors.grey),
                                    const SizedBox(width: 4),
                                    Text(trip.time, style: const TextStyle(fontWeight: FontWeight.w600)),
                                  ],
                                ),
                                Row(
                                  children: [
                                    const Icon(Icons.event_seat, size: 16, color: Colors.grey),
                                    const SizedBox(width: 4),
                                    Text(
                                      trip.availableSeats > 0
                                          ? '${trip.availableSeats} seat(s) left'
                                          : 'Full',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: trip.availableSeats > 0
                                            ? Colors.grey.shade700
                                            : Colors.redAccent,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                                Text(
                                  '${trip.price.toStringAsFixed(0)} DA',
                                  style: const TextStyle(
                                      color: Color(0xFF4CE5B1),
                                      fontWeight: FontWeight.bold,
                                      fontSize: 18),
                                ),
                              ],
                            ),
                            
                            const SizedBox(height: 8),
                            // Rating
                            Row(
                              children: const [
                                Icon(Icons.star, color: Colors.amber, size: 16),
                                Icon(Icons.star, color: Colors.amber, size: 16),
                                Icon(Icons.star, color: Colors.amber, size: 16),
                                Icon(Icons.star, color: Colors.amber, size: 16),
                                Icon(Icons.star_half, color: Colors.amber, size: 16),
                                SizedBox(width: 4),
                                Text('4.5', style: TextStyle(fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );

                if (isFull) {
                  cardContent = Stack(
                    children: [
                      Opacity(
                        opacity: 0.4,
                        child: cardContent,
                      ),
                      Positioned.fill(
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.7),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Text(
                              'Trip is fully booked',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                }

                return GestureDetector(
                  onTap: isFull
                      ? null
                      : () {
                          Navigator.pushNamed(context, '/seat-selection', arguments: trip);
                        },
                  child: cardContent,
                );
              },
            ),
          ],
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        type: BottomNavigationBarType.fixed,
        selectedItemColor: const Color(0xFF4CE5B1),
        unselectedItemColor: Colors.grey,
        onTap: (index) {
          if (index == 4) {
             _logout();
             return;
          }
          _onBottomNavTapped(index);
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.history),
            label: 'History',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.local_shipping),
            label: 'Delivery',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.discount),
            label: 'Discounts',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.logout),
            label: 'Logout',
          ),
        ],
      ),
    );
  }
}
"""
    with codecs.open('lib/pages/home_page.dart', 'w', 'utf-8') as f:
        f.write(original_code)

if __name__ == '__main__':
    main()
