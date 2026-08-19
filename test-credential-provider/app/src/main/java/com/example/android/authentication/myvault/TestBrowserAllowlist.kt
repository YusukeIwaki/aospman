/*
 * Copyright 2026 Yusuke Iwaki
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     https://www.apache.org/licenses/LICENSE-2.0
 */
package com.example.android.authentication.myvault

/**
 * Test-provider policy for browser-origin delegation.
 *
 * This is deliberately narrower than a production provider policy: it authorizes only the
 * browser-flavor test APK and its pinned debug certificate. It does not reuse or modify Google
 * Password Manager's allowlist.
 */
object TestBrowserAllowlist {
    const val JSON = """
        {
          "apps": [
            {
              "type": "android",
              "info": {
                "package_name": "com.example.webviewpasskeybrowser.browser",
                "signatures": [
                  {
                    "build": "test-debug",
                    "cert_fingerprint_sha256": "D6:B8:90:EC:A6:F4:70:8A:FF:24:BE:19:17:6C:56:AF:EE:38:D8:D4:D5:61:2A:99:64:F5:F5:81:CC:C2:B4:B1"
                  }
                ]
              }
            }
          ]
        }
    """
}
