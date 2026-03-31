/// מפת קואורדינטות ערים — מסודרת לפי מדינות ובסדר א-ב
const Map<String, Map<String, Map<String, dynamic>>> cityCoordinates = {
  'ארץ ישראל': {
    'אופקים': {'lat': 31.3111, 'lng': 34.6214, 'elevation': 140.0, 'timezone': 'Asia/Jerusalem'},
    'אילת': {'lat': 29.5581, 'lng': 34.9482, 'elevation': 12.0, 'timezone': 'Asia/Jerusalem'},
    'אלעד': {'lat': 32.0519, 'lng': 34.9517, 'elevation': 75.0, 'timezone': 'Asia/Jerusalem'},
    'אריאל': {'lat': 32.1069, 'lng': 35.1897, 'elevation': 650.0, 'timezone': 'Asia/Jerusalem'},
    'אשדוד': {'lat': 31.8044, 'lng': 34.6553, 'elevation': 50.0, 'timezone': 'Asia/Jerusalem'},
    'אשקלון': {'lat': 31.6688, 'lng': 34.5742, 'elevation': 50.0, 'timezone': 'Asia/Jerusalem'},
    'באר שבע': {'lat': 31.2518, 'lng': 34.7915, 'elevation': 280.0, 'timezone': 'Asia/Jerusalem'},
    'ביתר עילית': {'lat': 31.7025, 'lng': 35.1156, 'elevation': 740.0, 'timezone': 'Asia/Jerusalem'},
    'בית שמש': {'lat': 31.7245, 'lng': 34.9886, 'elevation': 220.0, 'timezone': 'Asia/Jerusalem'},
    'בני ברק': {'lat': 32.0809, 'lng': 34.8338, 'elevation': 50.0, 'timezone': 'Asia/Jerusalem'},
    'בת ים': {'lat': 32.0167, 'lng': 34.7500, 'elevation': 5.0, 'timezone': 'Asia/Jerusalem'},
    'גבעת זאב': {'lat': 31.8467, 'lng': 35.1667, 'elevation': 600.0, 'timezone': 'Asia/Jerusalem'},
    'גבעתיים': {'lat': 32.0706, 'lng': 34.8103, 'elevation': 80.0, 'timezone': 'Asia/Jerusalem'},
    'דימונה': {'lat': 31.0686, 'lng': 35.0333, 'elevation': 550.0, 'timezone': 'Asia/Jerusalem'},
    'הוד השרון': {'lat': 32.1506, 'lng': 34.8889, 'elevation': 40.0, 'timezone': 'Asia/Jerusalem'},
    'הרצליה': {'lat': 32.1624, 'lng': 34.8443, 'elevation': 40.0, 'timezone': 'Asia/Jerusalem'},
    'חיפה': {'lat': 32.7940, 'lng': 34.9896, 'elevation': 30.0, 'timezone': 'Asia/Jerusalem'},
    'חולון': {'lat': 32.0117, 'lng': 34.7689, 'elevation': 54.0, 'timezone': 'Asia/Jerusalem'},
    'טבריה': {'lat': 32.7940, 'lng': 35.5308, 'elevation': -200.0, 'timezone': 'Asia/Jerusalem'},
    'יבנה': {'lat': 31.8781, 'lng': 34.7378, 'elevation': 25.0, 'timezone': 'Asia/Jerusalem'},
    'ירושלים': {'lat': 31.7683, 'lng': 35.2137, 'elevation': 800.0, 'timezone': 'Asia/Jerusalem'},
    'כפר סבא': {'lat': 32.1742, 'lng': 34.9067, 'elevation': 75.0, 'timezone': 'Asia/Jerusalem'},
    'כרמיאל': {'lat': 32.9186, 'lng': 35.2958, 'elevation': 300.0, 'timezone': 'Asia/Jerusalem'},
    'לוד': {'lat': 31.9516, 'lng': 34.8958, 'elevation': 50.0, 'timezone': 'Asia/Jerusalem'},
    'מודיעין עילית': {'lat': 31.9254, 'lng': 35.0364, 'elevation': 400.0, 'timezone': 'Asia/Jerusalem'},
    'מצפה רמון': {'lat': 30.6097, 'lng': 34.8017, 'elevation': 860.0, 'timezone': 'Asia/Jerusalem'},
    'מעלה אדומים': {'lat': 31.7767, 'lng': 35.2973, 'elevation': 740.0, 'timezone': 'Asia/Jerusalem'},
    'נתיבות': {'lat': 31.4214, 'lng': 34.5911, 'elevation': 140.0, 'timezone': 'Asia/Jerusalem'},
    'נתניה': {'lat': 32.3215, 'lng': 34.8532, 'elevation': 30.0, 'timezone': 'Asia/Jerusalem'},
    'נצרת עילית': {'lat': 32.6992, 'lng': 35.3289, 'elevation': 400.0, 'timezone': 'Asia/Jerusalem'},
    'עפולה': {'lat': 32.6078, 'lng': 35.2897, 'elevation': 60.0, 'timezone': 'Asia/Jerusalem'},
    'ערד': {'lat': 31.2592, 'lng': 35.2124, 'elevation': 570.0, 'timezone': 'Asia/Jerusalem'},
    'פתח תקווה': {'lat': 32.0870, 'lng': 34.8873, 'elevation': 80.0, 'timezone': 'Asia/Jerusalem'},
    'צפת': {'lat': 32.9650, 'lng': 35.4951, 'elevation': 900.0, 'timezone': 'Asia/Jerusalem'},
    'קרית אונו': {'lat': 32.0539, 'lng': 34.8581, 'elevation': 75.0, 'timezone': 'Asia/Jerusalem'},
    'קרית ארבע': {'lat': 31.5244, 'lng': 35.1031, 'elevation': 930.0, 'timezone': 'Asia/Jerusalem'},
    'קרית גת': {'lat': 31.6100, 'lng': 34.7642, 'elevation': 68.0, 'timezone': 'Asia/Jerusalem'},
    'קרית מלאכי': {'lat': 31.7289, 'lng': 34.7456, 'elevation': 108.0, 'timezone': 'Asia/Jerusalem'},
    'קרית שמונה': {'lat': 33.2072, 'lng': 35.5692, 'elevation': 135.0, 'timezone': 'Asia/Jerusalem'},
    'ראשון לציון': {'lat': 31.9642, 'lng': 34.8047, 'elevation': 68.0, 'timezone': 'Asia/Jerusalem'},
    'רחובות': {'lat': 31.8947, 'lng': 34.8096, 'elevation': 89.0, 'timezone': 'Asia/Jerusalem'},
    'רמלה': {'lat': 31.9297, 'lng': 34.8667, 'elevation': 108.0, 'timezone': 'Asia/Jerusalem'},
    'רמת גן': {'lat': 32.0719, 'lng': 34.8244, 'elevation': 80.0, 'timezone': 'Asia/Jerusalem'},
    'רעננה': {'lat': 32.1847, 'lng': 34.8706, 'elevation': 45.0, 'timezone': 'Asia/Jerusalem'},
    'תל אביב': {'lat': 32.0853, 'lng': 34.7818, 'elevation': 5.0, 'timezone': 'Asia/Jerusalem'},
    'תפרח': {'lat': 31.3889, 'lng': 34.6861, 'elevation': 160.0, 'timezone': 'Asia/Jerusalem'},
  },
  'ארצות הברית': {
    'אטלנטה': {'lat': 33.7490, 'lng': -84.3880, 'elevation': 320.0, 'timezone': 'America/New_York'},
    'בוסטון': {'lat': 42.3601, 'lng': -71.0589, 'elevation': 43.0, 'timezone': 'America/New_York'},
    'בלטימור': {'lat': 39.2904, 'lng': -76.6122, 'elevation': 10.0, 'timezone': 'America/New_York'},
    'דטרויט': {'lat': 42.3314, 'lng': -83.0458, 'elevation': 183.0, 'timezone': 'America/Detroit'},
    'דנבר': {'lat': 39.7392, 'lng': -104.9903, 'elevation': 1609.0, 'timezone': 'America/Denver'},
    'לאס וגאס': {'lat': 36.1699, 'lng': -115.1398, 'elevation': 610.0, 'timezone': 'America/Los_Angeles'},
    'ליקווד': {'lat': 40.0878, 'lng': -74.2098, 'elevation': 20.0, 'timezone': 'America/New_York'},
    'לוס אנג\'לס': {'lat': 34.0522, 'lng': -118.2437, 'elevation': 71.0, 'timezone': 'America/Los_Angeles'},
    'מיאמי': {'lat': 25.7617, 'lng': -80.1918, 'elevation': 2.0, 'timezone': 'America/New_York'},
    'ניו יורק': {'lat': 40.7128, 'lng': -74.0060, 'elevation': 10.0, 'timezone': 'America/New_York'},
    'סיאטל': {'lat': 47.6062, 'lng': -122.3321, 'elevation': 56.0, 'timezone': 'America/Los_Angeles'},
    'סן פרנסיסקו': {'lat': 37.7749, 'lng': -122.4194, 'elevation': 16.0, 'timezone': 'America/Los_Angeles'},
    'פילדלפיה': {'lat': 39.9526, 'lng': -75.1652, 'elevation': 12.0, 'timezone': 'America/New_York'},
    'פיניקס': {'lat': 33.4484, 'lng': -112.0740, 'elevation': 331.0, 'timezone': 'America/Phoenix'},
    'קליבלנד': {'lat': 41.4993, 'lng': -81.6944, 'elevation': 199.0, 'timezone': 'America/New_York'},
    'שיקגו': {'lat': 41.8781, 'lng': -87.6298, 'elevation': 181.0, 'timezone': 'America/Chicago'},
  },
  'קנדה': {
    'אדמונטון': {'lat': 53.5461, 'lng': -113.4938, 'elevation': 645.0, 'timezone': 'America/Edmonton'},
    'אוטווה': {'lat': 45.4215, 'lng': -75.6972, 'elevation': 70.0, 'timezone': 'America/Toronto'},
    'ונקובר': {'lat': 49.2827, 'lng': -123.1207, 'elevation': 70.0, 'timezone': 'America/Vancouver'},
    'טורונטו': {'lat': 43.6532, 'lng': -79.3832, 'elevation': 76.0, 'timezone': 'America/Toronto'},
    'מונטריאול': {'lat': 45.5017, 'lng': -73.5673, 'elevation': 36.0, 'timezone': 'America/Toronto'},
    'קלגרי': {'lat': 51.0447, 'lng': -114.0719, 'elevation': 1048.0, 'timezone': 'America/Edmonton'},
  },
  'בריטניה': {
    'אדינבורו': {'lat': 55.9533, 'lng': -3.1883, 'elevation': 47.0, 'timezone': 'Europe/London'},
    'לונדון': {'lat': 51.5074, 'lng': -0.1278, 'elevation': 35.0, 'timezone': 'Europe/London'},
  },
  'צרפת': {
    'פריז': {'lat': 48.8566, 'lng': 2.3522, 'elevation': 35.0, 'timezone': 'Europe/Paris'},
  },
  'גרמניה': {
    'ברלין': {'lat': 52.5200, 'lng': 13.4050, 'elevation': 34.0, 'timezone': 'Europe/Berlin'},
  },
  'איטליה': {
    'מילאנו': {'lat': 45.4642, 'lng': 9.1900, 'elevation': 122.0, 'timezone': 'Europe/Rome'},
    'רומא': {'lat': 41.9028, 'lng': 12.4964, 'elevation': 21.0, 'timezone': 'Europe/Rome'},
  },
  'ספרד': {
    'מדריד': {'lat': 40.4168, 'lng': -3.7038, 'elevation': 650.0, 'timezone': 'Europe/Madrid'},
  },
  'הולנד': {
    'אמסטרדם': {'lat': 52.3676, 'lng': 4.9041, 'elevation': -2.0, 'timezone': 'Europe/Amsterdam'},
  },
  'שוויץ': {
    'ציריך': {'lat': 47.3769, 'lng': 8.5417, 'elevation': 408.0, 'timezone': 'Europe/Zurich'},
  },
  'אוסטריה': {
    'וינה': {'lat': 48.2082, 'lng': 16.3738, 'elevation': 171.0, 'timezone': 'Europe/Vienna'},
  },
  'הונגריה': {
    'בודפשט': {'lat': 47.4979, 'lng': 19.0402, 'elevation': 102.0, 'timezone': 'Europe/Budapest'},
  },
  'צ\'כיה': {
    'פראג': {'lat': 50.0755, 'lng': 14.4378, 'elevation': 200.0, 'timezone': 'Europe/Prague'},
  },
  'פולין': {
    'ורשה': {'lat': 52.2297, 'lng': 21.0122, 'elevation': 100.0, 'timezone': 'Europe/Warsaw'},
  },
  'רוסיה': {
    'מוסקבה': {'lat': 55.7558, 'lng': 37.6176, 'elevation': 156.0, 'timezone': 'Europe/Moscow'},
  },
  'טורקיה': {
    'איסטנבול': {'lat': 41.0082, 'lng': 28.9784, 'elevation': 39.0, 'timezone': 'Europe/Istanbul'},
  },
  'פורטוגל': {
    'ליסבון': {'lat': 38.7223, 'lng': -9.1393, 'elevation': 2.0, 'timezone': 'Europe/Lisbon'},
  },
  'אירלנד': {
    'דבלין': {'lat': 53.3498, 'lng': -6.2603, 'elevation': 85.0, 'timezone': 'Europe/Dublin'},
  },
  'שוודיה': {
    'סטוקהולם': {'lat': 59.3293, 'lng': 18.0686, 'elevation': 28.0, 'timezone': 'Europe/Stockholm'},
  },
  'דנמרק': {
    'קופנהגן': {'lat': 55.6761, 'lng': 12.5683, 'elevation': 24.0, 'timezone': 'Europe/Copenhagen'},
  },
  'פינלנד': {
    'הלסינקי': {'lat': 60.1699, 'lng': 24.9384, 'elevation': 26.0, 'timezone': 'Europe/Helsinki'},
  },
  'נורווגיה': {
    'אוסלו': {'lat': 59.9139, 'lng': 10.7522, 'elevation': 23.0, 'timezone': 'Europe/Oslo'},
  },
  'איסלנד': {
    'רייקיאוויק': {'lat': 64.1466, 'lng': -21.9426, 'elevation': 61.0, 'timezone': 'Atlantic/Reykjavik'},
  },
  'ארגנטינה': {
    'בואנוס איירס': {'lat': -34.6118, 'lng': -58.3960, 'elevation': 25.0, 'timezone': 'America/Argentina/Buenos_Aires'},
  },
  'ברזיל': {
    'ריו דה ז\'נרו': {'lat': -22.9068, 'lng': -43.1729, 'elevation': 2.0, 'timezone': 'America/Sao_Paulo'},
    'סאו פאולו': {'lat': -23.5505, 'lng': -46.6333, 'elevation': 760.0, 'timezone': 'America/Sao_Paulo'},
  },
  'צ\'ילה': {
    'סנטיאגו': {'lat': -33.4489, 'lng': -70.6693, 'elevation': 520.0, 'timezone': 'America/Santiago'},
  },
  'ונצואלה': {
    'קראקס': {'lat': 10.4806, 'lng': -66.9036, 'elevation': 900.0, 'timezone': 'America/Caracas'},
  },
  'פרו': {
    'לימה': {'lat': -12.0464, 'lng': -77.0428, 'elevation': 154.0, 'timezone': 'America/Lima'},
  },
  'מקסיקו': {
    'מקסיקו סיטי': {'lat': 19.4326, 'lng': -99.1332, 'elevation': 2240.0, 'timezone': 'America/Mexico_City'},
  },
  'מרוקו': {
    'קזבלנקה': {'lat': 33.5731, 'lng': -7.5898, 'elevation': 50.0, 'timezone': 'Africa/Casablanca'},
  },
  'דרום אפריקה': {
    'יוהנסבורג': {'lat': -26.2041, 'lng': 28.0473, 'elevation': 1753.0, 'timezone': 'Africa/Johannesburg'},
    'קייפטאון': {'lat': -33.9249, 'lng': 18.4241, 'elevation': 42.0, 'timezone': 'Africa/Johannesburg'},
  },
  'מצרים': {
    'אלכסנדריה': {'lat': 31.2001, 'lng': 29.9187, 'elevation': 12.0, 'timezone': 'Africa/Cairo'},
    'קהיר': {'lat': 30.0444, 'lng': 31.2357, 'elevation': 74.0, 'timezone': 'Africa/Cairo'},
  },
  'הודו': {
    'דלהי': {'lat': 28.7041, 'lng': 77.1025, 'elevation': 216.0, 'timezone': 'Asia/Kolkata'},
    'מומבאי': {'lat': 19.0760, 'lng': 72.8777, 'elevation': 14.0, 'timezone': 'Asia/Kolkata'},
  },
  'תאילנד': {
    'בנגקוק': {'lat': 13.7563, 'lng': 100.5018, 'elevation': 1.5, 'timezone': 'Asia/Bangkok'},
  },
  'סינגפור': {
    'סינגפור': {'lat': 1.3521, 'lng': 103.8198, 'elevation': 15.0, 'timezone': 'Asia/Singapore'},
  },
  'הונג קונג': {
    'הונג קונג': {'lat': 22.3193, 'lng': 114.1694, 'elevation': 552.0, 'timezone': 'Asia/Hong_Kong'},
  },
  'יפן': {
    'טוקיו': {'lat': 35.6762, 'lng': 139.6503, 'elevation': 40.0, 'timezone': 'Asia/Tokyo'},
  },
  'דרום קוריאה': {
    'סיאול': {'lat': 37.5665, 'lng': 126.9780, 'elevation': 38.0, 'timezone': 'Asia/Seoul'},
  },
  'סין': {
    'בייג\'ינג': {'lat': 39.9042, 'lng': 116.4074, 'elevation': 43.5, 'timezone': 'Asia/Shanghai'},
    'שנחאי': {'lat': 31.2304, 'lng': 121.4737, 'elevation': 4.0, 'timezone': 'Asia/Shanghai'},
  },
  'איחוד האמירויות': {
    'דובאי': {'lat': 25.2048, 'lng': 55.2708, 'elevation': 16.0, 'timezone': 'Asia/Dubai'},
  },
  'כווית': {
    'כווית': {'lat': 29.3759, 'lng': 47.9774, 'elevation': 55.0, 'timezone': 'Asia/Kuwait'},
  },
  'אוסטרליה': {
    'בריסביין': {'lat': -27.4698, 'lng': 153.0251, 'elevation': 27.0, 'timezone': 'Australia/Brisbane'},
    'מלבורן': {'lat': -37.8136, 'lng': 144.9631, 'elevation': 31.0, 'timezone': 'Australia/Melbourne'},
    'פרת': {'lat': -31.9505, 'lng': 115.8605, 'elevation': 46.0, 'timezone': 'Australia/Perth'},
    'סידני': {'lat': -33.8688, 'lng': 151.2093, 'elevation': 58.0, 'timezone': 'Australia/Sydney'},
  },
};

/// בודק אם עיר נמצאת בארץ ישראל
bool isCityInIsrael(String cityName) {
  return cityCoordinates['ארץ ישראל']!.containsKey(cityName);
}

/// מחזיר נתוני קואורדינטות של עיר לפי שם
Map<String, dynamic>? getCityData(String cityName) {
  for (var country in cityCoordinates.values) {
    if (country.containsKey(cityName)) {
      return country[cityName];
    }
  }
  return null;
}
