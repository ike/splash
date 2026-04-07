#! /bin/bash

SPLASH_HTML_FILE_PATH="${1:-./index.html}"
SCRIPT_DIR="$(dirname "$(realpath "$0")")"

$SCRIPT_DIR/get_webcam.sh "$SPLASH_HTML_FILE_PATH" --no-update-sw

# curl -X 'GET' \
#   'https://my.meteoblue.com/packages/basic-day?apikey=aL4b8GwhENBgiSTl&lat=46.309&lon=-119.254&asl=124&format=json' \

# curl -X 'GET' \
#   'https://my.meteoblue.com/packages/basic-1h_basic-day?apikey=aL4b8GwhENBgiSTl&lat=46.309&lon=-119.254&asl=124&format=json' | \
data=$(curl -s 'https://my.meteoblue.com/packages/basic-1h?apikey=aL4b8GwhENBgiSTl&lat=46.309&lon=-119.254&asl=124&format=json')
TODAY=$(date +%Y-%m-%d)
TIMESTAMP=$(date +%Y-%m-%dT%H-%M-%S)
DATA_DIR="$SCRIPT_DIR/data"
mkdir -p "$DATA_DIR"

echo $data | jq '.' > $SCRIPT_DIR/raw_weather.json
cp $SCRIPT_DIR/raw_weather.json "$DATA_DIR/raw_weather_${TIMESTAMP}.json"

echo "$data" | jq --arg today "$TODAY" '{
  today: {
    wind: {
      average_ms: ([.data_1h.windspeed[0:23][] | select(. != null)] | add / length),
      peak_ms: ([.data_1h.windspeed[0:23][] | select(. != null)] | max)
    },
    temperature: {
      feels_like_avg_c: ([.data_1h.felttemperature[0:23][] | select(. != null)] | add / length),
      feels_like_avg_f: (([.data_1h.felttemperature[0:23][] | select(. != null)] | add / length) * 9/5 + 32 | round),
      low_c: ([.data_1h.temperature[0:23][] | select(. != null)] | min),
      low_f: (([.data_1h.temperature[0:23][] | select(. != null)] | min) * 9/5 + 32 | round),
      high_c: ([.data_1h.temperature[0:23][] | select(. != null)] | max),
      high_f: (([.data_1h.temperature[0:23][] | select(. != null)] | max) * 9/5 + 32 | round)
    },
    wind_direction_degrees: ([.data_1h.winddirection[0:23][] | select(. != null)] | add / length | round)
  },
  hourly: (
    if .data_1h then
      [range(.data_1h.time | length) as $i | {
        time: .data_1h.time[$i],
        wind: {
          speed_ms: (if .data_1h.windspeed then .data_1h.windspeed[$i] else null end),
          speed_mph: ((if .data_1h.windspeed then (.data_1h.windspeed[$i] // 0) else 0 end) * 2.23694 | round),
          direction_degrees: (if .data_1h.winddirection then .data_1h.winddirection[$i] else null end)
        },
        temperature: {
          actual_c: (if .data_1h.temperature then .data_1h.temperature[$i] else null end),
          actual_f: ((if .data_1h.temperature then (.data_1h.temperature[$i] // 0) else 0 end) * 9/5 + 32 | round),
          feels_like_c: (if .data_1h.felttemperature then .data_1h.felttemperature[$i] else null end),
          feels_like_f: ((if .data_1h.felttemperature then (.data_1h.felttemperature[$i] // 0) else 0 end) * 9/5 + 32 | round)
        },
        precipitation_mm: .data_1h.precipitation[$i],
        relative_humidity: .data_1h.relativehumidity[$i],
        uvindex: .data_1h.uvindex[$i]
      } | select(.time >= $today)]
    else
      "hourly data not available in this API response (add basic-1h package)"
    end
  )
}' > $SCRIPT_DIR/weather.json
cp $SCRIPT_DIR/weather.json "$DATA_DIR/weather_${TIMESTAMP}.json"

# Get water quality data for yesterday
YESTERDAY=$(date -v-1d +%m/%d 2>/dev/null || date -d "yesterday" +%m/%d)
YESTERDAY_YEAR=$(date -v-1d +%Y 2>/dev/null || date -d "yesterday" +%Y)
YESTERDAY_URL_ENCODED=$(echo "$YESTERDAY" | sed 's|/|%2F|g')

# Fetch CSV for Pasco (PAQW), Priest Rapids (PRQW), and McNary (MCQW)
fetch_water_temp() {
  local proj=$1
  local csv
  url="https://www.cbr.washington.edu/dart/cs/php/rpt/wqm_hourly.php?sc=1&outputFormat=csv&year=${YESTERDAY_YEAR}&proj=${proj}&startdate=${YESTERDAY_URL_ENCODED}&days=1&keys="
  csv=$(curl -s "$url" | tail -n +2) # Skip header
  # Find the row matching yesterday's date, get temperature (col 3) and oxygen (col 4)
  echo "$csv" > $SCRIPT_DIR/${proj}_raw.csv
  cp $SCRIPT_DIR/${proj}_raw.csv "$DATA_DIR/${proj}_raw_${TIMESTAMP}.csv"
  echo "$csv" | head -1
}
pasco_row=$(fetch_water_temp "PAQW")
#priest_row=$(fetch_water_temp "PRQW")
#mcnary_row=$(fetch_water_temp "MCQW")


parse_field() {
  echo "$1" | awk -F',' "{print \$$2}" | tr -d '\r'
}

pasco_temp=$(parse_field "$pasco_row" 8)
pasco_oxygen=$(parse_field "$pasco_row" 11)
#priest_temp=$(parse_field "$priest_row" 3)
#priest_oxygen=$(parse_field "$priest_row" 4)
#mcnary_temp=$(parse_field "$mcnary_row" 3)
#mcnary_oxygen=$(parse_field "$mcnary_row" 4)

printf "Pasco - Temp: %s °C, Oxygen: %s mg/L\n" "$pasco_temp" "$pasco_oxygen"

jq -n \
  --argjson pt "${pasco_temp:-null}" \
  --argjson po "${pasco_oxygen:-null}" \
  '{
    pasco: { temperature: $pt, oxygen: $po },
  }' > $SCRIPT_DIR/water.json
cp $SCRIPT_DIR/water.json "$DATA_DIR/water_${TIMESTAMP}.json"
 # --argjson prt "${priest_temp:-null}" \
 # --argjson pro "${priest_oxygen:-null}" \
 # --argjson mt "${mcnary_temp:-null}" \
 # --argjson mo "${mcnary_oxygen:-null}" \
 #  priest_rapids: { temperature: $prt, oxygen: $pro },
 #  mcnary: { temperature: $mt, oxygen: $mo }


SPLASH_DIR=$(dirname "$SPLASH_HTML_FILE_PATH")
if [ "$SPLASH_DIR" != "." ]; then
  cp webcam.jpg "$SPLASH_DIR/webcam.jpg"
fi

$SCRIPT_DIR/generate_html.sh weather.json water.json $SPLASH_HTML_FILE_PATH
