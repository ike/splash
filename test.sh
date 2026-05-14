#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(dirname "$(realpath "$0")")"

# ── Minimal water JSON ─────────────────────────────────────────────────────────
cat > /tmp/water_cold.json << 'EOF'
{ "pasco": { "temperature": 44, "oxygen": 11.2 } }
EOF

cat > /tmp/water_warm.json << 'EOF'
{ "pasco": { "temperature": 68, "oxygen": 9.1 } }
EOF

cat > /tmp/water_frigid.json << 'EOF'
{ "pasco": { "temperature": 38, "oxygen": 12.5 } }
EOF

cat > /tmp/water_null.json << 'EOF'
{ "pasco": { "temperature": null, "oxygen": null } }
EOF

# ── Helper: generate hourly entries ───────────────────────────────────────────
# Args: date, start_hour, end_hour, wind_ms, wind_dir, temp_c, feels_c, precip, humidity, uvindex
# Outputs a JSON array fragment (one object per hour) to a temp accumulator file
gen_hours() {
  local date="$1" sh="$2" eh="$3" wms="$4" wdir="$5" tc="$6" fc="$7" pr="$8" hum="$9" uv="${10}"
  local tf fc_f wmp
  tf=$(echo "$tc"  | awk '{printf "%d", $1 * 9/5 + 32}')
  fc_f=$(echo "$fc" | awk '{printf "%d", $1 * 9/5 + 32}')
  wmp=$(echo "$wms" | awk '{printf "%d", $1 * 2.23694}')

  for h in $(seq "$sh" "$eh"); do
    local hh
    hh=$(printf "%02d" "$h")
    jq -n \
      --arg  time  "${date} ${hh}:00" \
      --argjson wms  "$wms" \
      --argjson wmp  "$wmp" \
      --argjson wdir "$wdir" \
      --argjson tc   "$tc" \
      --argjson tf   "$tf" \
      --argjson fc   "$fc" \
      --argjson fc_f "$fc_f" \
      --argjson pr   "$pr" \
      --argjson hum  "$hum" \
      --argjson uv   "$uv" \
      '{
        time: $time,
        wind: { speed_ms: $wms, speed_mph: $wmp, direction_degrees: $wdir },
        temperature: { actual_c: $tc, actual_f: $tf, feels_like_c: $fc, feels_like_f: $fc_f },
        precipitation_mm: $pr,
        relative_humidity: $hum,
        uvindex: $uv
      }'
  done
}

TODAY=$(date +%Y-%m-%d)
TOMORROW=$(date -d "+1 day" +%Y-%m-%d 2>/dev/null || date -v +1d +%Y-%m-%d)
DAY3=$(date -d "+2 days" +%Y-%m-%d 2>/dev/null || date -v +2d +%Y-%m-%d)

# Accumulator file for hourly objects (one JSON object per line)
HOURLY_TMP=$(mktemp)

reset_hourly() { > "$HOURLY_TMP"; }

add_hours() {
  gen_hours "$@" >> "$HOURLY_TMP"
}

make_weather() {
  local file="$1"
  local avg_ms="$2" peak_ms="$3" wind_dir="$4"
  local fl_avg_f="$5" low_c="$6" low_f="$7" high_c="$8" high_f="$9"

  jq -n \
    --argjson avg_ms   "$avg_ms" \
    --argjson peak_ms  "$peak_ms" \
    --argjson wind_dir "$wind_dir" \
    --argjson fl_avg_f "$fl_avg_f" \
    --argjson low_c    "$low_c" \
    --argjson low_f    "$low_f" \
    --argjson high_c   "$high_c" \
    --argjson high_f   "$high_f" \
    --slurpfile hourly "$HOURLY_TMP" \
    '{
      today: {
        wind: { average_ms: $avg_ms, peak_ms: $peak_ms },
        temperature: {
          feels_like_avg_f: $fl_avg_f,
          low_c: $low_c, low_f: $low_f,
          high_c: $high_c, high_f: $high_f
        },
        wind_direction_degrees: $wind_dir
      },
      hourly: $hourly
    }' > "$file"
}

# ── Scenario 1: Perfect sailing day (S wind 10 kts, warm, no rain) ────────────
reset_hourly
add_hours "$TODAY"    0  7  2  180  15  13  0    40  0
add_hours "$TODAY"    8  17 5  180  28  27  0    35  8
add_hours "$TODAY"    18 23 3  180  22  20  0    40  3
add_hours "$TOMORROW" 0  23 5  160  25  24  0    38  6
add_hours "$DAY3"     0  23 6  200  26  25  0.5  50  5
make_weather /tmp/weather_sail_good.json 4.8 7.2 180 82 15 59 28 82

# ── Scenario 2: Too windy, freezing morning (bad bike, bad sail) ───────────────
reset_hourly
add_hours "$TODAY"    0  5  15  270  -5  -8   0    55  0
add_hours "$TODAY"    6  12 18  270  -2  -6   0    50  2
add_hours "$TODAY"    13 17 20  260  2   -1   0    45  4
add_hours "$TODAY"    18 23 16  250  0   -3   0    50  0
add_hours "$TOMORROW" 0  23 8   180  18  16   0    40  6
make_weather /tmp/weather_windy_cold.json 17.5 22.0 265 28 -5 23 2 36

# ── Scenario 3: Calm but freezing (no bike due to freeze, no sail due to wind) ─
reset_hourly
add_hours "$TODAY"    0  23 1  90  -10  -14  0  60  0
add_hours "$TOMORROW" 0  23 2  90  -5   -9   0  55  1
make_weather /tmp/weather_calm_freeze.json 1.0 2.0 90 14 -10 14 -5 23

# ── Scenario 4: Heavy rain, all UV levels in one day ──────────────────────────
reset_hourly
add_hours "$TODAY"  0  1  3  180  20  19  5.2  90  0
add_hours "$TODAY"  2  3  3  180  20  19  3.1  88  1
add_hours "$TODAY"  4  5  3  180  20  19  2.0  85  2
add_hours "$TODAY"  6  7  3  180  20  19  0.5  80  3
add_hours "$TODAY"  8  9  4  180  22  21  0    75  4
add_hours "$TODAY"  10 11 5  180  24  23  0    70  6
add_hours "$TODAY"  12 13 5  180  25  24  0    65  8
add_hours "$TODAY"  14 15 5  180  25  24  0    65  10
add_hours "$TODAY"  16 17 4  180  23  22  1.0  72  12
add_hours "$TODAY"  18 23 3  180  21  20  4.5  85  0
add_hours "$TOMORROW" 0 23 5  180  22  21  0    60  5
make_weather /tmp/weather_rain_uv.json 3.8 5.5 180 68 20 68 25 77

# ── Scenario 5: All temperature classes in sequence ──────────────────────────
reset_hourly
add_hours "$TODAY"    0  3  3  180  -5   -8   0  50  0   # verycold
add_hours "$TODAY"    4  7  3  180  5    3    0  50  1   # cold
add_hours "$TODAY"    8  11 3  180  14   12   0  50  3   # cool
add_hours "$TODAY"    12 14 3  180  21   20   0  50  5   # mild
add_hours "$TODAY"    15 17 3  180  26   25   0  50  7   # warm
add_hours "$TODAY"    18 20 3  180  32   31   0  50  9   # hot
add_hours "$TODAY"    21 23 3  180  37   36   0  50  11  # veryhot
add_hours "$TOMORROW" 0  23 4  180  20   19   0  45  4
make_weather /tmp/weather_all_temps.json 3.0 4.0 180 66 -5 23 37 99

# ── Scenario 6: All wind speed classes, varying direction ─────────────────────
reset_hourly
add_hours "$TODAY"    0  3  0.5  180  20  19  0  50  3   # calm
add_hours "$TODAY"    4  6  3.5  180  20  19  0  50  3   # light
add_hours "$TODAY"    7  9  7.5  90   20  19  0  50  4   # moderate
add_hours "$TODAY"    10 12 10.5 270  20  19  0  50  5   # fresh
add_hours "$TODAY"    13 15 14.0 45   20  19  0  50  6   # strong
add_hours "$TODAY"    16 18 17.0 0    20  19  0  50  4   # gale
add_hours "$TODAY"    19 23 5.0  135  20  19  0  50  2   # back to good dir
add_hours "$TOMORROW" 0  23 6.0  180  22  21  0  48  5
make_weather /tmp/weather_all_winds.json 8.2 17.0 180 68 19 66 22 72

# ── Scenario 7: Sail possible tomorrow but not today ──────────────────────────
reset_hourly
add_hours "$TODAY"    0  23 1.5  180  20  19  0  50  4
add_hours "$TOMORROW" 8  16 6.0  180  25  24  0  45  7
add_hours "$TOMORROW" 0  7  1.5  180  18  17  0  55  1
add_hours "$TOMORROW" 17 23 2.0  180  22  21  0  50  3
make_weather /tmp/weather_sail_tomorrow.json 1.5 2.0 180 68 19 66 25 77

rm -f "$HOURLY_TMP"

# ── Generate HTML files ────────────────────────────────────────────────────────

echo "=== Scenario 1: Good Sailing Day ==="
bash "$SCRIPT_DIR/generate_html.sh" /tmp/weather_sail_good.json    /tmp/water_warm.json    /tmp/test_sail_good.html

echo "=== Scenario 2: Windy & Cold ==="
bash "$SCRIPT_DIR/generate_html.sh" /tmp/weather_windy_cold.json   /tmp/water_frigid.json  /tmp/test_windy_cold.html

echo "=== Scenario 3: Calm & Freezing ==="
bash "$SCRIPT_DIR/generate_html.sh" /tmp/weather_calm_freeze.json  /tmp/water_frigid.json  /tmp/test_calm_freeze.html

echo "=== Scenario 4: Rain + All UV Levels ==="
bash "$SCRIPT_DIR/generate_html.sh" /tmp/weather_rain_uv.json      /tmp/water_cold.json    /tmp/test_rain_uv.html

echo "=== Scenario 5: All Temperature Classes ==="
bash "$SCRIPT_DIR/generate_html.sh" /tmp/weather_all_temps.json    /tmp/water_warm.json    /tmp/test_all_temps.html

echo "=== Scenario 6: All Wind Speed Classes ==="
bash "$SCRIPT_DIR/generate_html.sh" /tmp/weather_all_winds.json    /tmp/water_warm.json    /tmp/test_all_winds.html

echo "=== Scenario 7: Sail Tomorrow (cold water warning) ==="
bash "$SCRIPT_DIR/generate_html.sh" /tmp/weather_sail_tomorrow.json /tmp/water_cold.json   /tmp/test_sail_tomorrow.html

echo "=== Scenario 8: Sail good wind but frigid water ==="
bash "$SCRIPT_DIR/generate_html.sh" /tmp/weather_sail_good.json    /tmp/water_frigid.json  /tmp/test_sail_frigid_water.html

echo "=== Scenario 9: Null water temp ==="
bash "$SCRIPT_DIR/generate_html.sh" /tmp/weather_all_temps.json    /tmp/water_null.json    /tmp/test_null_water.html

echo ""
echo "Done! Test files written to /tmp/test_*.html"
ls -lh /tmp/test_*.html
