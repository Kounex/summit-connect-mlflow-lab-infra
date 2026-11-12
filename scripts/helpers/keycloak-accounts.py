"""Keycloak Admin REST operations; no password/token values are written to stdout."""
import base64
import json
import os
from pathlib import Path
import subprocess
import sys
import uuid
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode, urlsplit, quote
from urllib.request import Request, urlopen


def oc_json(*args):
    return json.loads(subprocess.check_output(["oc", *args, "-o", "json"]))


def main():
    mode, directory, first, last = sys.argv[1:]
    destination = Path(directory).resolve()
    if destination.is_relative_to(Path.cwd().resolve()):
        raise ValueError("Credentials must be outside this repository")
    destination.mkdir(parents=True, exist_ok=True, mode=0o700)
    os.chmod(destination, 0o700)
    providers = oc_json("get", "oauth", "cluster")["spec"]["identityProviders"]
    idp_name = os.environ.get("KEYCLOAK_IDP", "rhbk")
    provider = next(p for p in providers if p["name"] == idp_name and p["type"] == "OpenID")
    issuer = provider["openID"]["issuer"].rstrip("/")
    origin, separator, realm = issuer.rpartition("/realms/")
    if not separator or urlsplit(origin).scheme != "https":
        raise ValueError("Expected an HTTPS Keycloak realm issuer")
    secret = oc_json("get", "secret", os.environ.get("KEYCLOAK_ADMIN_SECRET", "keycloak-initial-admin"),
                     "-n", os.environ.get("KEYCLOAK_NAMESPACE", "keycloak"))["data"]
    credentials = {key: base64.b64decode(secret[key]).decode() for key in ("username", "password")}
    payload = urlencode(dict(client_id="admin-cli", grant_type="password", **credentials)).encode()
    def authenticate():
        with urlopen(Request(origin + "/realms/master/protocol/openid-connect/token", data=payload), timeout=30) as response:
            return json.load(response)["access_token"]

    token = authenticate()

    def api(method, path, body=None):
        nonlocal token
        request = Request(origin + "/admin/realms/" + quote(realm, safe="") + path,
                          data=None if body is None else json.dumps(body).encode(), method=method,
                          headers={"Authorization": "Bearer " + token, "Content-Type": "application/json"})
        try:
            response = urlopen(request, timeout=30)
        except HTTPError as error:
            if error.code != 401:
                raise
            token = authenticate()
            request.add_header("Authorization", "Bearer " + token)
            response = urlopen(request, timeout=30)
        with response:
            content = response.read()
            return json.loads(content) if content else None

    for number in range(int(first), int(last) + 1):
        username = f"user{number}"
        receipt_path = destination / f"{username}.json"
        receipt = json.loads(receipt_path.read_text()) if receipt_path.exists() else None
        if receipt and (receipt.get("issuer"), receipt.get("username"), receipt.get("owner")) != (issuer, username, "darmstadt-demo"):
            raise ValueError(f"Receipt mismatch for {username}")
        existing = api("GET", "/users?" + urlencode(dict(username=username, exact="true")))
        if len(existing) > 1:
            raise ValueError(f"Ambiguous account {username}")
        user = existing[0] if existing else None
        if user and (not receipt or receipt.get("id") != user["id"]):
            raise ValueError(f"Refusing to adopt/reset/delete an unrecorded account: {username}")
        if mode == "delete":
            if not receipt:
                raise ValueError(f"No ownership receipt for {username}")
            # Remove only the OAuth records associated with this exact OpenShift user.
            users = oc_json("get", "users")["items"]
            oc_user = next((u for u in users if u["metadata"]["name"] == username), None)
            if oc_user:
                identities = oc_user.get("identities", [])
                if any(identity != idp_name + ":" + receipt["id"] for identity in identities):
                    raise ValueError(f"Unexpected identity mapping on {username}; inspect before cleanup")
            if user:
                api("DELETE", "/users/" + quote(user["id"], safe=""))
            # Keycloak logout alone does not revoke existing OpenShift OAuth tokens.
            for kind in ("oauthaccesstokens", "oauthauthorizetokens"):
                for item in oc_json("get", kind)["items"]:
                    if item.get("userName") == username:
                        result = subprocess.run(["oc", "delete", kind, item["metadata"]["name"]], capture_output=True)
                        if result.returncode:
                            raise ValueError(f"OAuth token cleanup failed for {username}; inspect the cluster")
            if oc_user:
                for identity in identities:
                    subprocess.run(["oc", "delete", "identity", identity], check=True, stdout=subprocess.DEVNULL)
                subprocess.run(["oc", "delete", "user", username], check=True, stdout=subprocess.DEVNULL)
            # Retain the receipt for audit. Recreation gets a new ID and the same demo password.
            print(f"{username}: deleted owned account and OpenShift identity records")
            continue
        representation = json.loads(Path("manifests/40-accounts/user.json").read_text().replace("${PARTICIPANT}", username))
        credential = representation["credentials"][0]
        if not user:
            receipt = dict(owner="darmstadt-demo", issuer=issuer, username=username, id=str(uuid.uuid4()), password=credential["value"])
            # Persist the ownership ID before create so retries can recognize the account.
            with open(receipt_path, "w", opener=lambda path, flags: os.open(path, flags, 0o600)) as output:
                json.dump(receipt, output, indent=2)
                output.write("\n")
            os.chmod(receipt_path, 0o600)
            representation["id"] = receipt["id"]
            api("POST", "/users", representation)
            user = api("GET", "/users?" + urlencode(dict(username=username, exact="true")))[0]
            receipt["id"] = user["id"]
            receipt_path.write_text(json.dumps(receipt, indent=2) + "\n")
            print(f"{username}: created; private credentials: {receipt_path}")
        else:
            api("PUT", "/users/" + quote(user["id"], safe="") + "/reset-password", credential)
            receipt["password"] = credential["value"]
            receipt_path.write_text(json.dumps(receipt, indent=2) + "\n")
            os.chmod(receipt_path, 0o600)
            print(f"{username}: recorded account reset to the declared demo password")


if __name__ == "__main__":
    try:
        main()
    except HTTPError as error:
        sys.exit(f"Keycloak HTTP {error.code}; inspect server logs (no credential-bearing response printed)")
    except URLError:
        sys.exit("Keycloak HTTPS connection failed. Check connectivity and local CA trust (SSL_CERT_FILE).")
    except (ValueError, KeyError, StopIteration) as error:
        sys.exit(str(error) or "Keycloak IDP configuration not found")
