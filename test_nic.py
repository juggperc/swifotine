import sys
sys.path.insert(0, 'vendor/nicotine-plus')
from pynicotine.config import Config
from pynicotine.core import Core
import pynicotine.events as events

def on_login(user):
    print("Logged in as:", user)

events.logined.append(on_login)
print("event hooks:", dir(events))
