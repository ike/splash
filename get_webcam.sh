#! /bin/bash

curl -X 'GET' \
  'https://api.windy.com/webcams/api/v3/webcams/1756933961?lang=en&include=images,urls' \
  -H 'accept: application/json' \
  -H 'x-windy-api-key: m4MBUPLQGbT04Tz6kCxcDIOTbYzfdy6t' | jq -r '.images.current.preview' | xargs curl -o webcam.jpg

