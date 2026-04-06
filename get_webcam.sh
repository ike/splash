#! /bin/bash

OUTPUT_HTML="${1:-index.html}"
OUTPUT_DIR="$(dirname "$OUTPUT_HTML")"
SCRIPT_DIR="$(dirname "$(realpath "$0")")"
NO_UPDATE_SW="${2:-}"

# img_url=$(curl -X 'GET' \
#  'https://api.windy.com/webcams/api/v3/webcams/1756933961?lang=en&include=images,urls' \
#  -H 'accept: application/json' \
#  -H 'x-windy-api-key: m4MBUPLQGbT04Tz6kCxcDIOTbYzfdy6t' | jq -r '.images.current.preview')

img_url="https://imgproxy.windy.com/_/preview/plain/current/1756933961/original.jpg"

echo "Downloading webcam image from: $img_url"
curl $img_url -o $SCRIPT_DIR/webcam.jpg

cp $SCRIPT_DIR/webcam.jpg "$OUTPUT_DIR/webcam.jpg"
echo "Webcam image saved to: $OUTPUT_DIR/webcam.jpg"

if [ "$NO_UPDATE_SW" != "--no-update-sw" ]; then
    $SCRIPT_DIR/update_service_worker.sh $OUTPUT_HTML
fi
