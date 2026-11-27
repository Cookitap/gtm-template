# Cookitap CMP: Google Tag Manager template

A tag template for people who can reach Google Tag Manager (GTM) but not the code of the site. The tag sets
consent to denied in Google Consent Mode v2 before any Google tag fires, restores the stored choice of a returning
visitor, and loads the Cookitap banner.

[Cookitap](https://cookitap.com) is a consent management platform: a cookie banner with a consent log. You need
a Cookitap account and a site added in its dashboard; the dashboard gives the site key the tag asks for.

If you can paste code into the `<head>` of the site, do that instead (Cookitap dashboard, install code): only the
code on the page blocks scripts that live outside GTM. Do not use both. When the page already has the Cookitap
code, the tag sees it and does nothing.

## Import

1. Download `template.tpl` from this repository.
2. In GTM open the container of the site, go to Templates and click New in the Tag Templates section.
3. In the editor open the three-dot menu in the top right corner, choose Import and pick `template.tpl`.
4. Click Save and close the editor.

## Tag

1. Tags, New, tag type "Cookitap CMP" (in the Custom section).
2. Enter the site key: 16 letters and digits from the Cookitap dashboard (the `data-ct-site` value of the install
   code), for example `Ex4mpleSiteKey01`.
3. Trigger: "Consent Initialization - All Pages". It is the only trigger that fires before all the others; on "All
   Pages" or "Initialization" Google tags may send data before consent is denied.
4. Advanced Settings, Consent Settings: "No additional consent required".
5. Remove the previous consent banner from the container and from the site (another CMP, a Custom HTML tag with
   a banner).
6. Check in preview (below) and publish the container.

The tags in the container keep following Consent Mode. Google tags have it built in; for the others (Meta,
TikTok, LinkedIn, Hotjar and so on) require consent in their own Consent Settings (`ad_storage` for advertising,
`analytics_storage` for analytics). Without it they fire before the visitor decides.

## Fields

| Field | Default | What it does |
|---|---|---|
| Site key | none | points to the banner configuration and the consent cookie of the site |
| Wait for update | 500 ms | `wait_for_update`: how long Google tags wait for the stored choice |
| Redact ads data | on | `ads_data_redaction` |
| Pass ad click information through URLs | off | `url_passthrough` |

The default is denied everywhere and the tag has no setting for it. Where the banner is shown is the banner area
setting of the site in the Cookitap dashboard (default: everywhere): outside that area the script grants consent
on its own once it loads.

## What the tag does, in order

1. The page already has the Cookitap code: done, it sets nothing.
2. Sends the default state (every consent type denied, everywhere) through the GTM consent APIs, a denied
   default for Microsoft UET, then `ads_data_redaction` and `url_passthrough` as set in the fields.
3. Wrong site key: done, the tag fails and consent stays at the default.
4. The Cookitap script is already running on the page (without the code that sets the default): done, the script
   reports its own state.
5. Reads the consent cookie `ct_<site key>`. If it holds a valid choice, the tag sends it as an update right away,
   so a returning visitor has their consent before the first tag fires.
6. Loads `https://cdn.cookitap.pl/v1/loader.js`. The script shows the banner and sends every choice to GTM as
   a consent update and a `cookitap_consent` event in the `dataLayer` (usable as a trigger).

If the script fails to load, the site keeps working: a new visitor stays at the default state, a returning one at
the choice from the cookie, and no banner shows.

## Limitations

- The Cookitap code on the page together with this tag: the tag usually does nothing, so everything depends on
  where the code sits. Code pasted after the GTM snippet (instead of first in `<head>`) denies consent too late and
  tags on "All Pages" may get ahead of it. Pick one way.
- The tag does not block scripts written into the page outside GTM. They run as without a banner unless marked
  with `type="text/plain" data-ct-category="..."`; automatic blocking needs the code in `<head>`.
- GTM cannot set `referrerpolicy` on a script it loads. A page with the `unsafe-url` policy therefore sends the
  full page address to `cdn.cookitap.pl` in the `Referer` header of that one request.
- A site with a Content Security Policy has to allow `https://cdn.cookitap.pl`, `https://cfg.cookitap.pl` and
  `https://c.cookitap.pl`.
- The cookie permission covers any name, because the name of the consent cookie contains the site key. The tag
  reads `ct_<site key>` only.
- The script picks the banner language (site settings in the dashboard); the tag does not pass one.

## Checking in preview

Click Preview in GTM and enter the address of the site. In Tag Assistant, following
[Google's guide](https://developers.google.com/tag-platform/security/guides/consent-debugging):

- select the earliest Consent event in the Summary; on the Consent tab the "On-page Default" column shows Denied
  for every type;
- click "Accept all" in the banner and select the most recent Consent event: "On-page Update" shows Granted;
- after a reload, Granted is in "On-page Update" before the Initialization event and no banner shows;
- after rejecting and reloading: Denied.

## Development

```bash
node tools/check.mjs
```

Checks the section syntax of the file, known traps of the GTM sandbox (a list, not a parser), the permissions
against the APIs in use, and runs the scenarios of the `___TESTS___` section on a small stand-in for the GTM test
runner (Node 20 or newer, no dependencies). The real runner is in the template editor: the Tests tab, "Run
tests"; the console under the list shows the result of each scenario.

The editor exports the file from the same menu (Export). After a change in the editor, export it, replace
`template.tpl` and run the check.

## Icon

The template has no icon yet. To add one, take a square PNG under 50 kB (Google's style guide asks for 48 to 96 px), encode
it as a data URI and put it in `brand.thumbnail` of the `___INFO___` section:

```bash
printf 'data:image/png;base64,%s' "$(base64 < icon.png | tr -d '\n')"
```

```json
"brand": {
  "id": "brand_dummy",
  "displayName": "Cookitap",
  "thumbnail": "data:image/png;base64,..."
}
```

The same can be done in the template editor: Info tab, the icon next to the name.

## Support

Problems with the template: [GitHub issues](https://github.com/Cookitap/gtm-template/issues) of this repository.
Questions about a Cookitap account or site: support@cookitap.com.

## License

Apache License 2.0, see `LICENSE`.
