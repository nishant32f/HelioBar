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

Find the `apptoken` and the **host** (e.g. `api-mifit-us3.zepp.com`) in any
request to a `*.zepp.com` host, and paste both into HelioBar ▸ Settings.

## How the cloud endpoints are wired

`ZeppCloudClient` now targets the real, community-documented Zepp/Huami event
stream (from the `zepp-health-cli` project), not a placeholder:

```
GET https://<host>/v2/users/me/events
    ?eventType=<type>&subType=<sub>&from=<ms>&to=<ms>&limit=200&reverse=0
    apptoken: <token>
```

| Metric     | eventType    | subType        |
|------------|--------------|----------------|
| Stress     | `Charge`     | `stress_data`  |
| Readiness  | `readiness`  | `watch_score`  |
| Body batt. | `Charge`     | `real_data`    |

The response envelope `{"items":[{"timestamp","value"}]}` is stable; the client
takes the newest item and pulls a numeric score out of `value` (handling
nested objects and JSON-encoded strings).

### If values look wrong
The inner `value` keys can differ per account/firmware. If stress or readiness
parse incorrectly:
1. Capture one real `/v2/users/me/events` response for that subType.
2. Note the JSON path to the score.
3. Add the key to `scoreKeys` in `ZeppCloudClient.swift`, and/or adjust the
   `eventType`/`subType` strings in `fetchStress` / `fetchReadiness`.
4. Add a fixture to `ZeppCloudClientTests` so the contract stays pinned, then
   `swift test`.

> These endpoints are reverse-engineered and unofficial; they can change without
> notice. Body battery (`Charge`/`real_data`) is documented above for when you
> want to add it as a Phase-2 metric.
