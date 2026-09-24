"""One-time interactive login bootstrap for the browser-agent capability suite.

The browser-agent condition drives the real claude.ai and gemini.google.com
web apps with Playwright, using your own Claude Pro / Gemini Pro login
sessions -- not a metered API key. Playwright can't fill in your
credentials (that's off-limits for automation), so this script just opens a
real, visible Chromium window against a persistent profile and waits for
you to log in by hand -- detected by polling the page URL rather than a
terminal keypress, since this is meant to run non-interactively (e.g. via
Claude Code's `!` prefix, which doesn't provide a real stdin).

The profile lives in browser_profiles/, which is gitignored -- it holds
real session cookies for your personal accounts and must never be
committed.

Usage:
  python3 browser_agent_login.py                     # log into both, 10 min each
  python3 browser_agent_login.py --site claude
  python3 browser_agent_login.py --site gemini
  python3 browser_agent_login.py --timeout 600        # wait up to 600s per site (default 300)
"""
import argparse
import os
import time

from playwright.sync_api import sync_playwright

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
PROFILE_DIR = os.path.join(BASE_DIR, "browser_profiles", "main")

SITES = {
    "claude": {
        "url": "https://claude.ai",
        "is_logged_in": lambda url: "claude.ai" in url and "/login" not in url,
    },
    "gemini": {
        "url": "https://gemini.google.com/app",
        "is_logged_in": lambda url: url.startswith("https://gemini.google.com"),
    },
}


def wait_for_login(page, name, site, timeout_s, poll_s=2.0):
    print(f"\n=== {name} ===")
    page.goto(site["url"], wait_until="domcontentloaded")
    print(f"Log in by hand in the Chrome window now (polling for up to {timeout_s:.0f}s).")

    deadline = time.time() + timeout_s
    last_url = None
    while time.time() < deadline:
        url = page.url
        if url != last_url:
            print(f"  [{name}] url -> {url}")
            last_url = url
        if site["is_logged_in"](url):
            print(f"  [{name}] looks logged in.")
            return True
        time.sleep(poll_s)

    print(f"  [{name}] timed out after {timeout_s:.0f}s -- still not logged in (last url: {last_url}).")
    return False


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--site", choices=list(SITES.keys()), default=None,
                         help="Only bootstrap this one site (default: both)")
    parser.add_argument("--timeout", type=float, default=300.0,
                         help="Seconds to wait for login per site (default: 300)")
    args = parser.parse_args()

    sites = {args.site: SITES[args.site]} if args.site else SITES

    os.makedirs(PROFILE_DIR, exist_ok=True)
    results = {}
    with sync_playwright() as pw:
        context = pw.chromium.launch_persistent_context(
            PROFILE_DIR,
            headless=False,
            viewport={"width": 1280, "height": 900},
        )
        page = context.pages[0] if context.pages else context.new_page()
        for name, site in sites.items():
            results[name] = wait_for_login(page, name, site, args.timeout)
        context.close()

    print(f"\nSession state saved in {PROFILE_DIR}")
    for name, ok in results.items():
        print(f"  {name}: {'logged in' if ok else 'NOT confirmed logged in'}")
    print("Re-run this script anytime to verify the login persisted (it should report logged-in immediately).")


if __name__ == "__main__":
    main()
