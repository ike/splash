#!/usr/bin/env bash
# generate_weather.sh
# Usage: ./generate_weather.sh [weather.json] [output.html]
set -euo pipefail

WEATHER_JSON="${1:-weather.json}"
WATER_JSON="${2:-water.json}"
OUTPUT_HTML="${3:-index.html}"

if ! command -v jq &>/dev/null; then
  echo "Error: jq is required." >&2; exit 1
fi
if [[ ! -f "$WEATHER_JSON" ]]; then
  echo "Error: '$WEATHER_JSON' not found." >&2; exit 1
fi
if ! jq empty "$WEATHER_JSON" 2>/dev/null; then
  echo "Error: invalid JSON in '$WEATHER_JSON'." >&2; exit 1
fi
if [[ ! -f "$WATER_JSON" ]]; then
  PASCO_WATER_TEMP="n/a"
fi
if [[ -f "$WATER_JSON" ]]; then
  if ! jq empty "$WATER_JSON" 2>/dev/null; then
    PASCO_WATER_TEMP="n/a"
  fi
fi

# ── helpers ────────────────────────────────────────────────────────────────────

fmt() {
  local v="$1"
  if [[ -z "$v" || "$v" == "null" ]]; then echo "—"; else echo "$v"; fi
}

ms_to_kts() {
  local ms="$1"
  if [[ -z "$ms" || "$ms" == "null" ]]; then echo "null"; return; fi
  echo "$ms" | awk '{printf "%.1f", $1 * 1.94384}'
}

get_temp_class() {
  local c="$1"
  if [[ -z "$c" || "$c" == "null" ]]; then echo ""; return; fi
  echo "$c" | awk '{
    if ($1 < 0)        print "temp-verycold"
    else if ($1 < 10)  print "temp-cold"
    else if ($1 < 18)  print "temp-cool"
    else if ($1 < 24)  print "temp-mild"
    else if ($1 < 30)  print "temp-warm"
    else if ($1 < 35)  print "temp-hot"
    else               print "temp-veryhot"
  }'
}

get_wind_speed_class() {
  local kts="$1"
  if [[ -z "$kts" || "$kts" == "null" ]]; then echo ""; return; fi
  echo "$kts" | awk '{
    if ($1 < 6)        print "wind-speed-calm"
    else if ($1 < 12)  print "wind-speed-light"
    else if ($1 < 17)  print "wind-speed-moderate"
    else if ($1 < 23)  print "wind-speed-fresh"
    else if ($1 < 31)  print "wind-speed-strong"
    else               print "wind-speed-gale"
  }'
}

get_wind_dir_class() {
  local deg="$1"
  if [[ -z "$deg" || "$deg" == "null" ]]; then echo ""; return; fi
  echo "$deg" | awk '{
    if ($1 >= 135 && $1 <= 225)     print "wind-dir-good"
    else if ($1 >= 90 && $1 <= 270) print "wind-dir-mid"
    else                             print "wind-dir-bad"
  }'
}

get_humidity_class() {
  local h="$1"
  if [[ -z "$h" || "$h" == "null" ]]; then echo ""; return; fi
  echo "$h" | awk '{
    b = int(($1 + 5) / 10) * 10
    if (b > 100) b = 100
    if (b < 0)   b = 0
    print "humidity-" b
  }'
}

get_precip_class() {
  local mm="$1"
  if [[ -z "$mm" || "$mm" == "null" || "$mm" == "0" || "$mm" == "0.0" ]]; then echo ""; return; fi
  echo "precip"
}

format_time() {
  local iso="$1"
  # Normalize space separator to T
  iso="${iso/ /T}"
  local date_part="${iso%%T*}"
  local time_part="${iso##*T}"
  time_part="${time_part:0:5}"
  local label
  if [[ "$date_part" == "$TODAY" ]]; then
    label="Today"
  elif [[ "$date_part" == "$TOMORROW" ]]; then
    label="Tomorrow"
 else
    label=$(date -j -f "%Y-%m-%d" "$date_part" +"%A" 2>/dev/null || date -d "$date_part" +"%A")
  fi
  echo "${label}, ${time_part}"
}

build_range_labels() {
  local hours_json="$1"
  echo "$hours_json" | jq -r '
    if length == 0 then ""
    else
      . as $hours |
      reduce range(1; length) as $i (
        [[ $hours[0], $hours[0] ]];
        if $hours[$i] == (last | .[1]) + 1
        then .[:-1] + [[ last[0], $hours[$i] ]]
        else . + [[ $hours[$i], $hours[$i] ]]
        end
      )
      | map(
          .[0] as $s | (.[1] + 1) as $e |
          ($s % 12 | if . == 0 then 12 else . end) as $s12 |
          ($e % 12 | if . == 0 then 12 else . end) as $e12 |
          (if $s >= 12 then "pm" else "am" end) as $sam |
          (if $e >= 12 then "pm" else "am" end) as $eam |
          if $s == (.[1])
          then "\($s12)\($sam)"
          elif $sam == $eam
          then "\($s12)-\($e12)\($eam)"
          else "\($s12)\($sam)-\($e12)\($eam)"
          end
        )
      | join(", ")
    end
  '
}

# ── dates ──────────────────────────────────────────────────────────────────────

TODAY=$(date +%Y-%m-%d)
TOMORROW=$(date -d "+1 day" +%Y-%m-%d 2>/dev/null || date -v +1d +%Y-%m-%d)
DATE_STRING=$(date +"%A %B %e, %Y")

# ── summary values ─────────────────────────────────────────────────────────────

AVG_MS=$(jq -r '.today.wind.average_ms // "null"' "$WEATHER_JSON")
PEAK_MS=$(jq -r '.today.wind.peak_ms // "null"' "$WEATHER_JSON")
WIND_DIR=$(jq -r '.today.wind_direction_degrees // "null"' "$WEATHER_JSON")
FEELS_AVG_F=$(jq -r '.today.temperature.feels_like_avg_f // "null"' "$WEATHER_JSON")
LOW_C=$(jq -r '.today.temperature.low_c // "null"' "$WEATHER_JSON")
LOW_F=$(jq -r '.today.temperature.low_f // "null"' "$WEATHER_JSON")
HIGH_C=$(jq -r '.today.temperature.high_c // "null"' "$WEATHER_JSON")
HIGH_F=$(jq -r '.today.temperature.high_f // "null"' "$WEATHER_JSON")

AVG_KTS=$(ms_to_kts "$AVG_MS")
PEAK_KTS=$(ms_to_kts "$PEAK_MS")

PASCO_WATER_TEMP=$(jq -r '.pasco.temperature // "null"' "$WATER_JSON")

# ── bike callout ───────────────────────────────────────────────────────────────

WIND_OK=false
echo "$AVG_KTS" | awk '{exit ($1 < 6) ? 0 : 1}' && WIND_OK=true || true

FREEZE_OK=$(jq --arg today "$TODAY" '
  [ .hourly[]
    | select(.time | startswith($today))
    | select((.time | gsub(" "; "T") | split("T")[1] | split(":")[0] | tonumber) >= 8)
    | select((.time | gsub(" "; "T") | split("T")[1] | split(":")[0] | tonumber) < 18)
    | .temperature.feels_like_f
  ]
  | if length == 0 then "false"
    elif all(. != null and . > 32) then "true"
    else "false"
    end
' "$WEATHER_JSON" -r)

if $WIND_OK && [[ "$FREEZE_OK" == "true" ]]; then
  BIKE_COLOR="#4caf50"
  BIKE_STATUS="Yes! Wind less than 6 kts, not freezing in the daytime."
else
  BIKE_COLOR="#e05020"
  REASONS=()
  $WIND_OK || REASONS+=("too windy (${AVG_KTS} kts)")
  [[ "$FREEZE_OK" == "true" ]] || REASONS+=("freezing today")
  IFS='; '; BIKE_STATUS="${REASONS[*]}"; unset IFS
fi

# ── sail callout ───────────────────────────────────────────────────────────────

GOOD_SAIL_TODAY=$(jq --arg today "$TODAY" '
  [ .hourly[]
    | select(.time | startswith($today))
    | select(
        (.wind.direction_degrees != null and .wind.direction_degrees >= 90 and .wind.direction_degrees <= 270)
        and (.wind.speed_ms != null and (.wind.speed_ms * 1.94384) >= 6 and (.wind.speed_ms * 1.94384) < 17)
        and (.temperature.actual_f != null and .temperature.actual_f > 60)
      )
    | (.time | gsub(" "; "T") | split("T")[1] | split(":")[0] | tonumber)
  ]
' "$WEATHER_JSON")

SAIL_RANGES_TODAY=$(build_range_labels "$GOOD_SAIL_TODAY")
SAIL_COUNT=$(echo "$GOOD_SAIL_TODAY" | jq 'length')

if [[ "$SAIL_COUNT" -gt 0 ]]; then
  SAIL_COLOR="#4caf50"
  SAIL_STATUS="Good hours:<br>${SAIL_RANGES_TODAY}"
else
  SAIL_COLOR="#e05020"
  SAIL_STATUS="No good sailing today."
fi

FUTURE_SAIL=$(jq --arg today "$TODAY" '
  [ .hourly[]
    | select((.time | gsub(" "; "T") | split("T")[0]) > $today)
    | select(
        (.wind.direction_degrees != null and .wind.direction_degrees >= 90 and .wind.direction_degrees <= 270)
        and (.wind.speed_ms != null and (.wind.speed_ms * 1.94384) >= 6 and (.wind.speed_ms * 1.94384) < 17)
        and (.temperature.actual_f != null and .temperature.actual_f > 60)
      )
    | { date: (.time | gsub(" "; "T") | split("T")[0]), hour: (.time | gsub(" "; "T") | split("T")[1] | split(":")[0] | tonumber) }
  ]
' "$WEATHER_JSON")

NEXT_WINDOW_HTML=""
FIRST_FUTURE_DATE=$(echo "$FUTURE_SAIL" | jq -r 'if length > 0 then .[0].date else "" end')
if [[ -n "$FIRST_FUTURE_DATE" ]]; then
  FIRST_DAY_HOURS=$(echo "$FUTURE_SAIL" | jq --arg d "$FIRST_FUTURE_DATE" '[.[] | select(.date == $d) | .hour]')
  FUTURE_RANGES=$(build_range_labels "$FIRST_DAY_HOURS")
  if [[ "$FIRST_FUTURE_DATE" == "$TOMORROW" ]]; then
    FUTURE_DAY_LABEL="Tomorrow"
  else
   FUTURE_DAY_LABEL=$(date -j -f "%Y-%m-%d" "$FIRST_FUTURE_DATE" +"%A" 2>/dev/null || date -d "$FIRST_FUTURE_DATE" +"%A")
  fi
  NEXT_WINDOW_HTML='<div class="next-window">Next: '"${FUTURE_DAY_LABEL}"'<br>'"${FUTURE_RANGES}"'</div>'
fi

# ── hourly table rows ──────────────────────────────────────────────────────────

HOURLY_ROWS=""
while IFS= read -r row; do
  TIME=$(echo "$row" | jq -r '.time')
  ACTUAL_C=$(echo "$row" | jq -r '.temperature.actual_c // "null"')
  ACTUAL_F=$(echo "$row" | jq -r '.temperature.actual_f // "null"')
  FEELS_C=$(echo "$row"  | jq -r '.temperature.feels_like_c // "null"')
  FEELS_F=$(echo "$row"  | jq -r '.temperature.feels_like_f // "null"')
  SPEED_MS=$(echo "$row" | jq -r '.wind.speed_ms // "null"')
  DIR=$(echo "$row"      | jq -r '.wind.direction_degrees // "null"')
  PRECIP=$(echo "$row"   | jq -r '.precipitation_mm // "null"')
  HUMIDITY=$(echo "$row" | jq -r '.relative_humidity // "null"')

  SPEED_KTS=$(ms_to_kts "$SPEED_MS")
  TIME_LABEL=$(format_time "$TIME")

  # Convert wind direction degrees to an arrow character
  if [[ -z "$DIR" || "$DIR" == "null" ]]; then
    DIR_ARROW="—"
  else
    DIR_ARROW=$(echo "$DIR" | awk '{
      d = ($1 % 360 + 360) % 360
      # Arrow points in the direction wind is going (from opposite)
      # We rotate by adding 180 to get "coming from" -> "going to"
      idx = int((d + 22.5) / 45) % 8
      arrows[0] = "&#x2193;"
      arrows[1] = "&#x2199;"
      arrows[2] = "&#x2190;"
      arrows[3] = "&#x2196;"
      arrows[4] = "&#x2191;"
      arrows[5] = "&#x2197;"
      arrows[6] = "&#x2192;"
      arrows[7] = "&#x2198;"
      print arrows[idx]
    }')
  fi

  HOURLY_ROWS="${HOURLY_ROWS}  <tr>
    <td>$(fmt "$TIME_LABEL")</td>
    <td class=\"$(get_temp_class "$ACTUAL_C")\">$(fmt "$ACTUAL_C") / $(fmt "$ACTUAL_F")</td>
    <td class=\"$(get_temp_class "$FEELS_C")\">$(fmt "$FEELS_C") / $(fmt "$FEELS_F")</td>
    <td class=\"$(get_wind_speed_class "$SPEED_KTS")\">$(fmt "$SPEED_KTS")</td>
    <td class=\"$(get_wind_dir_class "$DIR")\">$(fmt "$DIR_ARROW")</td>
    <td class=\"$(get_precip_class "$PRECIP")\">$(fmt "$PRECIP")</td>
    <td class=\"$(get_humidity_class "$HUMIDITY")\">$(fmt "$HUMIDITY")</td>
  </tr>
"
done < <(jq -c '.hourly[]' "$WEATHER_JSON")

# ── write output ───────────────────────────────────────────────────────────────

{
cat << 'HTML'
<!DOCTYPE html>
<html>
  <head>
    <title>Weather</title>
    <style>
      body { font-family: sans-serif; max-width: 900px; margin: 0 auto; padding: 1em; }
      table { border-collapse: collapse; width: 100%; margin-bottom: 2em; }
      th, td { border: 1px solid #ccc; padding: 4px 8px; text-align: center; font-size: 0.85em; }
      th { background: #eee; }
      .card { background: #f5f5f5; border-radius: 8px; padding: 1em 1.5em; }
      .card h3 { margin: 0 0 0.5em 0; }
      td.humidity-0   { background: hsl(210,100%,100%); }
      td.humidity-10  { background: hsl(210,100%,95%); }
      td.humidity-20  { background: hsl(210,100%,90%); }
      td.humidity-30  { background: hsl(210,100%,85%); }
      td.humidity-40  { background: hsl(210,100%,78%); }
      td.humidity-50  { background: hsl(210,100%,70%); }
      td.humidity-60  { background: hsl(210,100%,62%); }
      td.humidity-70  { background: hsl(210,100%,54%); }
      td.humidity-80  { background: hsl(210,100%,46%); }
      td.humidity-90  { background: hsl(210,100%,38%); }
      td.humidity-100 { background: hsl(210,100%,30%); }
      td.temp-verycold { background: hsl(240,80%,60%); }
      td.temp-cold     { background: hsl(200,80%,65%); }
      td.temp-cool     { background: hsl(160,60%,65%); }
      td.temp-mild     { background: hsl(140,60%,65%); }
      td.temp-warm     { background: hsl(120,70%,60%); }
      td.temp-hot      { background: hsl(40,90%,60%); }
      td.temp-veryhot  { background: hsl(0,90%,50%); }
      td.wind-speed-calm     { background: #ffffff; }
      td.wind-speed-light    { background: #d4f0c0; }
      td.wind-speed-moderate { background: #a8e6a3; }
      td.wind-speed-fresh    { background: #f4e04a; }
      td.wind-speed-strong   { background: #f4a430; }
      td.wind-speed-gale     { background: #e05020; }
      td.wind-dir-good { background: #a8e6a3; }
      td.wind-dir-mid  { background: #f4e04a; }
      td.wind-dir-bad  { background: #f4a460; }
      td.precip        { background: #d0eeff; }
      .top-layout { display: flex; gap: 1em; align-items: flex-start; margin-bottom: 1em; }
      .webcam-img { max-width: 100%; flex: 1 1 auto; }
      .callout-col { display: flex; flex-direction: column; gap: 0.75em; min-width: 180px; max-width: 230px; }
      .callout-card { border-left: 4px solid #ccc; }
      .callout-card h3 { margin: 0 0 0.25em 0; }
      .callout-card p { margin: 0; font-size: 0.9em; }
      .next-window { margin-top: 0.4em; font-size: 0.8em; color: #555; border-top: 1px solid #ddd; padding-top: 0.4em; }
      .overflow-auto { overflow-x: auto; }
      #kagi-search { margin-bottom: 1em; }
      #kagi-search input[type="text"] { width: 100%; padding: 0.5em 0.75em; font-size: 1em; border: 1px solid #ccc; border-radius: 4px; box-sizing: border-box; }

      @media print {

        /* ── Page setup ── */
        @page {
          size: letter landscape;
          margin: 0.45in 0.4in 0.4in;
        }

        /* ── Kill screen chrome ── */
        body {
          font-family: "Courier New", Courier, monospace;
          font-size: 7pt;
          line-height: 1.25;
          color: #000;
          background: #fff;
          margin: 0;
          padding: 0;
        }

        /* ── Hide non-data elements ── */
        #kagi-search,
        .webcam-img,
        script,
        .callout-col {
          display: none !important;
        }

        /* ── Top layout: collapse to header bar ── */
        .top-layout {
          display: block;
          border-bottom: 2pt solid #000;
          padding-bottom: 4pt;
          margin-bottom: 4pt;
        }

        /* ── Station header (injected via the h2) ── */
        h2.time {
          font-family: "Courier New", Courier, monospace;
          font-size: 10pt;
          font-weight: bold;
          letter-spacing: 0.08em;
          text-transform: uppercase;
          border-bottom: 0.5pt solid #000;
          padding-bottom: 2pt;
          margin: 0 0 4pt 0;
          text-align: center;
        }

        h2.time::before {
          content: "METEOROLOGICAL FORECAST NELSON ISLAND  //  ";
        }

        /* ── Table: full-width, dense, old-school ── */
        .overflow-auto {
          overflow: visible;
        }

        table {
          width: 100%;
          border-collapse: collapse;
          border-spacing: 0;
          table-layout: fixed;
          font-family: "Courier New", Courier, monospace;
          font-size: 6.5pt;
          page-break-inside: avoid;
        }

        /* Column widths */
        table colgroup,
        table col { display: none; }

        th:nth-child(1), td:nth-child(1) { width: 14%; }
        th:nth-child(2), td:nth-child(2) { width: 13%; }
        th:nth-child(3), td:nth-child(3) { width: 13%; }
        th:nth-child(4), td:nth-child(4) { width: 10%; }
        th:nth-child(5), td:nth-child(5) { width: 8%; }
        th:nth-child(6), td:nth-child(6) { width: 8%; }
        th:nth-child(7), td:nth-child(7) { width: 8%; }

        th, td {
          border: 0.4pt solid #555;
          padding: 1.2pt 3pt;
          text-align: center;
          vertical-align: middle;
          white-space: nowrap;
        }

        thead th {
          background: #000 !important;
          color: #fff !important;
          -webkit-print-color-adjust: exact;
          print-color-adjust: exact;
          font-weight: bold;
          font-size: 6pt;
          letter-spacing: 0.04em;
          text-transform: uppercase;
          border-color: #000;
        }

        /* Day separator: bold left border on first row of each day */
        tr:has(td:first-child:matches(*, [data-day])) td:first-child {
          font-weight: bold;
        }

        /* Zebra rows — very subtle */
        tbody tr:nth-child(even) td {
          background: #f5f5f5 !important;
          -webkit-print-color-adjust: exact;
          print-color-adjust: exact;
        }

        /* ── Temperature colour bands ── */
        td.temp-verycold { background: #c8d8f0 !important; -webkit-print-color-adjust: exact; print-color-adjust: exact; }
        td.temp-cold     { background: #dce8f4 !important; -webkit-print-color-adjust: exact; print-color-adjust: exact; }
        td.temp-cool     { background: #d6eedd !important; -webkit-print-color-adjust: exact; print-color-adjust: exact; }
        td.temp-mild     { background: #c8e8c0 !important; -webkit-print-color-adjust: exact; print-color-adjust: exact; }
        td.temp-warm     { background: #f5e8a0 !important; -webkit-print-color-adjust: exact; print-color-adjust: exact; }
        td.temp-hot      { background: #f5c060 !important; -webkit-print-color-adjust: exact; print-color-adjust: exact; }
        td.temp-veryhot  { background: #e8805a !important; color: #fff !important; -webkit-print-color-adjust: exact; print-color-adjust: exact; }

        /* ── Wind colour bands ── */
        td.wind-speed-calm     { background: #ffffff !important; }
        td.wind-speed-light    { background: #e8f5e0 !important; -webkit-print-color-adjust: exact; print-color-adjust: exact; }
        td.wind-speed-moderate { background: #d0ebc8 !important; -webkit-print-color-adjust: exact; print-color-adjust: exact; }
        td.wind-speed-fresh    { background: #f8f0a0 !important; -webkit-print-color-adjust: exact; print-color-adjust: exact; }
        td.wind-speed-strong   { background: #f5c860 !important; -webkit-print-color-adjust: exact; print-color-adjust: exact; }
        td.wind-speed-gale     { background: #e07040 !important; color: #fff !important; -webkit-print-color-adjust: exact; print-color-adjust: exact; }

        /* ── Wind direction colour bands ── */
        td.wind-dir-good { background: #d0ebc8 !important; -webkit-print-color-adjust: exact; print-color-adjust: exact; }
        td.wind-dir-mid  { background: #f8f0a0 !important; -webkit-print-color-adjust: exact; print-color-adjust: exact; }
        td.wind-dir-bad  { background: #f5c8a0 !important; -webkit-print-color-adjust: exact; print-color-adjust: exact; }

        /* ── Humidity colour bands ── */
        td[class^="humidity-"] {
          -webkit-print-color-adjust: exact;
          print-color-adjust: exact;
        }
        td.humidity-0   { background: #fff !important; }
        td.humidity-10  { background: #eef5fc !important; }
        td.humidity-20  { background: #ddeefa !important; }
        td.humidity-30  { background: #cce5f8 !important; }
        td.humidity-40  { background: #b8d8f5 !important; }
        td.humidity-50  { background: #9ec8f0 !important; }
        td.humidity-60  { background: #82b5e8 !important; }
        td.humidity-70  { background: #65a0dc !important; }
        td.humidity-80  { background: #4888cc !important; color: #fff !important; }
        td.humidity-90  { background: #2d70bb !important; color: #fff !important; }
        td.humidity-100 { background: #1050a0 !important; color: #fff !important; }

        /* ── Precipitation ── */
        td.precip { background: #a8d8f8 !important; -webkit-print-color-adjust: exact; print-color-adjust: exact; }

        /* ── Legend block ── */
        body::after {
          display: block;
          content: "TEMP  [C°/F°]   WIND  [knots]   DIR  [degrees]   P  [mm/hr]   H  [%RH]   //   Shading: blue=humid · green=cool · amber=warm · orange=strong wind · red=hot/gale";
          font-family: "Courier New", Courier, monospace;
          font-size: 5.5pt;
          letter-spacing: 0.03em;
          color: #444;
          border-top: 0.5pt solid #000;
          padding-top: 3pt;
          margin-top: 4pt;
        }

        /* ── Don't break inside a run of rows ── */
        tr { page-break-inside: avoid; }

        /* force rows to pack tight — override any JS-set heights */
        tr, td, th { height: auto !important; }
        tbody tr:nth-child(n-7) {
            display: none;
        }
        tbody tr:nth-child(n+50) {
            display: none !important;
        }
        tbody tr:nth-child(n+8) {
            display: table-row;
        }
      }
    </style>
    <link rel="manifest" href="manifest.json">
    <script>
      if ('serviceWorker' in navigator) {
        navigator.serviceWorker.register('sw.js');
      }
    </script>
  </head>
HTML

cat << HTML
  <body>
    <!-- <form id="kagi-search" action="https://kagi.com/search" method="get" target="_self">
       <input type="text" name="q" placeholder="Search Kagi…" autofocus />
    </form> -->

    <div class="top-layout">
     <img src="webcam.jpg" class="webcam-img"/>
      <div class="callout-col">


        <div class="card callout-card" style="border-left-color: ${BIKE_COLOR}">
          <h3>Bike</h3>
          <p>${BIKE_STATUS}</p>
        </div>

        <div class="card callout-card" style="border-left-color: ${SAIL_COLOR}">
          <h3>Sail</h3>
          <p>${SAIL_STATUS}</p>
          ${NEXT_WINDOW_HTML}
        </div>

        <div class="card callout-card">
          <h3>Wind: ${AVG_KTS} kts</h3>
          <p>Peak: ${PEAK_KTS} kts</p>
          <p>Direction: ${WIND_DIR}&deg;</p>
        </div>

        <div class="card callout-card">
          <h3>Temperature: ${FEELS_AVG_F}&deg;F</h3>
          <p>Low: ${LOW_C}&deg;C / ${LOW_F}&deg;F</p>
          <p>High: ${HIGH_C}&deg;C / ${HIGH_F}&deg;F</p>
        </div>

        <div class="card callout-card">
          <h3>Water: ${PASCO_WATER_TEMP}&deg;F</h3>
        </div>

      </div>
    </div>

    <h2 class="time"><span id="date">${DATE_STRING}</span> <span id="time"></span></h2>
    <div class="overflow-auto">
      <table>
        <thead>
          <tr>
            <th>Time</th>
            <th>Temp (&deg;C / &deg;F)</th>
            <th>Feels Like (&deg;C / &deg;F)</th>
            <th>Wind (kts)</th>
            <th>Wind Dir (&deg;)</th>
            <th>P (mm)</th>
            <th>H (%)</th>
          </tr>
        </thead>
        <tbody>
${HOURLY_ROWS}
        </tbody>
      </table>
    </div>
    <script>
      // Focus search input on load
      // with a small timeout
      // setTimeout(() => {
      //   document.getElementById('kagi-search').querySelector('input[type="text"]').focus();
      // }, 150);
      timeElem = document.querySelector('#time');
      if (timeElem) {
        // Get nice date in Pacific time zone
        const now = new Date();
        const options = { hour: '2-digit', minute: '2-digit', timeZone: 'America/Los_Angeles' };
        timeElem.textContent = now.toLocaleString('en-US', options);
      }
      document.addEventListener("DOMContentLoaded", async () => {
        if (!("serviceWorker" in navigator)) return;

        try {
          const registration = await navigator.serviceWorker.register("/sw.js", {
            scope: "/",
          });

          console.log("SW state:", registration.active?.state);
          console.log("SW waiting:", registration.waiting);
          console.log("SW installing:", registration.installing);

          console.log("Calling update...");
          registration.update().then(() => {
            console.log("update() resolved");
            console.log("SW waiting after update:", registration.waiting);
            console.log("SW installing after update:", registration.installing);
          });

          registration.addEventListener("updatefound", () => {
            console.log("updatefound fired!", registration.installing?.state);
            const worker = registration.installing;
            worker.addEventListener("statechange", () => {
              console.log("worker statechange:", worker.state);
              if (worker.state === "installed") {
                worker.postMessage({ type: "SKIP_WAITING" });
              }
            });
          });

        } catch (err) {
          console.log("SW registration failed", err);
        }
      });
    </script>
  </body>
</html>
HTML
} > "$OUTPUT_HTML"

./update_service_worker.sh "$OUTPUT_HTML"

echo "Generated: $OUTPUT_HTML"
