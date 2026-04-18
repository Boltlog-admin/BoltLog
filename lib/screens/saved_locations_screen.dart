import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/saved_location_model.dart';
import '../services/saved_location_service.dart';
import 'location_picker_screen.dart';

class SavedLocationsScreen extends StatelessWidget {
  const SavedLocationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final locationService = SavedLocationService();

    if (user == null) {
      return const Scaffold(
        body: Center(child: Text('Please log in')),
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text(
          'Saved Locations',
          style: GoogleFonts.inter(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: const Color(0xFF1E40AF), // Blue-700
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add, color: Color(0xFF1E40AF)), // Blue-700
            onPressed: () async {
              final result = await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const LocationPickerScreen(
                    title: 'Add Saved Location',
                  ),
                ),
              );
              if (result != null) {
                // Show dialog to enter name
                final nameController = TextEditingController();
                final result2 = await showDialog<String>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Name this location'),
                    content: TextField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        hintText: 'e.g., Home, Work',
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancel'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context, nameController.text),
                        child: const Text('Save'),
                      ),
                    ],
                  ),
                );
                if (result2 != null && result2.isNotEmpty) {
                  final location = SavedLocationModel(
                    userId: user.uid,
                    name: result2,
                    address: result['address'],
                    latitude: result['latitude'],
                    longitude: result['longitude'],
                    createdAt: DateTime.now(),
                  );
                  try {
                    await locationService.saveLocation(location);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Location saved!'),
                          backgroundColor: Colors.green,
                        ),
                      );
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Error: ${e.toString()}'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
                }
              }
            },
          ),
        ],
      ),
      body: SafeArea(
        child: StreamBuilder<List<SavedLocationModel>>(
          stream: locationService.streamSavedLocations(user.uid),
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

            final locations = snapshot.data ?? [];

            if (locations.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.location_off,
                      size: 64,
                      color: Colors.grey.shade400,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No saved locations',
                      style: GoogleFonts.inter(
                        fontSize: 18,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Tap + to add a location',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ],
                ),
              );
            }

            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: locations.length,
              itemBuilder: (context, index) {
                final location = locations[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ListTile(
                    leading: Icon(
                      location.name.toLowerCase() == 'home'
                          ? Icons.home
                          : location.name.toLowerCase() == 'work'
                              ? Icons.work
                              : Icons.location_on,
                      color: const Color(0xFF2563EB), // Blue-600
                    ),
                    title: Text(
                      location.name,
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF1E40AF), // Blue-700
                      ),
                    ),
                    subtitle: Text(
                      location.address,
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        color: Colors.grey.shade600,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                      onPressed: () async {
                        if (location.id != null) {
                          try {
                            await locationService.deleteLocation(location.id!);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Location deleted'),
                                  backgroundColor: Colors.green,
                                ),
                              );
                            }
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Error: ${e.toString()}'),
                                  backgroundColor: Colors.red,
                                ),
                              );
                            }
                          }
                        }
                      },
                    ),
                    onTap: () {
                      Navigator.of(context).pop({
                        'address': location.address,
                        'latitude': location.latitude,
                        'longitude': location.longitude,
                      });
                    },
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

