#!/usr/bin/env python3
"""POST a local BLAST tabular result (outfmt 6/7) to the cloud agent.

The agent places the hits on the genome as the `blast_hits` JBrowse track and
returns a deep link.

Usage:
  AGENT_URL=https://your-agent.up.railway.app SITE_PASSWORD=... \
    python post_results.py hits.tsv --program blastn

Env:
  AGENT_URL       agent base URL (required)
  SITE_PASSWORD   shared-password (basic auth); user defaults to 'spalangia'
  SITE_USER       basic-auth user (default 'spalangia')
"""
import argparse
import base64
import json
import os
import sys
import urllib.request

ap = argparse.ArgumentParser()
ap.add_argument("results", help="BLAST outfmt 6/7 file ('-' for stdin)")
ap.add_argument("--program", default=None,
                help="blastn|tblastn|blastp|blastx (infers subject type)")
ap.add_argument("--subject-type", default=None, choices=["genome", "protein"])
args = ap.parse_args()

text = sys.stdin.read() if args.results == "-" else open(args.results).read()

agent = os.environ.get("AGENT_URL")
if not agent:
    sys.exit("set AGENT_URL")
payload = json.dumps({
    "results": text, "program": args.program, "subject_type": args.subject_type,
}).encode()

req = urllib.request.Request(
    f"{agent.rstrip('/')}/blast-results", data=payload,
    headers={"Content-Type": "application/json"})

pw = os.environ.get("SITE_PASSWORD")
if pw:
    user = os.environ.get("SITE_USER", "spalangia")
    tok = base64.b64encode(f"{user}:{pw}".encode()).decode()
    req.add_header("Authorization", f"Basic {tok}")

with urllib.request.urlopen(req) as resp:
    out = json.load(resp)

print(json.dumps(out, indent=2))
if out.get("jbrowse_url"):
    print("\nOpen in JBrowse:\n  " + out["jbrowse_url"])
