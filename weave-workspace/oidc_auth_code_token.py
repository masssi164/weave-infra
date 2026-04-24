#!/usr/bin/env python3
import argparse
import base64
import hashlib
import html
import json
import os
import secrets
import sys
import urllib.error
import urllib.parse
import urllib.request
from html.parser import HTMLParser
from http.cookiejar import CookieJar


class _NoCustomSchemeRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        scheme = urllib.parse.urlparse(newurl).scheme.lower()
        if scheme and scheme not in {"http", "https"}:
            return None
        return super().redirect_request(req, fp, code, msg, headers, newurl)


class _FormParser(HTMLParser):
    def __init__(self):
        super().__init__()
        self.forms = []
        self._current = None

    def handle_starttag(self, tag, attrs):
        attrs_dict = dict(attrs)
        if tag == "form":
            self._current = {
                "action": attrs_dict.get("action", ""),
                "method": attrs_dict.get("method", "get").lower(),
                "inputs": {},
            }
        elif tag == "input" and self._current is not None:
            name = attrs_dict.get("name")
            if name:
                self._current["inputs"][name] = attrs_dict.get("value", "")

    def handle_endtag(self, tag):
        if tag == "form" and self._current is not None:
            self.forms.append(self._current)
            self._current = None


class _HttpClient:
    def __init__(self, cafile=None):
        handlers = [urllib.request.HTTPCookieProcessor(CookieJar()), _NoCustomSchemeRedirect()]
        if cafile:
            import ssl

            context = ssl.create_default_context(cafile=cafile)
            handlers.append(urllib.request.HTTPSHandler(context=context))
        self._opener = urllib.request.build_opener(*handlers)

    def request(self, url, data=None, headers=None, method=None):
        request = urllib.request.Request(url, data=data, headers=headers or {}, method=method)
        try:
            return self._opener.open(request)
        except urllib.error.HTTPError as error:
            return error


def _urlsafe_random(size):
    return secrets.token_urlsafe(size)[:size]


def _pkce_challenge(verifier):
    digest = hashlib.sha256(verifier.encode("utf-8")).digest()
    return base64.urlsafe_b64encode(digest).decode("ascii").rstrip("=")


def _read_json(client, url):
    response = client.request(url, headers={"Accept": "application/json"})
    body = response.read().decode("utf-8")
    if response.getcode() != 200:
        raise RuntimeError(f"Failed to fetch {url}: HTTP {response.getcode()} {body[:240]}")
    return json.loads(body)


def _read_form(html_body, base_url):
    parser = _FormParser()
    parser.feed(html_body)
    for form in parser.forms:
        action = urllib.parse.urljoin(base_url, html.unescape(form["action"]))
        fields = dict(form["inputs"])
        keys = set(fields)
        if {"username", "password"}.issubset(keys) or "credentialId" in keys:
            return action, fields
    if parser.forms:
        form = parser.forms[0]
        return urllib.parse.urljoin(base_url, html.unescape(form["action"])), dict(form["inputs"])
    raise RuntimeError("No HTML form found during OIDC login flow.")


def _follow_auth_flow(client, authorization_url, username, password, redirect_uri):
    current_url = authorization_url
    while True:
        response = client.request(current_url, headers={"Accept": "text/html,application/xhtml+xml"})
        body = response.read().decode("utf-8", errors="replace")
        final_url = response.geturl()

        if urllib.parse.urlparse(final_url).scheme not in {"http", "https"}:
            return final_url

        action, fields = _read_form(body, final_url)
        fields.update(
            {
                "username": username,
                "password": password,
                "credentialId": fields.get("credentialId", ""),
                "login": fields.get("login", "Sign In"),
            }
        )
        encoded = urllib.parse.urlencode(fields).encode("utf-8")
        post_response = client.request(
            action,
            data=encoded,
            headers={
                "Accept": "text/html,application/xhtml+xml",
                "Content-Type": "application/x-www-form-urlencoded",
                "Referer": final_url,
            },
            method="POST",
        )
        post_body = post_response.read().decode("utf-8", errors="replace")
        post_url = post_response.geturl()

        if urllib.parse.urlparse(post_url).scheme not in {"http", "https"}:
            return post_url

        if post_response.getcode() >= 400:
            raise RuntimeError(f"OIDC login failed with HTTP {post_response.getcode()}: {post_body[:240]}")

        if "Invalid username or password" in post_body:
            raise RuntimeError("OIDC login rejected the supplied test-user credentials.")

        if post_url == final_url and redirect_uri not in post_body:
            current_url = post_url
        else:
            current_url = post_url


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--issuer", required=True)
    parser.add_argument("--client-id", required=True)
    parser.add_argument("--username", required=True)
    parser.add_argument("--password", required=True)
    parser.add_argument("--scope", required=True)
    parser.add_argument("--ca-file")
    parser.add_argument("--redirect-uri", default="com.massimotter.weave:/oauthredirect")
    args = parser.parse_args()

    client = _HttpClient(cafile=args.ca_file)
    discovery = _read_json(client, urllib.parse.urljoin(args.issuer.rstrip("/") + "/", ".well-known/openid-configuration"))
    authorization_endpoint = discovery["authorization_endpoint"]
    token_endpoint = discovery["token_endpoint"]

    verifier = _urlsafe_random(64)
    state = _urlsafe_random(32)
    nonce = _urlsafe_random(32)
    authorization_url = authorization_endpoint + "?" + urllib.parse.urlencode(
        {
            "client_id": args.client_id,
            "redirect_uri": args.redirect_uri,
            "response_type": "code",
            "scope": args.scope,
            "state": state,
            "nonce": nonce,
            "code_challenge": _pkce_challenge(verifier),
            "code_challenge_method": "S256",
        }
    )

    callback_url = _follow_auth_flow(
        client,
        authorization_url,
        args.username,
        args.password,
        args.redirect_uri,
    )
    parsed_callback = urllib.parse.urlparse(callback_url)
    callback_query = urllib.parse.parse_qs(parsed_callback.query)
    code = (callback_query.get("code") or [""])[0]
    returned_state = (callback_query.get("state") or [""])[0]
    if not code:
        raise RuntimeError(f"OIDC callback did not include an authorization code: {callback_url}")
    if returned_state != state:
        raise RuntimeError("OIDC callback returned an unexpected state value.")

    token_body = urllib.parse.urlencode(
        {
            "grant_type": "authorization_code",
            "client_id": args.client_id,
            "code": code,
            "redirect_uri": args.redirect_uri,
            "code_verifier": verifier,
        }
    ).encode("utf-8")
    token_response = client.request(
        token_endpoint,
        data=token_body,
        headers={
            "Accept": "application/json",
            "Content-Type": "application/x-www-form-urlencoded",
        },
        method="POST",
    )
    token_payload = token_response.read().decode("utf-8")
    if token_response.getcode() != 200:
        raise RuntimeError(
            f"OIDC token exchange failed with HTTP {token_response.getcode()}: {token_payload[:240]}"
        )
    json.dump(json.loads(token_payload), sys.stdout)


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:  # noqa: BLE001
        print(str(exc), file=sys.stderr)
        sys.exit(1)
