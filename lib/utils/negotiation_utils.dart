import '../models/ride_model.dart';

/// Returns true when there is an active negotiation on this ride.
/// A negotiation is considered active while:
/// - status is 'pending' (negotiation stage)
/// - priceStatus is 'pending' (no final decision)
/// - a specific transporter is in play ([negotiatingTransporterId] and/or
///   [acceptedTransporterId]; counter-offer flows often clear [acceptedTransporterId])
bool negotiationInProgress(RideModel ride) {
  if (ride.status != 'pending' || ride.priceStatus != 'pending') {
    return false;
  }
  final neg = ride.negotiatingTransporterId?.trim();
  final acc = ride.acceptedTransporterId?.trim();
  return (neg != null && neg.isNotEmpty) || (acc != null && acc.isNotEmpty);
}

/// Amount on the table for UI: agreed price, else latest counter-offer (overwrites
/// the initial proposal in display), else sender's original [RideModel.price].
double? effectiveOfferAmount(RideModel ride) {
  return ride.finalPrice ?? ride.counterOffer ?? ride.price;
}

/// Primary label for the single price row during negotiation.
String effectiveOfferLabel(RideModel ride, {required bool isSender}) {
  if (ride.finalPrice != null) return 'Agreed price';
  if (ride.counterOffer != null) return 'Current offer';
  return isSender ? 'Your offer' : 'Sender\'s offer';
}

/// Optional one-line hint: who last moved the number (only when counter exists).
String? effectiveOfferLastMoveHint(RideModel ride) {
  if (ride.finalPrice != null) return null;
  if (ride.counterOffer == null) return null;
  return ride.lastCounterOfferBy == 'transporter'
      ? 'Last proposed by transporter'
      : 'Last proposed by sender';
}

