import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/places_autocomplete_service.dart';

/// Address field with Google Places autocomplete. inDrive-style: find pickup/dropoff by text.
class AddressAutocompleteField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final void Function(double lat, double lng, String address) onPlaceSelected;
  final void Function()? onClear;

  const AddressAutocompleteField({
    super.key,
    required this.controller,
    required this.label,
    required this.onPlaceSelected,
    this.onClear,
  });

  @override
  State<AddressAutocompleteField> createState() => _AddressAutocompleteFieldState();
}

class _AddressAutocompleteFieldState extends State<AddressAutocompleteField> {
  final PlacesAutocompleteService _places = PlacesAutocompleteService();
  List<PlacePrediction> _predictions = [];
  bool _loading = false;
  bool _showOverlay = false;
  Timer? _debounce;
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _removeOverlay();
    widget.controller.removeListener(_onTextChanged);
    super.dispose();
  }

  void _onTextChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      _fetchPredictions(widget.controller.text);
    });
  }

  Future<void> _fetchPredictions(String input) async {
    if (input.trim().length < 3) {
      setState(() {
        _predictions = [];
        _showOverlay = false;
        _loading = false;
      });
      _removeOverlay();
      return;
    }
    setState(() => _loading = true);
    final list = await _places.getPredictions(input);
    if (!mounted) return;
    setState(() {
      _predictions = list;
      _loading = false;
      _showOverlay = list.isNotEmpty;
    });
    if (_showOverlay) _showPredictionsOverlay();
    else _removeOverlay();
  }

  void _showPredictionsOverlay() {
    _removeOverlay();
    final box = context.findRenderObject() as RenderBox?;
    final width = box?.size.width ?? MediaQuery.of(context).size.width - 32;
    _overlayEntry = OverlayEntry(
      builder: (context) => CompositedTransformFollower(
        link: _layerLink,
        followerAnchor: Alignment.topLeft,
        targetAnchor: Alignment.bottomLeft,
        offset: const Offset(0, 4),
        child: SizedBox(
          width: width,
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(8),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: _predictions.length,
                itemBuilder: (context, index) {
                  final p = _predictions[index];
                  return ListTile(
                    dense: true,
                    title: Text(
                      p.description,
                      style: GoogleFonts.inter(fontSize: 14),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () => _selectPlace(p),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
    Overlay.of(context).insert(_overlayEntry!);
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  Future<void> _selectPlace(PlacePrediction p) async {
    _removeOverlay();
    setState(() {
      _predictions = [];
      _showOverlay = false;
    });
    widget.controller.text = p.description;
    final details = await _places.getPlaceDetails(p.placeId);
    if (!mounted || details == null) return;
    widget.onPlaceSelected(details.lat, details.lng, details.formattedAddress);
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: TextField(
        controller: widget.controller,
        decoration: InputDecoration(
          labelText: widget.label,
          hintText: 'Start typing an address...',
          suffixIcon: _loading
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : (widget.controller.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 20),
                      onPressed: () {
                        widget.controller.clear();
                        widget.onClear?.call();
                      },
                    )
                  : null),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
        style: GoogleFonts.inter(fontSize: 16),
        onTap: () {
          if (widget.controller.text.trim().length >= 3 && _predictions.isNotEmpty) {
            _showPredictionsOverlay();
          }
        },
      ),
    );
  }
}
