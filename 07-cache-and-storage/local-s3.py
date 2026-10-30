# /// script
# requires-python = ">=3.12"
# dependencies = ["minio>=7.2.15,<8"]
# ///
"""S3 client for the local object storage: SeaweedFS, service seaweedfs in
compose.yaml of PlaceFinder (from tag t07). Every store with the S3 API
works the same way; the endpoint and the keys come from the environment.

Usage: uv run local-s3.py <command>   (--help for details)
  setup                  CORS for the map and a lifecycle rule for raw/
  upload FILE [KEY]      upload a file; default key raw/<name>, tiles/ for .pmtiles
  list                   objects in the bucket
  presign KEY [SECONDS]  pre-signed URL (default 3600 s), tested without
                         signature, with a range request and with CORS
  map KEY [SECONDS]      address of the PlaceFinder map with ?tiles=<pre-signed
                         URL> (default 86400 s)

Environment (defaults as in compose.yaml): S3_ENDPOINT=http://localhost:8333,
S3_BUCKET=placefinder, LOCAL_S3_ACCESS_KEY=placefinder,
LOCAL_S3_SECRET_KEY=placefinder-local. The client is minio, a small S3
library under the Apache 2.0 license; it uses only the keys passed here.
"""

import argparse
import base64
import hashlib
import os
import sys
import urllib.error
import urllib.parse
import urllib.request
from datetime import UTC, datetime, timedelta
from email.message import Message
from pathlib import Path

from minio import Minio
from minio.commonconfig import ENABLED, Filter
from minio.credentials import Credentials
from minio.error import S3Error
from minio.lifecycleconfig import Expiration, LifecycleConfig, Rule
from minio.signer import sign_v4_s3
from urllib3.exceptions import MaxRetryError

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

ENDPOINT = os.environ.get("S3_ENDPOINT", "http://localhost:8333")
BUCKET = os.environ.get("S3_BUCKET", "placefinder")
ACCESS_KEY = os.environ.get("LOCAL_S3_ACCESS_KEY", "placefinder")
SECRET_KEY = os.environ.get("LOCAL_S3_SECRET_KEY", "placefinder-local")
REGION = "us-east-1"  # signed into every request; SeaweedFS accepts any
MAP_ORIGIN = "http://localhost:5173"  # frontend/index.html of PlaceFinder

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

# the map reads PMTiles with range requests and needs ETag and Content-Range
# in the answer
CORS_RULE = {
    "AllowedOrigin": MAP_ORIGIN,
    "AllowedMethod": ["GET", "HEAD"],
    "AllowedHeader": "Range",
    "ExposeHeader": ["ETag", "Content-Length", "Content-Range"],
    "MaxAgeSeconds": "3600",
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -


def client() -> Minio:
    url = urllib.parse.urlsplit(ENDPOINT)
    return Minio(
        url.netloc,  # localhost:8333; minio uses path-style addresses for it
        access_key=ACCESS_KEY,
        secret_key=SECRET_KEY,
        secure=url.scheme == "https",
        region=REGION,
    )


# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -


def http(
    url: str, method: str = "GET", headers: dict | None = None, body: bytes | None = None
) -> tuple[int, Message, bytes]:
    """Status, headers and body of a request; errors are answers, too."""
    request = urllib.request.Request(url, data=body, method=method, headers=headers or {})
    try:
        with urllib.request.urlopen(request, timeout=10) as response:
            return response.status, response.headers, response.read()
    except urllib.error.HTTPError as error:
        return error.code, error.headers, error.read()


# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -


def put_bucket_cors() -> None:
    """PUT /<bucket>?cors. minio has no call for CORS, so this request is
    signed by hand with the signature version 4 of minio - the same that
    every S3 request carries in its Authorization header."""
    rules = "".join(
        f"<{name}>{value}</{name}>"
        for name, values in CORS_RULE.items()
        for value in ([values] if isinstance(values, str) else values)
    )
    body = f"<CORSConfiguration><CORSRule>{rules}</CORSRule></CORSConfiguration>".encode()
    url = urllib.parse.urlsplit(f"{ENDPOINT}/{BUCKET}?cors=")
    sha256 = hashlib.sha256(body).hexdigest()
    now = datetime.now(UTC)
    headers = {
        "Host": url.netloc,
        "Content-Type": "application/xml",
        "Content-MD5": base64.b64encode(hashlib.md5(body).digest()).decode(),  # required by S3
        "x-amz-content-sha256": sha256,
        "x-amz-date": now.strftime("%Y%m%dT%H%M%SZ"),
    }
    # adds the header Authorization: AWS4-HMAC-SHA256 Credential=..., Signature=...
    headers = sign_v4_s3(
        method="PUT",
        url=url,
        region=REGION,
        headers=headers,
        credentials=Credentials(ACCESS_KEY, SECRET_KEY),
        content_sha256=sha256,
        date=now,
    )
    status, _, answer = http(url.geturl(), "PUT", dict(headers), body)
    if status != 200:
        sys.exit(f"S3 error: PUT ?cors answered {status}: {answer.decode(errors='replace')}")


# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -


def presign(s3: Minio, key: str, seconds: int) -> str:
    return s3.presigned_get_object(BUCKET, key, expires=timedelta(seconds=seconds))


# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -


def cmd_setup(s3: Minio) -> None:
    put_bucket_cors()
    rule = Rule(
        ENABLED,
        rule_filter=Filter(prefix="raw/"),
        rule_id="expire-raw-data",
        expiration=Expiration(days=30),
    )
    s3.set_bucket_lifecycle(BUCKET, LifecycleConfig([rule]))
    print(f"Bucket {BUCKET} at {ENDPOINT}")
    print(
        f"  CORS: {CORS_RULE['AllowedMethod']} from {CORS_RULE['AllowedOrigin']}, "
        f"headers {CORS_RULE['AllowedHeader']}, exposes {CORS_RULE['ExposeHeader']}"
    )
    print("  Lifecycle: objects under raw/ expire after 30 days")


# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -


def cmd_upload(s3: Minio, file: str, key: str | None = None) -> None:
    path = Path(file)
    if not path.is_file():
        sys.exit(f"File not found: {file}")
    key = key or ("tiles/" if path.suffix == ".pmtiles" else "raw/") + path.name
    s3.fput_object(BUCKET, key, str(path))  # in parts for large files
    print(f"Uploaded {path.stat().st_size:,} bytes to s3://{BUCKET}/{key}")


# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -


def cmd_list(s3: Minio) -> None:
    for obj in s3.list_objects(BUCKET, recursive=True):
        print(f"{obj.last_modified:%Y-%m-%d %H:%M}  {obj.size:>12,}  {obj.object_name}")


# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -


def cmd_presign(s3: Minio, key: str, seconds: str = "3600") -> None:
    url = presign(s3, key, int(seconds))
    print(f"Pre-signed URL ({seconds} s):\n{url}\n")
    status, _, _ = http(f"{ENDPOINT}/{BUCKET}/{urllib.parse.quote(key)}")
    print(f"Without signature:          {status}  (expected 403: the bucket is private)")
    status, headers, _ = http(url, headers={"Range": "bytes=0-99"})
    print(
        f"Range bytes=0-99:           {status}  {headers.get('Content-Range', '')}"
        "  (expected 206 Partial Content)"
    )
    status, headers, _ = http(
        url,
        "OPTIONS",
        {
            "Origin": MAP_ORIGIN,
            "Access-Control-Request-Method": "GET",
            "Access-Control-Request-Headers": "range",
        },
    )
    print(
        f"CORS preflight from {MAP_ORIGIN}: {status}  "
        f"Access-Control-Allow-Origin: {headers.get('Access-Control-Allow-Origin', '-')}"
    )


# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -


def cmd_map(s3: Minio, key: str, seconds: str = "86400") -> None:
    url = presign(s3, key, int(seconds))
    print(f"Map with the tiles of s3://{BUCKET}/{key} (valid for {seconds} s):")
    print(f"{MAP_ORIGIN}/?tiles={urllib.parse.quote(url, safe='')}")


# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -


def main() -> None:
    parser = argparse.ArgumentParser(
        description="S3 client for the local object storage (SeaweedFS)"
    )
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("setup", help="CORS for the map, lifecycle rule for raw/")
    upload = commands.add_parser("upload", help="upload a file")
    upload.add_argument("file")
    upload.add_argument("key", nargs="?", help="default raw/<name>, tiles/<name> for .pmtiles")
    commands.add_parser("list", help="objects in the bucket")
    for name, seconds, text in (
        ("presign", "3600", "pre-signed URL, tested"),
        ("map", "86400", "address of the map with ?tiles="),
    ):
        command = commands.add_parser(name, help=text)
        command.add_argument("key")
        command.add_argument("seconds", nargs="?", default=seconds, help=f"default {seconds}")
    args = vars(parser.parse_args())
    command = globals()["cmd_" + args.pop("command")]
    try:
        command(client(), **args)
    except (MaxRetryError, ConnectionError, urllib.error.URLError):
        sys.exit(
            f"No answer from {ENDPOINT}. Start SeaweedFS: "
            "docker compose up --detach seaweedfs (in /workspaces/placefinder)"
        )
    except S3Error as error:
        sys.exit(f"S3 error: {error}")


# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

if __name__ == "__main__":
    main()
