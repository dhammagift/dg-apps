package gift.dhamma.uposatha;

import android.content.Context;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.ByteArrayOutputStream;
import java.io.InputStream;

/** The widget's texts (res/raw/widget_strings.json, the designer's strings.json as it is) for one language. */
final class WidgetText {
    private static JSONObject all;
    private final JSONObject t;
    final String lang;

    WidgetText(Context ctx, String lang) {
        this.lang = "ru".equals(lang) ? "ru" : "en";
        JSONObject root = load(ctx);
        JSONObject l = root.optJSONObject(this.lang);
        this.t = l != null ? l : new JSONObject();
    }

    private static synchronized JSONObject load(Context ctx) {
        if (all != null) return all;
        try (InputStream in = ctx.getResources().openRawResource(R.raw.widget_strings)) {
            ByteArrayOutputStream out = new ByteArrayOutputStream();
            byte[] buf = new byte[4096];
            int n;
            while ((n = in.read(buf)) > 0) out.write(buf, 0, n);
            all = new JSONObject(out.toString("UTF-8"));
        } catch (Exception e) {
            all = new JSONObject();   // texts come out as their keys: visible, not a crash
        }
        return all;
    }

    String get(String key) { return t.optString(key, key); }

    /** A template with {name} slots: fmt("detail.span", "startDay", "сб 10", ...). */
    String fmt(String key, Object... kv) {
        String s = get(key);
        for (int i = 0; i + 1 < kv.length; i += 2) s = s.replace("{" + kv[i] + "}", String.valueOf(kv[i + 1]));
        return s;
    }

    String weekday(int dow) {
        JSONArray a = t.optJSONArray("weekdays");
        return a != null ? a.optString(dow, "") : "";
    }

    boolean ru() { return "ru".equals(lang); }

    /** Phone-wide short month ("окт" / "Oct"), 1..12. */
    String monthShort(int m) {
        return ru() ? RU_SHORT[m - 1] : EN_SHORT[m - 1];
    }

    /** Month name, nominative ("Октябрь" / "October"). */
    String monthName(int m) {
        return ru() ? RU_NAME[m - 1] : EN_NAME[m - 1];
    }

    String unitMin() { return ru() ? "мин" : "min"; }

    private static final String[] RU_SHORT = { "янв", "фев", "мар", "апр", "мая", "июн", "июл", "авг", "сен", "окт", "ноя", "дек" };
    private static final String[] EN_SHORT = { "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" };
    private static final String[] RU_NAME = { "Январь", "Февраль", "Март", "Апрель", "Май", "Июнь", "Июль", "Август", "Сентябрь", "Октябрь", "Ноябрь", "Декабрь" };
    private static final String[] EN_NAME = { "January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December" };
}
