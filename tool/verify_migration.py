#!/usr/bin/env python3
"""Reads the test account's Firestore state to confirm the migration persisted:
every password doc should now have v=2 + iv, and the profile securityVersion=2."""
import json
import urllib.request

API = "AIzaSyDp1tCNUMK_wCNMXfAP1CgFlmayTXi3ODY"
PROJECT = "cipher-eye"
EMAIL = "migration.test.001@example.com"
PASSWORD = "Migrate!Test#2026xZ"


def post(url, body):
    req = urllib.request.Request(
        url, data=json.dumps(body).encode(), headers={"Content-Type": "application/json"})
    return json.load(urllib.request.urlopen(req))


def get(url, token):
    req = urllib.request.Request(url, headers={"Authorization": f"Bearer {token}"})
    return json.load(urllib.request.urlopen(req))


sess = post(
    f"https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key={API}",
    {"email": EMAIL, "password": PASSWORD, "returnSecureToken": True})
token, uid = sess["idToken"], sess["localId"]
base = f"https://firestore.googleapis.com/v1/projects/{PROJECT}/databases/(default)/documents"

prof = get(f"{base}/users/{uid}", token)
sv = prof.get("fields", {}).get("securityVersion", {}).get("integerValue", "(fehlt)")
print(f"Profil  securityVersion = {sv}")

pw = get(f"{base}/users/{uid}/passwords", token)
print("Passwoerter:")
for d in pw.get("documents", []):
    name = d["name"].split("/")[-1]
    f = d["fields"]
    v = f.get("v", {}).get("integerValue", "(fehlt)")
    has_iv = "iv" in f
    print(f"  {name:8} v={v}  iv={'ja' if has_iv else 'NEIN'}")
