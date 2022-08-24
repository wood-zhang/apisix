#!/usr/bin/env python
# coding: utf-8
# save this file as ssl.py
import sys
# sudo pip install requests
import requests


if len(sys.argv) <= 3:
    print("bad argument")
    sys.exit(1)
with open(sys.argv[1]) as f:
    cert = f.read()
with open(sys.argv[2]) as f:
    key = f.read()
sni = sys.argv[3]
api_key = "edd1c9f034335f136f87ad84b625c8f1"
resp = requests.put("http://127.0.0.1:9080/apisix/admin/ssl/1", json={
    "cert": cert,
    "key": key,
    "snis": [sni],
}, headers={
    "X-API-KEY": api_key,
})
print(resp.status_code)
print(resp.text)
