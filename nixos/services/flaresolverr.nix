{ pkgs, ... }:
let
  flaresolverrSkill = pkgs.writeText "flaresolverr-skill.md" ''
    ---
    name: flaresolverr
    description: Bypass Cloudflare anti-bot challenges by routing requests through the local flaresolverr instance at localhost:8191.
    version: 1.0.0
    author: chin39
    license: MIT
    platforms: [linux]
    metadata:
      hermes:
        tags: [scraping, http, cloudflare, bot-bypass, proxy]
    prerequisites:
      commands: [curl, jq]
    ---

    # Flaresolverr

    A companion service that uses Chromium + Selenium to solve Cloudflare
    anti-bot challenges and return clean HTML / cookies.

    Available at `http://localhost:8191/v1` from inside this container
    (host networking, host-local bind).

    ## When to use

    - HTTP fetch returned 403 / 503 with `cf-ray:` header or "Just a moment..." HTML
    - Site sits behind Cloudflare's "Checking your browser" interstitial
    - Standard curl / requests yields the challenge page instead of real content
    - You see `cf-chl-bypass` cookies in a response without making progress

    ## When NOT to use

    - Site doesn't use Cloudflare — adds 3-30s per request (always launches a browser)
    - API endpoints with their own auth — use the auth flow, not browser scraping
    - High-volume parallel scraping — single instance, requests serialize

    ## API surface

    POST to `http://localhost:8191/v1` with JSON. Three commands you'll actually use:

    ### `sessions.create` — open a long-lived browser session

    ```bash
    SESSION=$(curl -s -X POST http://localhost:8191/v1 \
      -H 'Content-Type: application/json' \
      -d '{"cmd":"sessions.create","proxy":{"url":"http://192.168.0.240:10809"}}' | jq -r '.session')
    ```

    Pass the proxy here. A session keeps the browser it was created with,
    so a `proxy` block on a later `request.*` that names this session has
    no effect.

    Reuse the session across multiple requests to the same site to keep
    cookies. Each fresh request without a session spawns a new browser
    (~3-5s overhead).

    ### `request.get` — fetch a URL

    ```bash
    curl -s -X POST http://localhost:8191/v1 \
      -H 'Content-Type: application/json' \
      -d "{
        \"cmd\": \"request.get\",
        \"url\": \"https://protected.example.com/page\",
        \"maxTimeout\": 60000,
        \"session\": \"$SESSION\",
        \"proxy\": {\"url\": \"http://192.168.0.240:10809\"}
      }" | jq '.solution.response'    # HTML body
    ```

    The `proxy` block is **required** for a request without a session —
    without it, Chromium fetches direct and bypasses the operator's egress
    proxy. With a session, the proxy given at `sessions.create` applies.
    The URL is fixed; do not change it.

    `maxTimeout` is in **milliseconds**, default 60000. Bump to 120000 for
    slow sites or 30000 to fail-fast.

    ### `request.post` — POST with form-encoded data

    ```bash
    curl -s -X POST http://localhost:8191/v1 \
      -H 'Content-Type: application/json' \
      -d "{
        \"cmd\": \"request.post\",
        \"url\": \"https://protected.example.com/login\",
        \"postData\": \"username=foo&password=bar\",
        \"session\": \"$SESSION\",
        \"proxy\": {\"url\": \"http://192.168.0.240:10809\"}
      }"
    ```

    `postData` is `x-www-form-urlencoded` format only — JSON bodies aren't
    supported. For JSON APIs, don't use flaresolverr; the CF challenge
    only fires on browser-style requests.

    ### `sessions.destroy` — clean up

    ```bash
    curl -s -X POST http://localhost:8191/v1 \
      -H 'Content-Type: application/json' \
      -d "{\"cmd\":\"sessions.destroy\",\"session\":\"$SESSION\"}" > /dev/null
    ```

    Always destroy a session when done; each open session keeps a
    Chromium process running.

    ## Response structure

    ```json
    {
      "status": "ok",
      "message": "",
      "startTimestamp": ...,
      "endTimestamp": ...,
      "version": "...",
      "solution": {
        "url": "https://example.com/page",
        "status": 200,
        "response": "<html>...</html>",
        "cookies": [...],
        "headers": {...},
        "userAgent": "Mozilla/5.0 ..."
      }
    }
    ```

    Failed challenges return `status: error` with a `message` describing
    what went wrong (timeout, captcha required, etc.).

    ## Worked end-to-end example

    Fetching a CF-protected feed:

    ```bash
    # 1. open session (the proxy is fixed for the session's lifetime)
    SESSION=$(curl -s -X POST http://localhost:8191/v1 \
      -H 'Content-Type: application/json' \
      -d '{"cmd":"sessions.create","proxy":{"url":"http://192.168.0.240:10809"}}' | jq -r '.session')

    # 2. fetch through it
    curl -s -X POST http://localhost:8191/v1 \
      -H 'Content-Type: application/json' \
      -d "{\"cmd\":\"request.get\",\"url\":\"https://protected.example.com/feed\",\"maxTimeout\":60000,\"session\":\"$SESSION\"}" \
      | jq -r '.solution.response' > /tmp/feed.html

    # 3. clean up
    curl -s -X POST http://localhost:8191/v1 \
      -H 'Content-Type: application/json' \
      -d "{\"cmd\":\"sessions.destroy\",\"session\":\"$SESSION\"}" > /dev/null

    # work with /tmp/feed.html
    ```

    ## Notes & gotchas

    - **Session reuse matters.** Reusing a session is ~5x faster than
      fresh-browser per request. Use it whenever fetching multiple pages
      from the same site.
    - **Proxy is mandatory** in this deployment — `http://192.168.0.240:10809`.
      Pass it to `sessions.create`, or to each `request.*` that has no session.
    - **No JSON bodies.** `request.post` only accepts form-encoded
      `postData`. For JSON APIs that don't need CF bypass, use plain curl.
    - **Health**: `curl -s http://localhost:8191/` returns
      `FlareSolverr is ready!`. It runs as the host service `flaresolverr`;
      the owner reads its logs with `journalctl -u flaresolverr`.
    - **No HTML in logs**: `LOG_HTML=false` is set on the service, so
      response bodies aren't logged.
    - **Captcha**: `CAPTCHA_SOLVER=none` — flaresolverr can't solve hCaptcha
      or reCAPTCHA. If a site requires those, this tool won't help; pivot
      to manual collection or accept defeat.
    - **Rate limits**: flaresolverr can't bypass Cloudflare rate limiting —
      only the challenge page. Honor the site's terms.
  '';
in
{
  services.flaresolverr = {
    enable = true;
    # The API is unauthenticated; the LAN is trusted to submit fetches.
    openFirewall = true;
  };

  # Chromium ignores these and takes its proxy from each request's `proxy`
  # field. They cover what FlareSolverr's Python layer fetches itself.
  systemd.services.flaresolverr.environment = {
    LOG_LEVEL = "info";
    LOG_HTML = "false";
    CAPTCHA_SOLVER = "none";
    TZ = "Asia/Shanghai";
    http_proxy = "http://192.168.0.240:10809";
    https_proxy = "http://192.168.0.240:10809";
    no_proxy = "127.0.0.1,localhost,192.168.0.0/24";
    HTTP_PROXY = "http://192.168.0.240:10809";
    HTTPS_PROXY = "http://192.168.0.240:10809";
    NO_PROXY = "127.0.0.1,localhost,192.168.0.0/24";
  };

  # ── Install the SKILL.md into hermes' skills tree ────────────────────
  # The hermes gateway scans /data/.hermes/skills/**/SKILL.md at startup
  # and offers each matching skill to the LLM as available context.
  # `install -D` creates parent dirs; ownership matches the hermes user
  # so the gateway can read it through normal group perms.
  #
  # Runs on every nixos-rebuild — the file becomes a fresh copy of the
  # nix-managed content, so editing the skill above + rebuild is the
  # whole update flow. Restart the hermes-agent service afterwards so
  # the gateway re-scans skills.
  system.activationScripts.flaresolverrSkill = {
    text = ''
      mkdir -p /var/lib/hermes/.hermes/skills/local/flaresolverr
      ${pkgs.coreutils}/bin/install -o hermes -g hermes -m 0640 \
        ${flaresolverrSkill} \
        /var/lib/hermes/.hermes/skills/local/flaresolverr/SKILL.md
      chown hermes:hermes /var/lib/hermes/.hermes/skills/local
      chmod 2770 /var/lib/hermes/.hermes/skills/local
    '';
    deps = [ "users" ];
  };
}
