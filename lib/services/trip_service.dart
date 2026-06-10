import 'package:firebase_database/firebase_database.dart';
import '../models/trip_model.dart';
import 'chat_service.dart';

class TripService {
  final DatabaseReference _tripsRef = FirebaseDatabase.instance.ref().child('trips');
  final DatabaseReference _historyRef = FirebaseDatabase.instance.ref().child('history');
  final DatabaseReference _userChatsRef = FirebaseDatabase.instance.ref().child('userChats');
  final DatabaseReference _chatsRef = FirebaseDatabase.instance.ref().child('chats');

  // Stream active trips for passengers (e.g., Home Page)
  Stream<List<Trip>> getActiveTripsStream() {
    return _tripsRef.orderByChild('status').equalTo('active').onValue.map((event) {
      if (!event.snapshot.exists || event.snapshot.value == null) return [];
      
      final Map<dynamic, dynamic> tripsMap = event.snapshot.value as Map<dynamic, dynamic>;
      return tripsMap.entries.map((e) {
        return Trip.fromMap(e.value as Map<dynamic, dynamic>, e.key.toString());
      }).toList();
    });
  }

  // Stream driver's own active trips
  Stream<List<Trip>> getDriverTripsStream(String driverId) {
    return _tripsRef.orderByChild('driverId').equalTo(driverId).onValue.map((event) {
      if (!event.snapshot.exists || event.snapshot.value == null) return [];
      
      final Map<dynamic, dynamic> tripsMap = event.snapshot.value as Map<dynamic, dynamic>;
      return tripsMap.entries.map((e) {
        return Trip.fromMap(e.value as Map<dynamic, dynamic>, e.key.toString());
      }).where((trip) => trip.status == 'active' || trip.status == 'full').toList();
    });
  }

  // Create a new trip
  Future<void> createTrip(Map<String, dynamic> tripData) async {
    final newTripRef = _tripsRef.push();
    final tripId = newTripRef.key;
    if (tripId == null) throw Exception("Failed to generate trip ID");

    tripData['createdAt'] = ServerValue.timestamp;
    tripData['status'] = 'active';

    // Calculate 10% commission on the base price
    double basePrice = (tripData['price'] as num?)?.toDouble() ?? 0.0;
    tripData['commissionAmount'] = basePrice * 0.10;

    await newTripRef.set(tripData);
  }

  // Edit an existing trip
  Future<void> updateTrip(String tripId, Map<String, dynamic> data) async {
     await _tripsRef.child(tripId).update(data);
  }

  // Delete trip
  Future<void> deleteTrip(String tripId) async {
    await _tripsRef.child(tripId).remove();
    // Also cleanup chat to save space
    await _chatsRef.child(tripId).remove();
  }

  // Finish Trip -> Move to history, hide from home
  Future<void> finishTrip(String tripId, String driverId) async {
    final tripSnapshot = await _tripsRef.child(tripId).get();
    if (!tripSnapshot.exists || tripSnapshot.value == null) return;
    
    final Map<dynamic, dynamic> tripData = tripSnapshot.value as Map<dynamic, dynamic>;
    tripData['status'] = 'archived';
    tripData['finishedAt'] = ServerValue.timestamp;

    // Move to driver's history
    await _historyRef.child(driverId).child('trips').child(tripId).set(tripData);
    
    // Move to passengers history
    if (tripData['seats'] != null) {
      final seatsMap = tripData['seats'] as Map<dynamic, dynamic>;
      for (var seat in seatsMap.values) {
        if (seat != null && seat['reservedBy'] != null) {
          final passengerId = seat['reservedBy'];
          await _historyRef.child(passengerId).child('trips').child(tripId).set(tripData);
        }
      }
    }

    if (tripData['takenSeats'] != null) {
      final seatsMap = tripData['takenSeats'] as Map<dynamic, dynamic>;
      for (var seat in seatsMap.values) {
        if (seat != null && seat['userId'] != null) {
          final passengerId = seat['userId'];
          await _historyRef.child(passengerId).child('trips').child(tripId).set(tripData);
        }
      }
    }

    await _tripsRef.child(tripId).update({
      'status': 'archived',
      'finishedAt': ServerValue.timestamp,
    });

    await chatService.sendMessage(
      tripId,
      'system',
      'نظام',
      'تم إنهاء الرحلة وأرشفتها',
      isSystemMessage: true,
    );

    // Keep chats and archived trip visible in messages history tab.
  }

  // Reserve a Seat (Transaction to avoid double-booking)
  Future<void> reserveSeat(String tripId, String seatId, String passengerId, String gender) async {
    final tripRef = _tripsRef.child(tripId);
    
    await tripRef.runTransaction((Object? post) {
      if (post == null) return Transaction.abort();

      Map<dynamic, dynamic> trip = Map<dynamic, dynamic>.from(post as Map);
      
      trip['seats'] ??= {};
      
      final seats = Map<dynamic, dynamic>.from(trip['seats']);
      
      if (seats[seatId] != null && seats[seatId]['status'] == 'reserved') {
        // Already reserved
        return Transaction.abort();
      }

      seats[seatId] = {
        'reservedBy': passengerId,
        'gender': gender,
        'status': 'reserved',
        'timestamp': ServerValue.timestamp,
      };

      trip['availableSeats'] = (trip['availableSeats'] as int? ?? 1) - 1;
      
      if (trip['availableSeats'] == 0) {
        trip['status'] = 'full';
      }

      trip['seats'] = seats;
      
      return Transaction.success(trip);
    }).then((result) async {
       if (result.committed) {
         // Add to userChats so they can start texting the driver
         await _userChatsRef.child(passengerId).child(tripId).set({
           'timestamp': ServerValue.timestamp,
           'role': 'passenger'
         });
         
         // Driver already has the chat or will get it. We should ensure driver has it.
         final tripSnapshot = await tripRef.get();
         if(tripSnapshot.exists && tripSnapshot.child('driverId').value != null) {
             final driverId = tripSnapshot.child('driverId').value.toString();
             await _userChatsRef.child(driverId).child(tripId).set({
               'timestamp': ServerValue.timestamp,
               'role': 'driver'
             });
         }
       } else {
         throw Exception("Seat already reserved by someone else.");
       }
    });
  }

  // Passenger Cancels Reservation
  Future<void> cancelReservation(String tripId, String seatId, String passengerId) async {
    final tripRef = _tripsRef.child(tripId);
    
    await tripRef.runTransaction((Object? post) {
      if (post == null) return Transaction.abort();

      Map<dynamic, dynamic> trip = Map<dynamic, dynamic>.from(post as Map);
      
      if (trip['seats'] == null) return Transaction.success(trip);
      
      final seats = Map<dynamic, dynamic>.from(trip['seats']);
      
      if (seats[seatId] != null && seats[seatId]['reservedBy'] == passengerId) {
        seats.remove(seatId);
        trip['availableSeats'] = (trip['availableSeats'] as int? ?? 0) + 1;
        if (trip['status'] == 'full') {
          trip['status'] = 'active';
        }
        trip['seats'] = seats;
        return Transaction.success(trip);
      }
      
      return Transaction.abort();
    });
  }
}

final tripService = TripService();
