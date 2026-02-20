# Swifotine IPC Contract

The Swift application communicates with the Python helper via newline-delimited JSON over stdio streams.

## 1) Request Envelope (Swift -> Python)

```json
{ "id": "uuid", "method": "string", "params": { ... } }
```

## 2) Response Envelope (Python -> Swift)

Success:

```json
{ "id": "uuid", "ok": true, "result": { ... } }
```

Failure:

```json
{ "id": "uuid", "ok": false, "error": { "code": "string", "message": "string", "details": { ... } } }
```

## 3) Event Envelope (Python -> Swift)

```json
{ "event": "string", "payload": { ... } }
```

## Supported RPC Methods

- `session.configure` (params: `username`, `password`, `downloadRoot`, `incompleteRoot`)
- `session.connect`
- `session.disconnect`
- `search.start` (params: `query`, `mode` (global), `limit`)
- `search.stop` (params: `token`)
- `download.enqueue` (params: `username`, `virtualPath`, `targetFolder` (opt), `size` (opt), `attributes` (opt))
- `download.pause`
- `download.resume`
- `download.cancel`
- `download.clear`
- `downloads.list`
- `health.ping`
- `settings.update`

## Supported Event Types

- `connection.state_changed` (`offline|connecting|online|error`, `server_reason`, `username`)
- `search.result` (`token`, `peer_username`, `file_path`, `size`, `bitrate`, `length`, `queue_position`, `upload_speed`, `country`)
- `search.completed` (`token`, `aggregate_counts`)
- `download.updated` (`transfer_id`, `status`, `bytes_transferred`, `total`, `speed`, `eta`, `local_path`)
- `download.finished` (`local_file_path`, `source_username`, `virtual_path`)
- `download.failed` (`transfer_id`, `categorized_reason`)
- `backend.log` (`level`, `message`)
