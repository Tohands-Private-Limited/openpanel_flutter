const kDefaultBaseUrl = 'https://api.openpanel.dev';

/// Path of the unified tracking endpoint. Every request — single events and
/// the `{"type": "batch"}` envelope alike — POSTs here.
const kTrackPath = '/track';
