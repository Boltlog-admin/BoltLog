import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/ride_model.dart';
import '../models/user_model.dart';
import '../services/ride_service.dart';
import '../widgets/storage_image.dart';
import 'transporter_selection_screen.dart';

class TransporterViewersScreen extends StatefulWidget {
  final String rideId;

  const TransporterViewersScreen({
    super.key,
    required this.rideId,
  });

  @override
  State<TransporterViewersScreen> createState() => _TransporterViewersScreenState();
}

class _TransporterViewersScreenState extends State<TransporterViewersScreen> {
  final RideService _rideService = RideService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  RideModel? _cachedRide;

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text(
          'Transporters Viewing',
          style: GoogleFonts.inter(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: const Color(0xFF1E40AF),
          ),
        ),
      ),
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // Request details: persist last loaded ride so UI doesn't disappear on stream flicker
            StreamBuilder<RideModel?>(
              stream: _rideService.streamRideById(widget.rideId),
              builder: (context, snapshot) {
                if (snapshot.data != null) _cachedRide = snapshot.data;
                final ride = snapshot.data ?? _cachedRide;
                if (ride == null) {
                  return Container(
                    width: double.infinity,
                    margin: const EdgeInsets.all(16),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: const Color(0xFF2563EB),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Loading request details…',
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }
                return Container(
                  width: double.infinity,
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Your Request',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        ride.packageDescription ?? 'Transport request',
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF1E40AF),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${ride.pickupLocation} → ${ride.dropoffLocation}',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          color: Colors.grey.shade700,
                        ),
                      ),
                      if (ride.price != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Your offer: \$${ride.price!.toStringAsFixed(2)}',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF2563EB),
                          ),
                        ),
                      ],
                      // Persistent status: sender sent counter-offer, waiting for transporter
                      if (ride.status == 'pending' && ride.priceStatus == 'pending' && ride.lastCounterOfferBy == 'sender') ...[
                        const SizedBox(height: 12),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.amber.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.amber.shade200),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.schedule, size: 18, color: Colors.amber.shade800),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Waiting for transporter to respond',
                                  style: GoogleFonts.inter(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.amber.shade900,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
            // Online transporters viewing
            Expanded(
              child: StreamBuilder<List<UserModel>>(
                stream: _rideService.streamOnlineViewers(widget.rideId),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (snapshot.hasError) {
                    return Center(
                      child: Text(
                        'Error: ${snapshot.error}',
                        style: GoogleFonts.inter(color: Colors.red),
                      ),
                    );
                  }

                  final viewers = snapshot.data ?? [];

                  if (viewers.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.visibility_off,
                            size: 64,
                            color: Colors.grey.shade400,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No transporters viewing',
                            style: GoogleFonts.inter(
                              fontSize: 18,
                              color: Colors.grey.shade600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Online transporters viewing your request will appear here',
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              color: Colors.grey.shade500,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    );
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: viewers.length,
                    itemBuilder: (context, index) {
                      final transporter = viewers[index];
                      return _buildTransporterCard(context, transporter);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTransporterCard(BuildContext context, UserModel transporter) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      elevation: 2,
      child: InkWell(
        onTap: () {
          // Navigate to selection screen to see offers and select
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => TransporterSelectionScreen(rideId: widget.rideId),
            ),
          );
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Avatar: prefer truck side view, then selfie/photo
              StorageAvatar(
                pathOrUrl: (transporter.truckSideImageUrl != null && transporter.truckSideImageUrl!.isNotEmpty)
                    ? transporter.truckSideImageUrl
                    : ((transporter.photoUrl != null && transporter.photoUrl!.isNotEmpty)
                        ? transporter.photoUrl
                        : transporter.selfieImageUrl),
                radius: 28,
                backgroundColor: const Color(0xFF2563EB).withOpacity(0.1),
                child: ((transporter.truckSideImageUrl == null || transporter.truckSideImageUrl!.isEmpty) &&
                        (transporter.photoUrl == null || transporter.photoUrl!.isNotEmpty) &&
                        (transporter.selfieImageUrl == null || transporter.selfieImageUrl!.isNotEmpty))
                    ? Text(
                        (transporter.displayName ?? 'T')[0].toUpperCase(),
                        style: GoogleFonts.inter(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF2563EB),
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 16),
              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            transporter.displayName ?? 'Transporter',
                            style: GoogleFonts.inter(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFF1E40AF),
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.green.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: const BoxDecoration(
                                  color: Colors.green,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Online',
                                style: GoogleFonts.inter(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.green.shade700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    if (transporter.truckType != null) ...[
                      Text(
                        _getVehicleTypeLabel(transporter.truckType!),
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(height: 4),
                    ],
                    if (transporter.rating != null) ...[
                      Row(
                        children: [
                          Icon(
                            Icons.star,
                            size: 14,
                            color: Colors.amber,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            transporter.rating!.toStringAsFixed(1),
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey.shade700,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right,
                color: Colors.grey,
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _getVehicleTypeLabel(String truckType) {
    switch (truckType) {
      case 'bike_express':
        return 'Bike Express';
      case 'runner':
        return 'Runner';
      case 'pickup':
        return 'Pickup (1.2t)';
      case 'truck_5t':
        return 'Truck (5t)';
      case 'truck_10t':
        return 'Truck (10t)';
      case 'truck_20t':
        return 'Truck (20t)';
      default:
        return truckType;
    }
  }
}
