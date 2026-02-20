import sys
import os
import json
import threading
import time

# Path to upstream nicotine+ submodule
VENDOR_PATH = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', 'vendor', 'nicotine-plus'))
sys.path.insert(0, VENDOR_PATH)

import pynicotine
from pynicotine.config import config
from pynicotine.events import events
from pynicotine.core import core

class SwifotineHelper:
    """
    JSON-RPC out-of-process helper bridging nicotine-plus to standard IO.
    """
    def __init__(self):
        self.session_config = {}
        self.is_running = True

        # Initialize core components. We exclude UI and CLI.
        # "search" and "downloads" components must be enabled
        enabled = {
            "error_handler", "signal_handler", "portmapper", "network_thread", "shares", "users",
            "notifications", "network_filter", "statistics", "port_checker",
            "search", "downloads", "uploads", "interests", "userbrowse", "userinfo",
            "buddies", "privatechat", "pluginhandler"
        }
        
        # Keep helper config in app-specific user data, not in the launch CWD.
        helper_config_root = os.path.join(
            os.path.expanduser("~"), "Library", "Application Support", "Swifotine", "nicotine-config"
        )
        os.makedirs(helper_config_root, exist_ok=True)
        os.environ['XDG_CONFIG_HOME'] = helper_config_root
        
        core.init_components(enabled_components=enabled, isolated_mode=True)
        
        # Register Nicotine core hooks
        events.connect("server-login", self.on_server_login)
        events.connect("invalid-password", self.on_invalid_auth)
        events.connect("invalid-username", self.on_invalid_auth)
        events.connect("server-disconnect", self.on_disconnect)
        events.connect("file-search-response", self.on_search_result)
        events.connect("update-download", self.on_update_download)
        events.connect("download-file-error", self.on_download_error)
        events.connect("quit", self.on_quit)

    def on_server_login(self, *_args):
        self.emit_event("connection.state_changed", {
            "state": "online", 
            "server_reason": "", 
            "username": self.session_config.get("username", "")
        })

    def on_invalid_auth(self, *_args):
        self.emit_event("connection.state_changed", {
            "state": "error", 
            "server_reason": "invalid_credentials", 
            "username": self.session_config.get("username", "")
        })
        core.disconnect()

    def on_disconnect(self, *_args):
        self.emit_event("connection.state_changed", {
            "state": "offline", 
            "server_reason": "disconnected", 
            "username": self.session_config.get("username", "")
        })
        
    def on_search_result(self, msg, *args):
        if getattr(msg, "list", None) is None:
            return
        username = getattr(msg, "search_username", getattr(msg, "username", "unknown"))
        token = getattr(msg, "token", "unknown")
        for res in msg.list:
            if len(res) >= 3:
                filepath = res[1]
                size = res[2]
                attrs = res[4] if len(res) > 4 else {}
                self.emit_event("search.result", {
                    "token": token,
                    "peer_username": username,
                    "file_path": filepath,
                    "size": size,
                    "bitrate": attrs.get("bitrate", 0) if isinstance(attrs, dict) else 0,
                    "length": attrs.get("length", 0) if isinstance(attrs, dict) else 0
                })

    def on_update_download(self, transfer, *args):
        status = getattr(transfer, "status", "unknown")
        self.emit_event("download.updated", {
            "transfer_id": getattr(transfer, "id", "unknown"),
            "source_username": getattr(transfer, "user", "unknown"),
            "virtual_path": getattr(transfer, "virtual_path", ""),
            "status": str(status),
            "bytes_transferred": getattr(transfer, "transferred", 0),
            "total": getattr(transfer, "size", 0),
            "speed": getattr(transfer, "speed", 0),
            "eta": getattr(transfer, "eta", 0),
            "local_path": getattr(transfer, "file_path", "")
        })
        # If it finished or reached equivalent completion, broadcast a distinct finished event
        status_str = str(status).lower()
        if "finished" in status_str or "complete" in status_str:
            self.emit_event("download.finished", {
                "local_file_path": getattr(transfer, "file_path", ""),
                "source_username": getattr(transfer, "user", "unknown"),
                "virtual_path": getattr(transfer, "virtual_path", "")
            })
        
    def on_download_error(self, transfer, reason, *args):
        self.emit_event("download.failed", {
            "transfer_id": getattr(transfer, "id", "unknown"),
            "categorized_reason": str(reason)
        })

    def on_quit(self, *args):
        self.is_running = False

    def _normalize_payload(self, payload):
        if not isinstance(payload, dict):
            return {}

        normalized = {}
        for key, value in payload.items():
            if value is None:
                normalized[str(key)] = ""
            elif isinstance(value, (dict, list)):
                normalized[str(key)] = json.dumps(value, separators=(",", ":"), default=str)
            else:
                normalized[str(key)] = str(value)

        return normalized

    def emit_event(self, event_name, payload):
        sys.stdout.write(json.dumps({"event": event_name, "payload": self._normalize_payload(payload)}) + "\n")
        sys.stdout.flush()

    def respond(self, request_id, result=None, error=None):
        if error is not None:
            res = {"id": request_id, "ok": False, "error": error}
        else:
            res = {"id": request_id, "ok": True, "result": result or {}}
        sys.stdout.write(json.dumps(res) + "\n")
        sys.stdout.flush()

    def handle_request(self, line):
        try:
            req = json.loads(line.strip())
        except json.JSONDecodeError:
            self.emit_event("backend.log", {"level": "error", "message": "Failed to decode JSON request"})
            return

        method = req.get("method")
        params = req.get("params", {})
        req_id = req.get("id", "none")

        try:
            if method == "health.ping":
                self.respond(req_id, {"status": "ok"})
            elif method == "session.configure":
                self.session_config.update(params)
                
                # Apply config to pynicotine
                if "username" in params:
                    config.sections["server"]["login"] = params["username"]
                if "password" in params:
                    config.sections["server"]["passw"] = params["password"]
                    
                # Downloads configuration
                if "downloadRoot" in params:
                    config.sections["transfers"]["downloaddir"] = params["downloadRoot"]
                if "incompleteRoot" in params:
                    config.sections["transfers"]["incompletedir"] = params["incompleteRoot"]
                
                self.respond(req_id, {"configured": True})
            elif method == "session.connect":
                self.emit_event("connection.state_changed", {
                    "state": "connecting", 
                    "server_reason": "", 
                    "username": self.session_config.get("username", "")
                })
                core.connect()
                self.respond(req_id)
            elif method == "session.disconnect":
                core.disconnect()
                self.respond(req_id)
            elif method == "search.start":
                query = params.get("query", "")
                if getattr(core, "search", None) and query:
                    core.search.do_search(query, mode="global")
                self.respond(req_id)
            elif method == "download.enqueue":
                username = params.get("username", "")
                vpath = params.get("virtualPath", "")
                if core.downloads and username and vpath:
                    core.downloads.enqueue_download(username, vpath)
                self.respond(req_id)
            else:
                self.respond(req_id, error={"code": "MethodNotFound", "message": f"Unknown method: {method}", "details": {}})
        except Exception as e:
            self.respond(req_id, error={"code": "InternalError", "message": str(e), "details": {}})

    def input_loop(self):
        for line in sys.stdin:
            if not line.strip():
                continue
            self.handle_request(line)
        self.is_running = False

    def run(self):
        self.emit_event("backend.log", {"level": "info", "message": "Swifotine Helper initialized and awaiting commands."})
        
        core.start()
        
        input_thread = threading.Thread(target=self.input_loop, daemon=True)
        input_thread.start()
        
        while self.is_running and events.process_thread_events():
            time.sleep(0.05)
            
        core.quit()

if __name__ == "__main__":
    helper = SwifotineHelper()
    helper.run()
