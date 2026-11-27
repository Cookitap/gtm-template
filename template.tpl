___INFO___

{
  "type": "TAG",
  "id": "cvt_temp_public_id",
  "version": 1,
  "securityGroups": [],
  "displayName": "Cookitap CMP",
  "brand": {
    "id": "brand_dummy",
    "displayName": "Cookitap"
  },
  "description": "Cookitap consent banner with Google Consent Mode v2: consent is denied by default before any Google tag fires, and a returning visitor keeps the stored choice. https://cookitap.com",
  "categories": [
    "TAG_MANAGEMENT",
    "PERSONALIZATION"
  ],
  "containerContexts": [
    "WEB"
  ]
}


___TEMPLATE_PARAMETERS___

[
  {
    "type": "TEXT",
    "name": "siteKey",
    "displayName": "Site key",
    "simpleValueType": true,
    "valueHint": "Ex4mpleSiteKey01",
    "help": "16 letters and digits from the Cookitap dashboard: the data-ct-site value of the site\u0027s install code.",
    "alwaysInSummary": true,
    "valueValidators": [
      {
        "type": "NON_EMPTY"
      },
      {
        "type": "REGEX",
        "args": [
          "^[0-9A-Za-z]{16}$"
        ],
        "errorMessage": "A site key is exactly 16 letters and digits."
      }
    ]
  },
  {
    "type": "GROUP",
    "name": "advancedGroup",
    "displayName": "Google settings",
    "groupStyle": "ZIPPY_CLOSED",
    "subParams": [
      {
        "type": "TEXT",
        "name": "waitForUpdate",
        "displayName": "Wait for update",
        "simpleValueType": true,
        "defaultValue": 500,
        "valueUnit": "ms",
        "help": "How long Google tags wait for the visitor\u0027s stored choice before they send data (wait_for_update). 500 is recommended.",
        "valueValidators": [
          {
            "type": "NON_EMPTY"
          },
          {
            "type": "NON_NEGATIVE_NUMBER"
          }
        ]
      },
      {
        "type": "CHECKBOX",
        "name": "adsDataRedaction",
        "checkboxText": "Redact ads data",
        "simpleValueType": true,
        "defaultValue": true,
        "help": "While ad_storage is denied, Google Ads and Floodlight requests carry no ad click identifiers (ads_data_redaction)."
      },
      {
        "type": "CHECKBOX",
        "name": "urlPassthrough",
        "checkboxText": "Pass ad click information through URLs",
        "simpleValueType": true,
        "defaultValue": false,
        "help": "Without consent to cookies, the ad click identifier travels between pages in the URL (url_passthrough). If the container has a Conversion Linker tag, enable it there as well."
      }
    ]
  }
]


___SANDBOXED_JS_FOR_WEB_TEMPLATE___

const copyFromWindow = require('copyFromWindow');
const createQueue = require('createQueue');
const getCookieValues = require('getCookieValues');
const getTimestampMillis = require('getTimestampMillis');
const gtagSet = require('gtagSet');
const injectScript = require('injectScript');
const log = require('logToConsole');
const makeInteger = require('makeInteger');
const makeString = require('makeString');
const setDefaultConsentState = require('setDefaultConsentState');
const setInWindow = require('setInWindow');
const updateConsentState = require('updateConsentState');

const LOADER = 'https://cdn.cookitap.pl/v1/loader.js';
// The order of the gcm field in the consent cookie.
const TYPES = ['ad_storage', 'ad_user_data', 'ad_personalization', 'analytics_storage',
  'functionality_storage', 'personalization_storage', 'security_storage'];
const HEX = '0123456789abcdef';
const BASE36 = HEX + 'ghijklmnopqrstuvwxyz';
const UPPER = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';

// Sandboxed JavaScript has no regular expressions.
const only = (s, chars) => s.split('').every(c => chars.indexOf(c) >= 0);
const positive = (s, max) => {
  const n = makeInteger(s);
  return makeString(n) === s && n > 0 && n <= max ? n : 0;
};

const state = (granted) => {
  const o = {};
  TYPES.forEach((t, i) => {
    o[t] = granted(t, i) ? 'granted' : 'denied';
  });
  return o;
};

// Reads every value the banner script writes: exactly one ct_<siteKey> value in the v1 format, not expired,
// rev and seq in range. Anything else is no consent. The check is looser than the banner script's own, which
// reads the value again once it loads and denies a malformed one.
const storedGcm = (siteKey) => {
  const found = getCookieValues('ct_' + siteKey, false);
  if (found.length !== 1) return;
  const p = found[0].split('.');
  if (p.length < 8 || p[0] !== '1') return;
  const ok = p[1].length === 36 && only(p[1], HEX + '-') &&
      positive(p[2], 9999999999) > getTimestampMillis() / 1000 &&
      p[3].length === 7 && only(p[3], '01') &&
      positive(p[4], 32767) &&
      p[5].length > 0 && p[5].length < 5 && only(p[5], BASE36) &&
      only(p[6], BASE36 + '-~') &&
      positive(p[7], 32767);
  if (ok) return p[3];
};

const uet = (command, value) => createQueue('uetq')('consent', command, {ad_storage: value});

// Denied everywhere: where the banner asks at all is a setting of the site, which the banner script applies.
const setDefaults = () => {
  const wait = makeInteger(data.waitForUpdate);
  const denied = state(() => false);
  denied.wait_for_update = wait >= 0 ? wait : 500;
  setDefaultConsentState(denied);
  uet('default', 'denied');
};

// Set by the Cookitap code of the page, or by this tag: the default is in place and the banner loads.
if (copyFromWindow('cookitapSnippet')) {
  log('Cookitap: consent is already set up on this page, the tag does nothing');
  return data.gtmOnSuccess();
}

setDefaults();
if (data.adsDataRedaction) gtagSet({ads_data_redaction: true});
if (data.urlPassthrough) gtagSet({url_passthrough: true});

const siteKey = data.siteKey;
if (typeof siteKey !== 'string' || siteKey.length !== 16 || !only(siteKey, BASE36 + UPPER)) {
  log('Cookitap: wrong site key, consent stays denied');
  return data.gtmOnFailure();
}
setInWindow('cookitapSnippet', {v: 1}, true);
// A banner script already on the page keeps its own, possibly narrower, state.
const running = copyFromWindow('cookitap');
if (running && running.version) return data.gtmOnSuccess();

const gcm = storedGcm(siteKey);
if (gcm) {
  updateConsentState(state((t, i) => gcm.charAt(i) === '1'));
  uet('update', gcm.charAt(0) === '1' ? 'granted' : 'denied');
}

setInWindow('cookitapSite', siteKey, true);
injectScript(LOADER, undefined, () => log('Cookitap: failed to load', LOADER), LOADER);
// Not after the script loads: Tag Manager applies the default once this tag is done.
data.gtmOnSuccess();


___WEB_PERMISSIONS___

[
  {
    "instance": {
      "key": {
        "publicId": "access_consent",
        "versionId": "1"
      },
      "param": [
        {
          "key": "consentTypes",
          "value": {
            "type": 2,
            "listItem": [
              {
                "type": 3,
                "mapKey": [
                  {
                    "type": 1,
                    "string": "consentType"
                  },
                  {
                    "type": 1,
                    "string": "read"
                  },
                  {
                    "type": 1,
                    "string": "write"
                  }
                ],
                "mapValue": [
                  {
                    "type": 1,
                    "string": "ad_storage"
                  },
                  {
                    "type": 8,
                    "boolean": false
                  },
                  {
                    "type": 8,
                    "boolean": true
                  }
                ]
              },
              {
                "type": 3,
                "mapKey": [
                  {
                    "type": 1,
                    "string": "consentType"
                  },
                  {
                    "type": 1,
                    "string": "read"
                  },
                  {
                    "type": 1,
                    "string": "write"
                  }
                ],
                "mapValue": [
                  {
                    "type": 1,
                    "string": "ad_user_data"
                  },
                  {
                    "type": 8,
                    "boolean": false
                  },
                  {
                    "type": 8,
                    "boolean": true
                  }
                ]
              },
              {
                "type": 3,
                "mapKey": [
                  {
                    "type": 1,
                    "string": "consentType"
                  },
                  {
                    "type": 1,
                    "string": "read"
                  },
                  {
                    "type": 1,
                    "string": "write"
                  }
                ],
                "mapValue": [
                  {
                    "type": 1,
                    "string": "ad_personalization"
                  },
                  {
                    "type": 8,
                    "boolean": false
                  },
                  {
                    "type": 8,
                    "boolean": true
                  }
                ]
              },
              {
                "type": 3,
                "mapKey": [
                  {
                    "type": 1,
                    "string": "consentType"
                  },
                  {
                    "type": 1,
                    "string": "read"
                  },
                  {
                    "type": 1,
                    "string": "write"
                  }
                ],
                "mapValue": [
                  {
                    "type": 1,
                    "string": "analytics_storage"
                  },
                  {
                    "type": 8,
                    "boolean": false
                  },
                  {
                    "type": 8,
                    "boolean": true
                  }
                ]
              },
              {
                "type": 3,
                "mapKey": [
                  {
                    "type": 1,
                    "string": "consentType"
                  },
                  {
                    "type": 1,
                    "string": "read"
                  },
                  {
                    "type": 1,
                    "string": "write"
                  }
                ],
                "mapValue": [
                  {
                    "type": 1,
                    "string": "functionality_storage"
                  },
                  {
                    "type": 8,
                    "boolean": false
                  },
                  {
                    "type": 8,
                    "boolean": true
                  }
                ]
              },
              {
                "type": 3,
                "mapKey": [
                  {
                    "type": 1,
                    "string": "consentType"
                  },
                  {
                    "type": 1,
                    "string": "read"
                  },
                  {
                    "type": 1,
                    "string": "write"
                  }
                ],
                "mapValue": [
                  {
                    "type": 1,
                    "string": "personalization_storage"
                  },
                  {
                    "type": 8,
                    "boolean": false
                  },
                  {
                    "type": 8,
                    "boolean": true
                  }
                ]
              },
              {
                "type": 3,
                "mapKey": [
                  {
                    "type": 1,
                    "string": "consentType"
                  },
                  {
                    "type": 1,
                    "string": "read"
                  },
                  {
                    "type": 1,
                    "string": "write"
                  }
                ],
                "mapValue": [
                  {
                    "type": 1,
                    "string": "security_storage"
                  },
                  {
                    "type": 8,
                    "boolean": false
                  },
                  {
                    "type": 8,
                    "boolean": true
                  }
                ]
              },
              {
                "type": 3,
                "mapKey": [
                  {
                    "type": 1,
                    "string": "consentType"
                  },
                  {
                    "type": 1,
                    "string": "read"
                  },
                  {
                    "type": 1,
                    "string": "write"
                  }
                ],
                "mapValue": [
                  {
                    "type": 1,
                    "string": "wait_for_update"
                  },
                  {
                    "type": 8,
                    "boolean": false
                  },
                  {
                    "type": 8,
                    "boolean": true
                  }
                ]
              }
            ]
          }
        }
      ]
    },
    "clientAnnotations": {
      "isEditedByUser": true
    },
    "isRequired": true
  },
  {
    "instance": {
      "key": {
        "publicId": "write_data_layer",
        "versionId": "1"
      },
      "param": [
        {
          "key": "keyPatterns",
          "value": {
            "type": 2,
            "listItem": [
              {
                "type": 1,
                "string": "ads_data_redaction"
              },
              {
                "type": 1,
                "string": "url_passthrough"
              }
            ]
          }
        }
      ]
    },
    "clientAnnotations": {
      "isEditedByUser": true
    },
    "isRequired": true
  },
  {
    "instance": {
      "key": {
        "publicId": "inject_script",
        "versionId": "1"
      },
      "param": [
        {
          "key": "urls",
          "value": {
            "type": 2,
            "listItem": [
              {
                "type": 1,
                "string": "https://cdn.cookitap.pl/v1/loader.js"
              }
            ]
          }
        }
      ]
    },
    "clientAnnotations": {
      "isEditedByUser": true
    },
    "isRequired": true
  },
  {
    "instance": {
      "key": {
        "publicId": "access_globals",
        "versionId": "1"
      },
      "param": [
        {
          "key": "keys",
          "value": {
            "type": 2,
            "listItem": [
              {
                "type": 3,
                "mapKey": [
                  {
                    "type": 1,
                    "string": "key"
                  },
                  {
                    "type": 1,
                    "string": "read"
                  },
                  {
                    "type": 1,
                    "string": "write"
                  },
                  {
                    "type": 1,
                    "string": "execute"
                  }
                ],
                "mapValue": [
                  {
                    "type": 1,
                    "string": "cookitapSnippet"
                  },
                  {
                    "type": 8,
                    "boolean": true
                  },
                  {
                    "type": 8,
                    "boolean": true
                  },
                  {
                    "type": 8,
                    "boolean": false
                  }
                ]
              },
              {
                "type": 3,
                "mapKey": [
                  {
                    "type": 1,
                    "string": "key"
                  },
                  {
                    "type": 1,
                    "string": "read"
                  },
                  {
                    "type": 1,
                    "string": "write"
                  },
                  {
                    "type": 1,
                    "string": "execute"
                  }
                ],
                "mapValue": [
                  {
                    "type": 1,
                    "string": "cookitapSite"
                  },
                  {
                    "type": 8,
                    "boolean": false
                  },
                  {
                    "type": 8,
                    "boolean": true
                  },
                  {
                    "type": 8,
                    "boolean": false
                  }
                ]
              },
              {
                "type": 3,
                "mapKey": [
                  {
                    "type": 1,
                    "string": "key"
                  },
                  {
                    "type": 1,
                    "string": "read"
                  },
                  {
                    "type": 1,
                    "string": "write"
                  },
                  {
                    "type": 1,
                    "string": "execute"
                  }
                ],
                "mapValue": [
                  {
                    "type": 1,
                    "string": "cookitap"
                  },
                  {
                    "type": 8,
                    "boolean": true
                  },
                  {
                    "type": 8,
                    "boolean": false
                  },
                  {
                    "type": 8,
                    "boolean": false
                  }
                ]
              },
              {
                "type": 3,
                "mapKey": [
                  {
                    "type": 1,
                    "string": "key"
                  },
                  {
                    "type": 1,
                    "string": "read"
                  },
                  {
                    "type": 1,
                    "string": "write"
                  },
                  {
                    "type": 1,
                    "string": "execute"
                  }
                ],
                "mapValue": [
                  {
                    "type": 1,
                    "string": "uetq"
                  },
                  {
                    "type": 8,
                    "boolean": true
                  },
                  {
                    "type": 8,
                    "boolean": true
                  },
                  {
                    "type": 8,
                    "boolean": false
                  }
                ]
              }
            ]
          }
        }
      ]
    },
    "clientAnnotations": {
      "isEditedByUser": true
    },
    "isRequired": true
  },
  {
    "instance": {
      "key": {
        "publicId": "get_cookies",
        "versionId": "1"
      },
      "param": [
        {
          "key": "cookieAccess",
          "value": {
            "type": 1,
            "string": "any"
          }
        }
      ]
    },
    "clientAnnotations": {
      "isEditedByUser": true
    },
    "isRequired": true
  },
  {
    "instance": {
      "key": {
        "publicId": "logging",
        "versionId": "1"
      },
      "param": [
        {
          "key": "environments",
          "value": {
            "type": 1,
            "string": "debug"
          }
        }
      ]
    },
    "clientAnnotations": {
      "isEditedByUser": true
    },
    "isRequired": true
  }
]


___TESTS___

scenarios:
- name: first visit sets denied and loads the banner
  code: |-
    const page = arrange({});
    runCode(mockData);

    assertApi('setDefaultConsentState').wasCalledWith(DENIED);
    assertThat(page.updates).isEqualTo([]);
    assertApi('gtagSet').wasCalledWith({ads_data_redaction: true});
    assertThat(page.uetq).isEqualTo(['consent', 'default', {ad_storage: 'denied'}]);
    assertThat(page.win.cookitapSnippet).isEqualTo({v: 1});
    assertApi('setInWindow').wasCalledWith('cookitapSite', 'Ex4mpleSiteKey01', true);
    assertThat(page.injected).isEqualTo(['https://cdn.cookitap.pl/v1/loader.js']);
    assertApi('gtmOnSuccess').wasCalled();
- name: returning visitor gets the stored consent
  code: |-
    const page = arrange({cookies: [cookie('1001000', NOW / 1000 + 60)]});
    runCode(mockData);

    assertApi('setDefaultConsentState').wasCalledWith(DENIED);
    assertApi('getCookieValues').wasCalledWith('ct_Ex4mpleSiteKey01', false);
    assertThat(page.updates).isEqualTo([{
      ad_storage: 'granted',
      ad_user_data: 'denied',
      ad_personalization: 'denied',
      analytics_storage: 'granted',
      functionality_storage: 'denied',
      personalization_storage: 'denied',
      security_storage: 'denied'
    }]);
    assertThat(page.uetq.length).isEqualTo(6);
    assertThat(page.uetq[5]).isEqualTo({ad_storage: 'granted'});
    assertApi('gtmOnSuccess').wasCalled();
- name: every shape the banner script writes is read
  code: |-
    const good = cookie('0001000', NOW / 1000 + 60);
    [
      good,
      good.replace('ga1~ads0', ''),
      good.replace('ga1~ads0', 'google-analytics-41'),
      good.replace('.3.7.', '.32767.zzzz.'),
      good.replace('ads0.2', 'ads0.32767'),
      good + '.future'
    ].forEach(value => {
      const page = arrange({cookies: [value]});
      runCode(mockData);
      assertThat(page.updates.length, value).isEqualTo(1);
      assertThat(page.updates[0].analytics_storage).isEqualTo('granted');
      assertThat(page.updates[0].ad_storage).isEqualTo('denied');
    });
- name: expired, duplicated or malformed cookie is no consent
  code: |-
    const good = cookie('1111111', NOW / 1000 + 60);
    [
      [cookie('1111111', NOW / 1000 - 1)],
      [good, good],
      [good.replace('1.', '2.')],
      [good.replace('.3.7.', '.0.7.')],
      [good.replace('.3.7.', '.03.7.')],
      [good.replace('.3.7.', '.32768.7.')],
      [good.replace('.3.7.', '.3.7!.')],
      [good.replace('.3.7.', '.3.zzzzz.')],
      [good.replace('1111111', '111111')],
      [good.replace('3f2b8c1e', '3F2B8C1E')],
      [good.replace('ga1~ads0', 'GA1')],
      [good.replace('ads0.2', 'ads0.0')],
      [good.replace('ads0.2', 'ads0.32768')],
      [good.replace('ads0.2', 'ads0')],
      ['1.x']
    ].forEach(cookies => {
      const page = arrange({cookies: cookies});
      runCode(mockData);
      assertThat(page.updates, cookies[0]).isEqualTo([]);
      assertThat(page.injected.length).isEqualTo(1);
    });
- name: wait for update follows the field
  code: |-
    const waits = [];
    ['800', '0', 500, 'soon'].forEach(value => {
      arrange({});
      mock('setDefaultConsentState', o => {
        waits.push(o.wait_for_update);
      });
      mockData.waitForUpdate = value;
      runCode(mockData);
    });

    assertThat(waits).isEqualTo([800, 0, 500, 500]);
- name: page with the Cookitap code is left alone
  code: |-
    const page = arrange({win: {cookitapSnippet: {v: 1, gtmBefore: false}}, cookies: [cookie('1111111', NOW / 1000 + 60)]});
    runCode(mockData);

    assertApi('setDefaultConsentState').wasNotCalled();
    assertApi('gtagSet').wasNotCalled();
    assertThat(page.updates).isEqualTo([]);
    assertThat(page.injected).isEqualTo([]);
    assertThat(page.uetq).isEqualTo([]);
    assertApi('gtmOnSuccess').wasCalled();
- name: running banner script keeps its own state
  code: |-
    const page = arrange({win: {cookitap: {version: '0.1.0'}}, cookies: [cookie('1111111', NOW / 1000 + 60)]});
    runCode(mockData);

    assertApi('setDefaultConsentState').wasCalledWith(DENIED);
    assertThat(page.updates).isEqualTo([]);
    assertThat(page.injected).isEqualTo([]);
    assertApi('gtmOnSuccess').wasCalled();
- name: wrong site key only sets denied
  code: |-
    ['short', 'Ex4mpleSiteKey0!', undefined, 1234567890123456].forEach(key => {
      const page = arrange({cookies: [cookie('1111111', NOW / 1000 + 60)]});
      mockData.siteKey = key;
      runCode(mockData);
      assertThat(page.updates).isEqualTo([]);
      assertThat(page.injected).isEqualTo([]);
      assertThat(page.win.cookitapSite).isUndefined();
      assertThat(page.win.cookitapSnippet).isUndefined();
    });

    assertApi('setDefaultConsentState').wasCalledWith(DENIED);
    assertApi('gtmOnFailure').wasCalled();
    assertApi('gtmOnSuccess').wasNotCalled();
- name: url passthrough and redaction follow the fields
  code: |-
    arrange({});
    mockData.adsDataRedaction = false;
    mockData.urlPassthrough = true;
    runCode(mockData);

    assertApi('gtagSet').wasCalledWith({url_passthrough: true});
    assertApi('gtagSet').wasNotCalledWith({ads_data_redaction: true});
setup: |-
  const NOW = 1800000000000;
  const mockData = {
    siteKey: 'Ex4mpleSiteKey01',
    waitForUpdate: '500',
    adsDataRedaction: true,
    urlPassthrough: false
  };
  const DENIED = {
    ad_storage: 'denied',
    ad_user_data: 'denied',
    ad_personalization: 'denied',
    analytics_storage: 'denied',
    functionality_storage: 'denied',
    personalization_storage: 'denied',
    security_storage: 'denied',
    wait_for_update: 500
  };
  const cookie = (gcm, exp) => '1.3f2b8c1e-7a4d-4e6f-9b0a-5c1d2e3f4a5b.' + exp + '.' + gcm + '.3.7.ga1~ads0.2';

  // A fake page: window keys, the consent cookie values, and what the tag left behind.
  const arrange = (o) => {
    const page = {win: o.win || {}, uetq: [], injected: [], updates: []};
    mock('getTimestampMillis', NOW);
    mock('copyFromWindow', key => page.win[key]);
    mock('setInWindow', (key, value) => {
      page.win[key] = value;
      return true;
    });
    mock('createQueue', name => (a, b, c) => {
      page.uetq.push(a, b, c);
    });
    mock('getCookieValues', name => o.cookies || []);
    mock('updateConsentState', state => {
      page.updates.push(state);
    });
    mock('injectScript', url => {
      page.injected.push(url);
    });
    return page;
  };


___NOTES___

Cookitap CMP, https://github.com/Cookitap/gtm-template
