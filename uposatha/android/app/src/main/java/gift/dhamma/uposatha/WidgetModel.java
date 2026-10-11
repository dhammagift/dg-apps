package gift.dhamma.uposatha;

import org.json.JSONArray;
import org.json.JSONObject;

import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Calendar;
import java.util.List;
import java.util.Locale;
import java.util.TimeZone;

/**
 * What the page handed over (uposatha/widget/WIDGET.md), read once and placed against "now":
 * which Uposatha is current or next, kala or vikala, which part of the day. No moon, sun or Uposatha
 * maths here: every moment comes from the data; this only compares them with the clock.
 * parse() returns null when there is nothing safe to show (no data, older than 30 days, today not covered).
 */
final class WidgetModel {
    static final long STALE_MS = 30L * WidgetFormat.DAY;   // the page gives 31 days of sun and 30 of the moon's percent
    static final int NONE = 0, KALA = 1, VIKALA = 2;

    static final class Mo {
        final long ms; final String ymd, hm;
        Mo(JSONObject o) { ms = o.optLong("ms"); ymd = o.optString("ymd"); hm = o.optString("hm"); }
    }

    static final class Day {
        String date; Mo sunrise, noon, sunset, aruna;
        final String[] partName = new String[6];
        final String[] partFrom = new String[6], partTo = new String[6];
        final long[] partStart = new long[6], partEnd = new long[6];
    }

    static final class Upo {
        Mo start, end; String day, phaseName; int lunarDay; double phase;
        /** The moon of a LIST row: the plain phase of that day (new, 50 %, full; the 14th a crescent or a gibbous), not the exact fraction. */
        double nominal() {
            boolean wax = phase > 0 && phase < 0.5;
            if (lunarDay == 8) return "firstQuarter".equals(phaseName) ? 0.25 : "lastQuarter".equals(phaseName) ? 0.75 : (wax ? 0.25 : 0.75);
            if (lunarDay == 14) return wax ? 0.375 : 0.875;
            if (lunarDay == 15) return "full".equals(phaseName) ? 0.5 : "new".equals(phaseName) ? 0.0 : (wax ? 0.5 : 0.0);
            return phase;
        }
    }

    final long now;
    final TimeZone tz;
    final String lang;
    final boolean bySuttas, detail, showKala, placeSet, south, allMoons;
    final boolean tzAuto;                     // the page follows the phone's time zone (none was chosen there)
    final double moonNow;                     // the real phase of the moon now (0 new .. 0.5 full): between two middays of the page's table, else carried on from when the data was made
    final int weekStart;                      // 0: the week starts on Sunday, 1: on Monday (the app's own setting)
    final String today;                       // YYYY-MM-DD in the place's zone
    final List<Day> days = new ArrayList<>();
    final List<Upo> upos = new ArrayList<>();
    private String moonsFrom;                 // the moon of every day at midday, from this date (the page's own numbers)
    private double[] moons;
    final double litNow;                      // the lit percent of the moon now, as the page shows it (its own table, read between two points)

    int curIdx = -1;                          // the Uposatha running now, else the next one
    boolean ongoing;
    int kala = NONE;                          // kala / vikala now
    long kalaEndMs;
    String kalaEndHm = "";
    int dayIdx = -1;                          // the day (aruna .. next aruna) containing now
    int partDay = -1, partIdx = -1;           // the part of the day containing now (-1: not known)

    private WidgetModel(JSONObject root, long now) throws Exception {
        this.now = now;
        JSONObject st = root.optJSONObject("settings");
        if (st == null) st = new JSONObject();
        lang = "ru".equals(st.optString("lang")) ? "ru" : "en";
        bySuttas = st.optBoolean("bySuttas", true);
        detail = st.optBoolean("detail", false);
        showKala = st.optBoolean("showKala", true);
        placeSet = st.optBoolean("placeSet", true);
        south = st.optBoolean("south", false);
        allMoons = st.optBoolean("allMoons", false);
        tzAuto = st.optBoolean("tzAuto", false);
        weekStart = st.optInt("weekStart", "ru".equals(st.optString("lang")) ? 1 : 0) == 0 ? 0 : 1;
        long gen0 = parseIso(root.optString("generatedAt", ""));
        JSONObject td = root.optJSONObject("today");
        double mf = td == null ? 0 : td.optDouble("moon", 0);
        if (Double.isNaN(mf)) mf = 0;
        double mn = ((mf + (gen0 > 0 ? (now - gen0) / (29.530588853 * 86400000.0) : 0)) % 1 + 1) % 1;   // the moon moves about 0.034 of a cycle a day
        String tzid = root.optString("tz", "");
        TimeZone z = tzid.isEmpty() ? TimeZone.getDefault() : TimeZone.getTimeZone(tzid);
        tz = z;
        SimpleDateFormat f = new SimpleDateFormat("yyyy-MM-dd", Locale.US);
        f.setTimeZone(tz);
        today = f.format(now);

        JSONArray da = root.getJSONArray("days");
        for (int i = 0; i < da.length(); i++) {
            JSONObject o = da.getJSONObject(i);
            Day d = new Day();
            d.date = o.getString("date");
            d.sunrise = new Mo(o.getJSONObject("sunrise"));
            d.noon = new Mo(o.getJSONObject("noon"));
            d.sunset = new Mo(o.getJSONObject("sunset"));
            d.aruna = o.has("aruna") ? new Mo(o.getJSONObject("aruna")) : d.sunrise;
            JSONArray ps = o.getJSONArray("parts");
            if (ps.length() < 6) throw new IllegalArgumentException("parts");
            int dayOff = 0, lastMin = -1;
            for (int k = 0; k < 6; k++) {
                JSONArray p = ps.getJSONArray(k);
                d.partName[k] = p.getString(0);
                d.partFrom[k] = p.getString(1);
                d.partTo[k] = p.getString(2);
                // The page gives clock times; a part that wraps past midnight has a smaller time than the one before.
                int a = WidgetFormat.minutes(d.partFrom[k]), b = WidgetFormat.minutes(d.partTo[k]);
                if (lastMin >= 0 && a < lastMin) dayOff++;
                d.partStart[k] = at(d.date, dayOff, a);
                if (b < a) dayOff++;
                d.partEnd[k] = at(d.date, dayOff, b);
                lastMin = b;
            }
            days.add(d);
        }
        JSONArray ua = root.getJSONArray("uposathas");
        for (int i = 0; i < ua.length(); i++) {
            JSONObject o = ua.getJSONObject(i);
            Upo u = new Upo();
            u.start = new Mo(o.getJSONObject("start"));
            u.end = new Mo(o.getJSONObject("end"));
            u.day = o.getString("day");
            u.lunarDay = o.optInt("lunarDay");
            u.phaseName = o.optString("phaseName", "new");
            u.phase = o.optDouble("phase", 0);
            upos.add(u);
        }
        JSONObject mo = root.optJSONObject("moons");
        JSONArray mp = mo == null ? null : mo.optJSONArray("phase");
        if (mp != null && mo.optString("from", "").length() == 10) {
            moonsFrom = mo.optString("from");
            moons = new double[mp.length()];
            for (int i = 0; i < moons.length; i++) moons[i] = mp.optDouble(i, 0);
        }
        // The phase now: between the two middays around now. The mean speed alone is half a day off after two weeks (the moon's orbit
        // is not a circle), and a widget lives a month on one set of data.
        if (moons != null) {
            int j = (int) WidgetFormat.daysBetween(moonsFrom, today);
            if (now < at(today, 0, 720)) j--;
            if (j >= 0 && j + 1 < moons.length) {
                long t0 = at(moonsFrom, j, 720), t1 = at(moonsFrom, j + 1, 720);
                mn = WidgetPlan.phaseBetween(moons[j], moons[j + 1], (now - t0) / (double) (t1 - t0));
            }
        }
        moonNow = mn;
        // The lit percent now: between two points of the page's table; with no table (older data) or past its end, the cosine of the phase.
        double lit = (1 - Math.cos(2 * Math.PI * moonNow)) / 2 * 100;
        JSONObject lt = mo == null ? null : mo.optJSONObject("lit");
        JSONArray lp = lt == null ? null : lt.optJSONArray("pct");
        long step = lt == null ? 0 : lt.optLong("step", 0);
        if (lp != null && step > 0) {
            double x = (now - lt.optLong("from", 0)) / (double) step;
            int i = (int) Math.floor(x);
            if (i >= 0 && i + 1 < lp.length()) lit = lp.optDouble(i, lit) + (lp.optDouble(i + 1, lit) - lp.optDouble(i, lit)) * (x - i);
        }
        litNow = lit;
    }

    /**
     * The moon of a day (its phase at midday, 0..1): the page's own number when it sent one (settings.allMoons data), else today's moon
     * carried to that date at the mean speed of the moon (a few percent off at most, on a picture of a dozen dp).
     */
    double phaseOn(String ymd) {
        if (moons != null) {
            long i = WidgetFormat.daysBetween(moonsFrom, ymd);
            if (i >= 0 && i < moons.length) return moons[(int) i];
        }
        double days = WidgetFormat.daysBetween(today, ymd) + 0.5 - ((now + tz.getOffset(now)) % WidgetFormat.DAY) / (double) WidgetFormat.DAY;
        return ((moonNow + days / 29.530588853) % 1 + 1) % 1;
    }

    /** The place's wall-clock date (YYYY-MM-DD) + dayOff days at minutes-of-day, as epoch ms. */
    private long at(String ymd, int dayOff, int min) {
        Calendar c = Calendar.getInstance(tz, Locale.US);
        c.clear();
        c.set(WidgetFormat.year(ymd), WidgetFormat.month(ymd) - 1, WidgetFormat.day(ymd) + dayOff, min / 60, min % 60, 0);
        return c.getTimeInMillis();
    }

    static long parseIso(String s) {
        String[] fmts = { "yyyy-MM-dd'T'HH:mm:ss.SSSXXX", "yyyy-MM-dd'T'HH:mm:ssXXX", "yyyy-MM-dd'T'HH:mm:ss.SSSX", "yyyy-MM-dd'T'HH:mm:ssX" };
        for (String f : fmts) {
            try {
                SimpleDateFormat p = new SimpleDateFormat(f, Locale.US);
                return p.parse(s).getTime();
            } catch (Exception e) { /* next format */ }
        }
        return 0;
    }

    /** Null when the widget must show the placeholder instead (no data, too old, today not covered). */
    static WidgetModel parse(JSONObject root, long now) {
        if (root == null) return null;
        try {
            long gen = parseIso(root.optString("generatedAt", ""));
            if (gen > 0 && now - gen > STALE_MS) return null;
            WidgetModel m = new WidgetModel(root, now);
            // The page followed the phone's zone and the phone is in another one now (a flight): the dawn, the midday and "today" are
            // the old place's. Nothing true to show until the app is opened there.
            if (m.tzAuto && TimeZone.getDefault().getOffset(now) != m.tz.getOffset(now)) return null;
            return m.place() ? m : null;
        } catch (Exception e) {
            return null;
        }
    }

    private boolean place() {
        if (days.isEmpty() || upos.isEmpty()) return false;
        for (int i = 0; i < upos.size(); i++) {
            if (upos.get(i).end.ms > now) { curIdx = i; break; }
        }
        if (curIdx < 0) return false;
        ongoing = upos.get(curIdx).start.ms <= now;

        int n = days.size();
        for (int i = 0; i < n; i++) {
            long from = days.get(i).aruna.ms;
            long to = i + 1 < n ? days.get(i + 1).aruna.ms : days.get(i).partEnd[5];
            if (now >= from && now < to) { dayIdx = i; break; }
        }
        if (dayIdx < 0) {
            // Just after midnight, with data made after midnight too: the first day has not begun, and it is vikala till its aruna.
            Day d0 = days.get(0);
            if (now < d0.aruna.ms && today.equals(d0.date)) {
                kala = VIKALA; kalaEndMs = d0.aruna.ms; kalaEndHm = d0.aruna.hm;
                return true;
            }
            return false;
        }
        Day d = days.get(dayIdx);
        if (now < d.noon.ms) {
            kala = KALA; kalaEndMs = d.noon.ms; kalaEndHm = d.noon.hm;
        } else {
            kala = VIKALA;
            if (dayIdx + 1 < n) { kalaEndMs = days.get(dayIdx + 1).aruna.ms; kalaEndHm = days.get(dayIdx + 1).aruna.hm; }
            else { kalaEndMs = d.partEnd[5]; kalaEndHm = d.partTo[5]; }
        }
        for (int i = Math.max(0, dayIdx - 1); i <= dayIdx && partIdx < 0; i++) {
            Day x = days.get(i);
            for (int k = 0; k < 6; k++) {
                if (now >= x.partStart[k] && now < x.partEnd[k]) { partDay = i; partIdx = k; break; }
            }
        }
        return true;
    }

    Upo cur() { return upos.get(curIdx); }

    /** The moment the big counter runs to: the start of the next Uposatha, or the end of the one that is on. */
    long counterTarget() { return ongoing ? cur().end.ms : cur().start.ms; }

    /** The next Uposathas after the current one (up to n). */
    List<Upo> following(int n) {
        List<Upo> r = new ArrayList<>();
        for (int i = curIdx + 1; i < upos.size() && r.size() < n; i++) r.add(upos.get(i));
        return r;
    }

    /** The Uposatha whose day is the given date, or null. */
    Upo uposathaOn(String ymd) {
        for (Upo u : upos) if (u.day.equals(ymd)) return u;
        return null;
    }

    /** The Uposatha whose evening-before start cell is the given date (start date differs from its day), or null. */
    Upo startingOn(String ymd) {
        for (Upo u : upos) if (u.start.ymd.equals(ymd) && !u.start.ymd.equals(u.day)) return u;
        return null;
    }

    /** Earliest moment after now when the picture can change by itself (events of the day, Uposatha edges, part borders). */
    long nextEvent() {
        long best = Long.MAX_VALUE;
        for (Day d : days) {
            long[] c = { d.aruna.ms, d.sunrise.ms, d.noon.ms, d.sunset.ms };
            for (long v : c) if (v > now && v < best) best = v;
            for (int k = 0; k < 6; k++) {
                if (d.partStart[k] > now && d.partStart[k] < best) best = d.partStart[k];
                if (d.partEnd[k] > now && d.partEnd[k] < best) best = d.partEnd[k];
            }
        }
        for (Upo u : upos) {
            if (u.start.ms > now && u.start.ms < best) best = u.start.ms;
            if (u.end.ms > now && u.end.ms < best) best = u.end.ms;
        }
        return best;
    }

    /** Month grid of the given date: first column offset (Monday = 0), length, rows (4..6). */
    /** The month of a date: year, month, column of the 1st (0 = the first day of the week), days, rows. weekStart: 0 Sunday, 1 Monday. */
    static int[] month(String ymd, int weekStart) {
        int y = WidgetFormat.year(ymd), m = WidgetFormat.month(ymd);
        int off = column(WidgetFormat.dow(y, m, 1), weekStart), dim = WidgetFormat.daysInMonth(y, m);
        return new int[] { y, m, off, dim, (off + dim + 6) / 7 };
    }

    /** The column of a weekday (WidgetFormat.dow: Monday 0 .. Sunday 6) in a week that starts on Sunday (0) or Monday (1). */
    static int column(int dow, int weekStart) {
        return weekStart == 0 ? (dow + 1) % 7 : dow;
    }

    static String ymd(int y, int m, int d) {
        return String.format(Locale.US, "%04d-%02d-%02d", y, m, d);
    }
}
