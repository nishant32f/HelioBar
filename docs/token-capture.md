# Capturing your Zepp apptoken

The Zepp cloud API has no password login, so HelioBar needs the `apptoken`
header the official app sends.

## Option A — HTTP Toolkit (no root)
1. Install HTTP Toolkit (free) on your computer.
2. Start "Intercept" for your phone (follow its Wi-Fi/cert steps).
3. Open the Zepp app, pull-to-refresh your data.
4. In HTTP Toolkit, find a request to a `*.zepp.com` / `*.huami.com` host.
5. Copy the `apptoken` request header value and the request **host**.
6. Paste both into HelioBar ▸ Settings.

## Option B — rooted Android
Read `apptoken` from:
`/data/data/com.huami.watch.hmwatchmanager/shared_prefs/hm_id_sdk_android.xml`

## Calibrating endpoints
The exact stress/readiness path in `ZeppCloudClient.makeRequest` and the JSON
shape in `decode` are placeholders. Compare a real captured response and adjust
both to match. Tests in `ZeppCloudClientTests` pin the parsing contract.
