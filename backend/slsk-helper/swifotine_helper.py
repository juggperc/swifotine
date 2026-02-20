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
        
        # Prevent default config from trying to write to standard config dir by setting isolated mode or overriding
        os.environ['XDG_CONFIG_HOME'] = os.path.join(os.getcwd(), '.nicotine-data')
        os.makedirs(os.environ['XDG_CONFIG_HOME'], exist_ok=True)
        
        core.init_components(enabled_components=enabled, isolated_mode=True)
        
        # Register Nicotine core hooks
        events.connect("server-login", self.on_server_login)
        events.connect("invalid-password", self.on_invalid_auth)
        events.connect("invalid-username", self.on_invalid_auth)
        events.connect("disconnect", self.on_disconnect)
        events.connect("search-result", self.on_search_result)
        events.connect("update-download", self.on_update_download)
        events.connect("download-finished", self.on_download_finished)
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
        
    def on_search_result(self, search_result):
        # We need to pick out the interesting fields
        self.emit_event("search.result", {
            "token": getattr(search_result, "token", "unknown"),
            "peer_username": getattr(search_result, "user", "unknown"),
            "file_path": getattr(search_result, "filename", "unknown"),
            "size": getattr(search_result, "size", 0),
            "bitrate": getattr(search_result, "bitrate", 0),
            "length": getattr(search_result, "length", 0)
        })

    def on_update_download(self, transfer, *args):
        self.emit_event("download.updated", {
            "transfer_id": getattr(transfer, "id", "unknown"),
            "status": getattr(transfer, "status", "unknown"),
            "bytes_transferred": getattr(transfer, "transferred", 0),
            "total": getattr(transfer, "size", 0),
            "speed": getattr(transfer, "speed", 0),
            "eta": getattr(transfer, "eta", 0),
            "local_path": getattr(transfer, "file_path", "")
        })

    def on_download_finished(self, transfer, *args):
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

    def emit_event(self, event_name, payload):
        sys.stdout.write(json.dumps({"event": event_name, "payload": payload}) + "\n")
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
                if core.search and query:
                    # mode 1 typically represents global
                    core.search.do_search(query, mode=1)
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
