package gift.dhamma.uposatha;

/**
 * Pure text and calendar helpers of the home-screen widget: no Android classes, so the JVM unit test
 * (src/test) runs them as they are. The widget lays out what the page computed; these only turn
 * numbers into the strings of the design (design/README.md: "1 d 7 h", "Kala until 12:41 · 1 h 34 min left").
 */
final class WidgetFormat {
    static final long MIN = 60000L, HOUR = 3600000L, DAY = 86400000L;

    private WidgetFormat() {}

    /** "1 d 7 h" or, under a day, "20 h": whole days and hours, never minutes. */
    static String counter(long remMs, String unitD, String unitH) {
        if (remMs < 0) remMs = 0;
        long d = remMs / DAY, h = (remMs % DAY) / HOUR;
        return d > 0 ? d + " " + unitD + " " + h + " " + unitH : h + " " + unitH;
    }

    /** Time left as "1 h 34 min", "34 min" (an hour or less shows minutes only), at least "1 min" while anything is left. */
    static String left(long remMs, String unitH, String unitMin) {
        if (remMs < 0) remMs = 0;
        long totalMin = (remMs + MIN - 1) / MIN;   // rounded up: "0 min" is never shown while time is left
        if (totalMin < 1) totalMin = remMs > 0 ? 1 : 0;
        long h = totalMin / 60, m = totalMin % 60;
        return h > 0 ? h + " " + unitH + " " + (m < 10 ? "0" : "") + m + " " + unitMin : m + " " + unitMin;
    }

    /** "Kala until 12:41 · 1 h 34 min left" from the two templates of strings.json ({time}, {left}). */
    static String kalaLine(String kalaTpl, String leftTpl, String hm, long leftMs, String unitH, String unitMin) {
        String line = kalaTpl.replace("{time}", hm);
        return leftMs < 0 ? line : line + " · " + leftTpl.replace("{left}", left(leftMs, unitH, unitMin));
    }

    /** Milliseconds from now until counter(remMs) shows another text (the next whole-hour boundary of the remaining time). */
    static long untilCounterChanges(long remMs) {
        return remMs <= 0 ? Long.MAX_VALUE : (remMs % HOUR) + 1;
    }

    /** Day of week of a civil date, Monday = 0 … Sunday = 6. */
    static int dow(int y, int m, int d) {
        return (int) Math.floorMod(daysFromCivil(y, m, d) + 3, 7L);   // 1970-01-01 was a Thursday (3)
    }

    static int daysInMonth(int y, int m) {
        switch (m) {
            case 2: return (y % 4 == 0 && (y % 100 != 0 || y % 400 == 0)) ? 29 : 28;
            case 4: case 6: case 9: case 11: return 30;
            default: return 31;
        }
    }

    /** Days since 1970-01-01 (Howard Hinnant's civil-days algorithm). */
    static long daysFromCivil(int y, int m, int d) {
        y -= m <= 2 ? 1 : 0;
        long era = Math.floorDiv(y, 400);
        long yoe = y - era * 400;
        long doy = (153L * (m + (m > 2 ? -3 : 9)) + 2) / 5 + d - 1;
        long doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
        return era * 146097 + doe - 719468;
    }

    /** Civil date of a day count since 1970-01-01, as "YYYY-MM-DD". */
    static String ymdFromDays(long z) {
        z += 719468;
        long era = Math.floorDiv(z, 146097L);
        long doe = z - era * 146097;
        long yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
        long y = yoe + era * 400;
        long doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
        long mp = (5 * doy + 2) / 153;
        long d = doy - (153 * mp + 2) / 5 + 1;
        long m = mp + (mp < 10 ? 3 : -9);
        if (m <= 2) y++;
        return String.format(java.util.Locale.US, "%04d-%02d-%02d", y, m, d);
    }

    /** Whole days between two "YYYY-MM-DD" dates (b - a). */
    static long daysBetween(String a, String b) {
        return daysFromCivil(year(b), month(b), day(b)) - daysFromCivil(year(a), month(a), day(a));
    }

    static int year(String ymd) { return Integer.parseInt(ymd.substring(0, 4)); }
    static int month(String ymd) { return Integer.parseInt(ymd.substring(5, 7)); }
    static int day(String ymd) { return Integer.parseInt(ymd.substring(8, 10)); }

    /** "15:30" -> minutes of the day. */
    static int minutes(String hm) {
        return Integer.parseInt(hm.substring(0, 2)) * 60 + Integer.parseInt(hm.substring(3, 5));
    }

    /** "4 упосатхи" / "1 Uposatha": count with the right plural form. */
    static String uposathas(String lang, int n) {
        if (!"ru".equals(lang)) return n + (n == 1 ? " Uposatha" : " Uposathas");
        int a = n % 10, b = n % 100;
        String w = (a == 1 && b != 11) ? "упосатха" : (a >= 2 && a <= 4 && (b < 12 || b > 14)) ? "упосатхи" : "упосатх";
        return n + " " + w;
    }
}
