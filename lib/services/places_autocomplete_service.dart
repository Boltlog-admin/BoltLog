import 'dart:convert';
import 'package:http/http.dart' as http;
import '../constants/app_constants.dart';

/// Google Places API (Geocoding/Places) for address autocomplete. inDrive-style: convert text to coordinates.
class PlacesAutocompleteService {
  static const String _apiKey = 'AIzaSyAuZTJgvpOr20n0yeK0s1OMQfiSSRWGSWI';
  static const String _autocompleteUrl = 'https://maps.googleapis.com/maps/api/place/autocomplete/json';
  static const String _detailsUrl = 'https://maps.googleapis.com/maps/api/place/details/json';

  /// Fetch place predictions for address autocomplete.
  Future<List<PlacePrediction>> getPredictions(String input, {String? sessionToken}) async {
    if (input.trim().isEmpty) return [];
    try {
      final query = <String, String>{
        'input': input.trim(),
        'key': _apiKey,
        'types': 'address',
      };
      if (sessionToken != null) query['sessiontoken'] = sessionToken;
      final uri = Uri.parse(_autocompleteUrl).replace(queryParameters: query);
      final response = await http.get(uri).timeout(
        const Duration(seconds: AppConstants.connectionTimeoutSeconds),
      );
      if (response.statusCode != 200) return [];
      final data = json.decode(response.body) as Map<String, dynamic>;
      if (data['status'] != 'OK' && data['status'] != 'ZERO_RESULTS') return [];
      final list = data['predictions'] as List?;
      if (list == null) return [];
      return list.map((e) {
        final m = e as Map<String, dynamic>;
        return PlacePrediction(
          placeId: m['place_id'] as String? ?? '',
          description: m['description'] as String? ?? '',
          mainText: (m['structured_formatting'] as Map?)?['main_text'] as String?,
          secondaryText: (m['structured_formatting'] as Map?)?['secondary_text'] as String?,
        );
      }).toList();
    } catch (e) {
      return [];
    }
  }

  /// Get lat/lng and formatted address for a place_id.
  Future<PlaceDetails?> getPlaceDetails(String placeId) async {
    if (placeId.isEmpty) return null;
    try {
      final uri = Uri.parse(_detailsUrl).replace(queryParameters: {
        'place_id': placeId,
        'key': _apiKey,
        'fields': 'geometry,formatted_address',
      });
      final response = await http.get(uri).timeout(
        const Duration(seconds: AppConstants.connectionTimeoutSeconds),
      );
      if (response.statusCode != 200) return null;
      final data = json.decode(response.body) as Map<String, dynamic>;
      if (data['status'] != 'OK') return null;
      final result = data['result'] as Map<String, dynamic>?;
      if (result == null) return null;
      final geo = result['geometry'] as Map<String, dynamic>?;
      final loc = geo?['location'] as Map<String, dynamic>?;
      final lat = (loc?['lat'] as num?)?.toDouble();
      final lng = (loc?['lng'] as num?)?.toDouble();
      final address = result['formatted_address'] as String? ?? '';
      if (lat == null || lng == null) return null;
      return PlaceDetails(lat: lat, lng: lng, formattedAddress: address);
    } catch (e) {
      return null;
    }
  }
}

class PlacePrediction {
  final String placeId;
  final String description;
  final String? mainText;
  final String? secondaryText;
  PlacePrediction({
    required this.placeId,
    required this.description,
    this.mainText,
    this.secondaryText,
  });
}

class PlaceDetails {
  final double lat;
  final double lng;
  final String formattedAddress;
  PlaceDetails({required this.lat, required this.lng, required this.formattedAddress});
}
