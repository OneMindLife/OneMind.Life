import 'package:flutter_timezone/flutter_timezone.dart';

/// Full list of IANA timezones, organized with common ones first.
/// This list covers all major populated timezones worldwide.
const allTimezones = [
  // === Common US Timezones ===
  'America/New_York',
  'America/Chicago',
  'America/Denver',
  'America/Los_Angeles',
  'America/Anchorage',
  'Pacific/Honolulu',

  // === Common European ===
  'Europe/London',
  'Europe/Paris',
  'Europe/Berlin',
  'Europe/Madrid',
  'Europe/Rome',
  'Europe/Amsterdam',
  'Europe/Brussels',
  'Europe/Vienna',
  'Europe/Zurich',
  'Europe/Stockholm',
  'Europe/Oslo',
  'Europe/Copenhagen',
  'Europe/Helsinki',
  'Europe/Warsaw',
  'Europe/Prague',
  'Europe/Budapest',
  'Europe/Athens',
  'Europe/Bucharest',
  'Europe/Moscow',
  'Europe/Istanbul',
  'Europe/Kiev',
  'Europe/Dublin',
  'Europe/Lisbon',

  // === Common Asian ===
  'Asia/Tokyo',
  'Asia/Shanghai',
  'Asia/Hong_Kong',
  'Asia/Singapore',
  'Asia/Seoul',
  'Asia/Taipei',
  'Asia/Bangkok',
  'Asia/Ho_Chi_Minh',
  'Asia/Jakarta',
  'Asia/Manila',
  'Asia/Kuala_Lumpur',
  'Asia/Kolkata',
  'Asia/Mumbai',
  'Asia/Dubai',
  'Asia/Riyadh',
  'Asia/Tel_Aviv',
  'Asia/Jerusalem',
  'Asia/Karachi',
  'Asia/Dhaka',
  'Asia/Kathmandu',
  'Asia/Colombo',
  'Asia/Yangon',
  'Asia/Almaty',
  'Asia/Tashkent',
  'Asia/Tbilisi',
  'Asia/Yerevan',
  'Asia/Baku',

  // === Oceania ===
  'Australia/Sydney',
  'Australia/Melbourne',
  'Australia/Brisbane',
  'Australia/Perth',
  'Australia/Adelaide',
  'Australia/Darwin',
  'Australia/Hobart',
  'Pacific/Auckland',
  'Pacific/Fiji',
  'Pacific/Guam',

  // === Americas (non-US) ===
  'America/Toronto',
  'America/Vancouver',
  'America/Montreal',
  'America/Edmonton',
  'America/Winnipeg',
  'America/Halifax',
  'America/St_Johns',
  'America/Mexico_City',
  'America/Cancun',
  'America/Tijuana',
  'America/Bogota',
  'America/Lima',
  'America/Santiago',
  'America/Buenos_Aires',
  'America/Sao_Paulo',
  'America/Rio_de_Janeiro',
  'America/Caracas',
  'America/La_Paz',
  'America/Montevideo',
  'America/Asuncion',
  'America/Guayaquil',
  'America/Panama',
  'America/Costa_Rica',
  'America/Guatemala',
  'America/Havana',
  'America/Jamaica',
  'America/Puerto_Rico',
  'America/Santo_Domingo',
  'America/Port-au-Prince',

  // === Africa ===
  'Africa/Cairo',
  'Africa/Johannesburg',
  'Africa/Lagos',
  'Africa/Nairobi',
  'Africa/Casablanca',
  'Africa/Algiers',
  'Africa/Tunis',
  'Africa/Accra',
  'Africa/Addis_Ababa',
  'Africa/Dar_es_Salaam',
  'Africa/Kampala',
  'Africa/Khartoum',
  'Africa/Kinshasa',
  'Africa/Luanda',
  'Africa/Maputo',
  'Africa/Harare',

  // === Middle East ===
  'Asia/Baghdad',
  'Asia/Beirut',
  'Asia/Damascus',
  'Asia/Amman',
  'Asia/Kuwait',
  'Asia/Qatar',
  'Asia/Bahrain',
  'Asia/Muscat',

  // === Atlantic/Indian Ocean ===
  'Atlantic/Reykjavik',
  'Atlantic/Azores',
  'Atlantic/Canary',
  'Atlantic/Cape_Verde',
  'Indian/Mauritius',
  'Indian/Maldives',

  // === UTC ===
  'UTC',

  // === Additional US/Canada ===
  'America/Phoenix',
  'America/Detroit',
  'America/Indianapolis',
  'America/Kentucky/Louisville',
  'America/Boise',
  'America/Juneau',
  'America/Adak',

  // === Additional Asia ===
  'Asia/Vladivostok',
  'Asia/Magadan',
  'Asia/Kamchatka',
  'Asia/Novosibirsk',
  'Asia/Krasnoyarsk',
  'Asia/Irkutsk',
  'Asia/Yakutsk',
  'Asia/Sakhalin',
  'Asia/Brunei',
  'Asia/Makassar',
  'Asia/Jayapura',
  'Asia/Dili',
  'Asia/Phnom_Penh',
  'Asia/Vientiane',
  'Asia/Ulaanbaatar',
  'Asia/Pyongyang',
  'Asia/Thimphu',
  'Asia/Ashgabat',
  'Asia/Dushanbe',
  'Asia/Bishkek',
  'Asia/Samarkand',
  'Asia/Oral',
  'Asia/Aqtau',
  'Asia/Qyzylorda',
  'Asia/Hovd',
  'Asia/Choibalsan',

  // === Additional Pacific ===
  'Pacific/Port_Moresby',
  'Pacific/Noumea',
  'Pacific/Efate',
  'Pacific/Guadalcanal',
  'Pacific/Majuro',
  'Pacific/Kosrae',
  'Pacific/Palau',
  'Pacific/Chuuk',
  'Pacific/Pohnpei',
  'Pacific/Tarawa',
  'Pacific/Funafuti',
  'Pacific/Wallis',
  'Pacific/Fakaofo',
  'Pacific/Apia',
  'Pacific/Tongatapu',
  'Pacific/Chatham',
  'Pacific/Kiritimati',
  'Pacific/Enderbury',
  'Pacific/Gambier',
  'Pacific/Marquesas',
  'Pacific/Tahiti',
  'Pacific/Pitcairn',
  'Pacific/Easter',
  'Pacific/Galapagos',
  'Pacific/Rarotonga',
  'Pacific/Niue',
  'Pacific/Pago_Pago',
  'Pacific/Midway',
  'Pacific/Wake',
  'Pacific/Johnston',
  'Pacific/Kwajalein',
  'Pacific/Norfolk',

  // === Additional Europe ===
  'Europe/Luxembourg',
  'Europe/Monaco',
  'Europe/San_Marino',
  'Europe/Vatican',
  'Europe/Andorra',
  'Europe/Gibraltar',
  'Europe/Malta',
  'Europe/Sarajevo',
  'Europe/Zagreb',
  'Europe/Ljubljana',
  'Europe/Skopje',
  'Europe/Belgrade',
  'Europe/Podgorica',
  'Europe/Tirane',
  'Europe/Sofia',
  'Europe/Chisinau',
  'Europe/Minsk',
  'Europe/Vilnius',
  'Europe/Riga',
  'Europe/Tallinn',
  'Europe/Kaliningrad',
  'Europe/Samara',
  'Europe/Volgograd',
  'Europe/Saratov',
  'Europe/Ulyanovsk',
  'Europe/Kirov',

  // === Additional Americas ===
  'America/Araguaina',
  'America/Bahia',
  'America/Belem',
  'America/Boa_Vista',
  'America/Campo_Grande',
  'America/Cuiaba',
  'America/Fortaleza',
  'America/Maceio',
  'America/Manaus',
  'America/Noronha',
  'America/Porto_Velho',
  'America/Recife',
  'America/Santarem',
  'America/Cordoba',
  'America/Jujuy',
  'America/Mendoza',
  'America/Catamarca',
  'America/La_Rioja',
  'America/San_Juan',
  'America/San_Luis',
  'America/Tucuman',
  'America/Ushuaia',
  'America/Punta_Arenas',

  // === Additional Africa ===
  'Africa/Abidjan',
  'Africa/Bamako',
  'Africa/Banjul',
  'Africa/Bissau',
  'Africa/Conakry',
  'Africa/Dakar',
  'Africa/Freetown',
  'Africa/Lome',
  'Africa/Monrovia',
  'Africa/Niamey',
  'Africa/Nouakchott',
  'Africa/Ouagadougou',
  'Africa/Brazzaville',
  'Africa/Douala',
  'Africa/Libreville',
  'Africa/Malabo',
  'Africa/Ndjamena',
  'Africa/Porto-Novo',
  'Africa/Sao_Tome',
  'Africa/Bangui',
  'Africa/Bujumbura',
  'Africa/Gaborone',
  'Africa/Kigali',
  'Africa/Lubumbashi',
  'Africa/Lusaka',
  'Africa/Maseru',
  'Africa/Mbabane',
  'Africa/Blantyre',
  'Africa/Windhoek',
  'Africa/Juba',
  'Africa/Mogadishu',
  'Africa/Asmara',
  'Africa/Djibouti',
  'Africa/Tripoli',
  'Africa/El_Aaiun',
  'Africa/Ceuta',

  // === Antarctica ===
  'Antarctica/Casey',
  'Antarctica/Davis',
  'Antarctica/DumontDUrville',
  'Antarctica/Macquarie',
  'Antarctica/Mawson',
  'Antarctica/McMurdo',
  'Antarctica/Palmer',
  'Antarctica/Rothera',
  'Antarctica/Syowa',
  'Antarctica/Troll',
  'Antarctica/Vostok',

  // === Arctic ===
  'Arctic/Longyearbyen',

  // === Indian Ocean ===
  'Indian/Antananarivo',
  'Indian/Chagos',
  'Indian/Christmas',
  'Indian/Cocos',
  'Indian/Comoro',
  'Indian/Kerguelen',
  'Indian/Mahe',
  'Indian/Mayotte',
  'Indian/Reunion',
];

/// Detects user's local timezone.
///
/// Returns the device's timezone if it's in the supported list,
/// otherwise returns the detected timezone anyway (IANA format).
Future<String> detectUserTimezone() async {
  try {
    final localTz = await FlutterTimezone.getLocalTimezone();

    // Return the detected timezone - it's always valid IANA format
    if (allTimezones.contains(localTz)) {
      return localTz;
    }

    // If not in our list, still return it but also try offset mapping
    // This handles edge cases where device returns an alias
    return localTz;
  } catch (_) {
    return mapOffsetToTimezone(DateTime.now().timeZoneOffset);
  }
}

/// Maps a UTC offset to a common timezone.
///
/// This is a fallback when timezone detection fails.
String mapOffsetToTimezone(Duration offset) {
  final hours = offset.inHours;
  final minutes = offset.inMinutes % 60;

  // Handle half-hour and 45-minute offsets
  if (minutes == 30) {
    return switch (hours) {
      5 => 'Asia/Kolkata', // IST +5:30
      -3 => 'America/St_Johns', // NST -3:30
      4 => 'Asia/Kabul', // AFT +4:30
      6 => 'Asia/Yangon', // MMT +6:30
      9 => 'Australia/Darwin', // ACST +9:30
      10 => 'Australia/Adelaide', // ACDT +10:30
      _ => 'UTC',
    };
  }

  if (minutes == 45) {
    return switch (hours) {
      5 => 'Asia/Kathmandu', // NPT +5:45
      8 => 'Australia/Eucla', // ACWST +8:45
      12 => 'Pacific/Chatham', // CHAST +12:45
      _ => 'UTC',
    };
  }

  // Standard hour offsets
  return switch (hours) {
    -12 => 'Pacific/Kwajalein',
    -11 => 'Pacific/Pago_Pago',
    -10 => 'Pacific/Honolulu',
    -9 => 'America/Anchorage',
    -8 => 'America/Los_Angeles',
    -7 => 'America/Denver',
    -6 => 'America/Chicago',
    -5 => 'America/New_York',
    -4 => 'America/Halifax',
    -3 => 'America/Sao_Paulo',
    -2 => 'Atlantic/South_Georgia',
    -1 => 'Atlantic/Azores',
    0 => 'UTC',
    1 => 'Europe/Paris',
    2 => 'Europe/Helsinki',
    3 => 'Europe/Moscow',
    4 => 'Asia/Dubai',
    5 => 'Asia/Karachi',
    6 => 'Asia/Dhaka',
    7 => 'Asia/Bangkok',
    8 => 'Asia/Shanghai',
    9 => 'Asia/Tokyo',
    10 => 'Australia/Sydney',
    11 => 'Pacific/Noumea',
    12 => 'Pacific/Auckland',
    13 => 'Pacific/Tongatapu',
    14 => 'Pacific/Kiritimati',
    _ => 'UTC',
  };
}

/// Returns a display-friendly name for a timezone.
/// e.g., 'America/New_York' -> 'New York (America)'
String getTimezoneDisplayName(String timezone) {
  if (timezone == 'UTC') return 'UTC';

  final parts = timezone.split('/');
  if (parts.length < 2) return timezone;

  final region = parts[0];
  final city = parts.sublist(1).join('/').replaceAll('_', ' ');

  return '$city ($region)';
}
